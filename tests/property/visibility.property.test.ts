// Visibility properties (spec 00, task 32). Each property carries the comment
// `// Feature: 00-database-foundation, Property N: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every
// assertion, and runs inside withRolledBackTx.
//
// The file is split in two parts so that properties 2, 3 and 5 (tasks 32.2 to
// 32.4) can reuse the same world model:
//   1. Shared model: simulated users, the stranger test, item lists.
//   2. One `describe` block per property.
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import {
  insertScenario,
  pick,
  resolveViewer,
  scenarioArb,
  viewerArb,
  type Fixture,
  type FixtureProfile,
  type ViewerSpec,
} from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

// ---------------------------------------------------------------------------
// 1. Shared model
// ---------------------------------------------------------------------------

/** A simulated API caller: signed out, or one login with the profiles it controls. */
export interface SimUser {
  role: "anon" | "authenticated";
  sub?: string;
  /** Profiles this login owns or manages (empty for anon). */
  controlled: FixtureProfile[];
}

/** One item (content item or vouch) as the visibility checks see it. */
export interface ItemFacts {
  id: string;
  kind: "content" | "vouch";
  ownerId: string;
  subjectId: string | null;
  /** True when anyone (including signed out visitors) may see it right now. */
  isPublic: boolean;
}

/** Resolves a generated viewer to a simulated caller: signed out, or a login and all it controls. */
export function simulatedUser(fixture: Fixture, viewer: ViewerSpec): SimUser {
  const resolved = resolveViewer(fixture, viewer);
  if (resolved.role === "anon" || resolved.sub === undefined) return { role: "anon", controlled: [] };
  const sub = resolved.sub;
  return {
    role: "authenticated",
    sub,
    controlled: fixture.profiles.filter((p) => p.controllerIds.includes(sub)),
  };
}

/** All items of the fixture. An expired story is never public (Req 20.4). */
export function itemFacts(fixture: Fixture): ItemFacts[] {
  const content = fixture.content.map(
    (c): ItemFacts => ({
      id: c.id,
      kind: "content",
      ownerId: c.ownerId,
      subjectId: null,
      isPublic: c.audience === "public" && !c.expired,
    }),
  );
  const vouches = fixture.vouches.map(
    (v): ItemFacts => ({
      id: v.id,
      kind: "vouch",
      ownerId: v.authorId,
      subjectId: v.subjectId,
      isPublic: v.audience === "public",
    }),
  );
  return [...content, ...vouches];
}

/**
 * True when `user` is a stranger to `item`. Deliberately conservative: a user
 * is NOT a stranger if any profile it controls is the owner or the vouch
 * subject, has any relationship row with the owner (any status, either
 * direction), is in any circle the owner owns, or is in any group. Fewer
 * strangers only means fewer assertions, never a false failure.
 */
export function isStranger(fixture: Fixture, user: SimUser, item: ItemFacts): boolean {
  for (const profile of user.controlled) {
    if (profile.id === item.ownerId || profile.id === item.subjectId) return false;
    const related = fixture.relationships.some(
      (r) =>
        (r.requesterId === profile.id && r.targetId === item.ownerId) ||
        (r.targetId === profile.id && r.requesterId === item.ownerId),
    );
    if (related) return false;
    const inOwnerCircle = fixture.memberships.some(
      (m) =>
        m.memberId === profile.id &&
        fixture.circles.some((c) => c.id === m.circleId && c.ownerId === item.ownerId),
    );
    if (inOwnerCircle) return false;
    if (fixture.groups.some((g) => g.memberIds.includes(profile.id))) return false;
  }
  return true;
}

/** Items that `user` must not be able to see: non public items it is a stranger to. */
export function hiddenFrom(fixture: Fixture, user: SimUser, items: ItemFacts[]): ItemFacts[] {
  return items.filter((item) => !item.isPublic && isStranger(fixture, user, item));
}

/** Runs `fn` in a savepoint and returns the error code it raised, or null if it did not raise. */
export async function errorCodeOf(client: Client, fn: () => Promise<unknown>): Promise<string | null> {
  await client.query("savepoint expect_error");
  try {
    await fn();
    await client.query("release savepoint expect_error");
    return null;
  } catch (error) {
    await client.query("rollback to savepoint expect_error");
    await client.query("release savepoint expect_error");
    const code = (error as { code?: unknown }).code;
    return typeof code === "string" ? code : "unknown";
  }
}

/** One `connections` item with what Property 2 needs to know about it. */
interface ConnectionsItem {
  id: string;
  kind: "content" | "vouch";
  ownerId: string;
  subjectId: string | null;
  expired: boolean;
  /** True when the item is nested under a parent, whose own audience also applies (Req 20.13). */
  nested: boolean;
}

/** All items stored with audience `connections`. */
export function connectionsItems(fixture: Fixture): ConnectionsItem[] {
  const content = fixture.content
    .filter((c) => c.audience === "connections")
    .map(
      (c): ConnectionsItem => ({
        id: c.id,
        kind: "content",
        ownerId: c.ownerId,
        subjectId: null,
        expired: c.expired,
        nested: c.spec.parentPick !== null,
      }),
    );
  const vouches = fixture.vouches
    .filter((v) => v.audience === "connections")
    .map(
      (v): ConnectionsItem => ({
        id: v.id,
        kind: "vouch",
        ownerId: v.authorId,
        subjectId: v.subjectId,
        expired: false,
        nested: false,
      }),
    );
  return [...content, ...vouches];
}

/**
 * True when `viewerId` is in the owner's connections audience: an accepted
 * connection with the owner, or, for a business owner, an accepted follow.
 */
export function inConnectionsAudience(fixture: Fixture, ownerId: string, viewerId: string): boolean {
  const owner = fixture.profiles.find((p) => p.id === ownerId);
  return fixture.relationships.some((r) => {
    if (r.status !== "accepted") return false;
    if (r.type === "connection") {
      return (
        (r.requesterId === ownerId && r.targetId === viewerId) ||
        (r.requesterId === viewerId && r.targetId === ownerId)
      );
    }
    return owner?.type === "business" && r.requesterId === viewerId && r.targetId === ownerId;
  });
}

/**
 * What `can_view` must answer for a `connections` item: true, false, or
 * undefined when the model cannot tell (a nested item also depends on its parent).
 */
export function expectedConnectionsView(
  fixture: Fixture,
  viewerId: string | null,
  item: ConnectionsItem,
): boolean | undefined {
  if (viewerId === null) return false;
  if (viewerId === item.ownerId || viewerId === item.subjectId) return true;
  if (!inConnectionsAudience(fixture, item.ownerId, viewerId)) return false;
  if (item.expired) return false;
  return item.nested ? undefined : true;
}

/** One item stored with audience `circles`, with the circles it is linked to. */
interface CircleItem {
  id: string;
  kind: "content" | "vouch";
  ownerId: string;
  subjectId: string | null;
  expired: boolean;
  nested: boolean;
  /** Linked circles that are hand picked (rows of `circle_members`). */
  circleIds: string[];
  /** True when the item is also linked to the owner's all followers circle. */
  allFollowers: boolean;
}

/** All items stored with audience `circles`, generated ones and the all followers ones added by the test. */
export function circleItems(fixture: Fixture, allFollowersItems: string[] = []): CircleItem[] {
  const content = fixture.content
    .filter((c) => c.audience === "circles")
    .map(
      (c): CircleItem => ({
        id: c.id,
        kind: "content",
        ownerId: c.ownerId,
        subjectId: null,
        expired: c.expired,
        nested: c.spec.parentPick !== null,
        circleIds: c.circleIds,
        allFollowers: false,
      }),
    );
  const vouches = fixture.vouches
    .filter((v) => v.audience === "circles")
    .map(
      (v): CircleItem => ({
        id: v.id,
        kind: "vouch",
        ownerId: v.authorId,
        subjectId: v.subjectId,
        expired: false,
        nested: false,
        circleIds: v.circleIds,
        allFollowers: false,
      }),
    );
  // The extra items are one status per business, linked to its all followers circle.
  const extra = allFollowersItems.map(
    (id, i): CircleItem => ({
      id,
      kind: "content",
      ownerId: fixture.businesses[i]!.id,
      subjectId: null,
      expired: false,
      nested: false,
      circleIds: [],
      allFollowers: true,
    }),
  );
  return [...content, ...vouches, ...extra];
}

/** True when `viewerId` is in at least one circle linked to `item`; deleted circles no longer count. */
export function inLinkedCircle(
  fixture: Fixture,
  viewerId: string,
  item: CircleItem,
  deleted: ReadonlySet<string>,
): boolean {
  const member = item.circleIds.some(
    (circleId) =>
      !deleted.has(circleId) &&
      fixture.memberships.some((m) => m.circleId === circleId && m.memberId === viewerId),
  );
  if (member) return true;
  return (
    item.allFollowers &&
    fixture.relationships.some(
      (r) =>
        r.type === "follow" &&
        r.status === "accepted" &&
        r.requesterId === viewerId &&
        r.targetId === item.ownerId,
    )
  );
}

/**
 * What `can_view` must answer for a `circles` item: true, false, or undefined
 * when the model cannot tell (a nested item also depends on its parent).
 */
export function expectedCircleView(
  fixture: Fixture,
  viewerId: string | null,
  item: CircleItem,
  deleted: ReadonlySet<string>,
): boolean | undefined {
  if (viewerId === null) return false;
  if (viewerId === item.ownerId || viewerId === item.subjectId) return true;
  if (!inLinkedCircle(fixture, viewerId, item, deleted)) return false;
  if (item.expired) return false;
  return item.nested ? undefined : true;
}

/** Checks can_view and RLS reads of `items` for the current caller against the model. */
async function checkCircleItems(
  client: Client,
  fixture: Fixture,
  user: SimUser,
  items: CircleItem[],
  deleted: ReadonlySet<string>,
  phase: string,
): Promise<void> {
  const viewers: (string | null)[] = [null, ...user.controlled.map((p) => p.id)];
  await asUser(client, user.role, user.sub);
  try {
    for (const viewer of viewers) {
      const res = await client.query<{ id: string; ok: boolean }>(
        "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
        [viewer, items.map((i) => i.id)],
      );
      const answers = new Map(res.rows.map((r) => [r.id, r.ok]));
      for (const item of items) {
        const expected = expectedCircleView(fixture, viewer, item, deleted);
        if (expected !== undefined && answers.get(item.id) !== expected) {
          throw new Error(
            `${phase}: can_view(${item.kind} ${item.id}) as ${String(viewer)}: got ${String(answers.get(item.id))}, expected ${String(expected)}`,
          );
        }
      }
    }
    for (const [table, kind] of [
      ["content_items", "content"],
      ["vouches", "vouch"],
    ] as const) {
      const res = await client.query<{ id: string }>(`select id from public.${table}`);
      const seen = new Set(res.rows.map((r) => r.id));
      for (const item of items.filter((i) => i.kind === kind)) {
        const answers = viewers.map((v) => expectedCircleView(fixture, v, item, deleted));
        const expected = answers.includes(true) ? true : answers.includes(undefined) ? undefined : false;
        if (expected === undefined) continue;
        if (seen.has(item.id) !== expected) {
          throw new Error(
            `${phase}: select from ${table}: ${item.id} seen=${String(seen.has(item.id))}, expected ${String(expected)} for ${user.role} ${user.sub ?? "(signed out)"}`,
          );
        }
      }
    }
  } finally {
    await resetRole(client);
  }
}

/** Throws when `leaked` is not empty, naming what leaked and to whom. */
function assertNoLeak(what: string, user: SimUser, leaked: string[]): void {
  if (leaked.length > 0) {
    throw new Error(
      `${what}: ${user.role} ${user.sub ?? "(signed out)"} saw non public item(s) ${leaked.join(", ")}`,
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Properties
// ---------------------------------------------------------------------------

/**
 * Per-test timeout. One generated world takes about 15 s to insert over the
 * pooler (see DEVLOG 31.4), so the limit grows with PROPERTY_RUNS.
 */
export const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

describe("visibility properties", () => {
  // Feature: 00-database-foundation, Property 1: Strangers and signed-out visitors never see a non-public item
  // **Validates: Requirements 20.1, 20.4, 20.5, 20.6, 20.7, 20.11, 22.4, 22.5**
  it(
    "Property 1: strangers and signed-out visitors never see a non-public item",
    async () => {
      await fc.assert(
        fc.asyncProperty(
          scenarioArb,
          viewerArb,
          fc.nat(1000),
          async (spec, viewerSpec, viewAsPick) => {
            await withRolledBackTx(async (client) => {
              const fixture = await insertScenario(client, spec);
              const user = simulatedUser(fixture, viewerSpec);
              const hidden = hiddenFrom(fixture, user, itemFacts(fixture));
              const hiddenIds = new Set(hidden.map((i) => i.id));
              const controlledIds = new Set(user.controlled.map((p) => p.id));
              const pages = fixture.profiles.filter((p) => !controlledIds.has(p.id));
              // Signed out, and as each profile this login controls.
              const viewers: (string | null)[] = [null, ...user.controlled.map((p) => p.id)];

              await asUser(client, user.role, user.sub);
              try {
                // can_view
                if (hidden.length > 0) {
                  for (const viewer of viewers) {
                    const res = await client.query<{ id: string; ok: boolean }>(
                      "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
                      [viewer, hidden.map((i) => i.id)],
                    );
                    assertNoLeak(
                      `can_view as ${String(viewer)}`,
                      user,
                      res.rows.filter((r) => r.ok).map((r) => r.id),
                    );
                  }
                }

                // RLS reads of content_items and vouches.
                for (const table of ["content_items", "vouches"] as const) {
                  const res = await client.query<{ id: string }>(`select id from public.${table}`);
                  assertNoLeak(
                    `select from ${table}`,
                    user,
                    res.rows.map((r) => r.id).filter((id) => hiddenIds.has(id)),
                  );
                }

                // page_items for every page the caller does not control. No audience
                // is ever returned to a non-owner.
                for (const viewer of viewers) {
                  const res = await client.query<{ item_id: string; audience: string | null }>(
                    `select pi.item_id, pi.audience
                     from unnest($1::uuid[]) as o(id), lateral public.page_items(o.id, $2) as pi`,
                    [pages.map((p) => p.id), viewer],
                  );
                  assertNoLeak(
                    `page_items as ${String(viewer)}`,
                    user,
                    res.rows.map((r) => r.item_id).filter((id) => hiddenIds.has(id)),
                  );
                  if (res.rows.some((r) => r.audience !== null)) {
                    throw new Error("page_items returned an audience to a non-owner");
                  }
                }

                // view_as on a page the caller does not control is refused: PT403 for a
                // signed in login, permission denied (42501) for anon, which has no execute.
                const target = pick(pages, viewAsPick);
                if (target !== undefined) {
                  const expected = user.role === "anon" ? "42501" : "PT403";
                  const code = await errorCodeOf(client, () =>
                    client.query("select * from public.view_as($1, null)", [target.id]),
                  );
                  if (code !== expected) {
                    throw new Error(
                      `view_as(${target.handle}) by ${user.role} gave ${String(code)}, expected ${expected}`,
                    );
                  }
                }
              } finally {
                await resetRole(client);
              }
            });
          },
        ),
        { numRuns: PROPERTY_RUNS },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );

  // Feature: 00-database-foundation, Property 2: Connections see connections items; non-connections never do
  // **Validates: Requirements 20.6, 8.4, 8.6**
  it(
    "Property 2: connections see connections items; non-connections never do",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, viewerArb, async (spec, viewerSpec) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            const user = simulatedUser(fixture, viewerSpec);
            const items = connectionsItems(fixture);
            if (items.length === 0) return;
            const viewers: (string | null)[] = [null, ...user.controlled.map((p) => p.id)];
            await asUser(client, user.role, user.sub);
            try {
              // can_view, per viewer profile (and signed out).
              for (const viewer of viewers) {
                const res = await client.query<{ id: string; ok: boolean }>(
                  "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
                  [viewer, items.map((i) => i.id)],
                );
                const answers = new Map(res.rows.map((r) => [r.id, r.ok]));
                for (const item of items) {
                  const expected = expectedConnectionsView(fixture, viewer, item);
                  if (expected !== undefined && answers.get(item.id) !== expected) {
                    throw new Error(
                      `can_view(${item.kind} ${item.id}) as ${String(viewer)}: got ${String(answers.get(item.id))}, expected ${String(expected)}`,
                    );
                  }
                }
              }
              // RLS reads: an item is returned when any profile of the login may see it.
              for (const [table, kind] of [
                ["content_items", "content"],
                ["vouches", "vouch"],
              ] as const) {
                const res = await client.query<{ id: string }>(`select id from public.${table}`);
                const seen = new Set(res.rows.map((r) => r.id));
                for (const item of items.filter((i) => i.kind === kind)) {
                  const answers = viewers.map((v) => expectedConnectionsView(fixture, v, item));
                  // Seen when any profile may see it; unknown when only nested answers remain.
                  const expected = answers.includes(true)
                    ? true
                    : answers.includes(undefined)
                      ? undefined
                      : false;
                  if (expected === undefined) continue;
                  if (seen.has(item.id) !== expected) {
                    throw new Error(
                      `select from ${table}: ${item.id} seen=${String(seen.has(item.id))}, expected ${String(expected)} for ${user.role} ${user.sub ?? "(signed out)"}`,
                    );
                  }
                }
              }
            } finally {
              await resetRole(client);
            }
          });
        }),
        // endOnFailure: a world takes 10 to 30 s over the pooler, so shrinking could not finish
        // inside PROPERTY_TIMEOUT_MS and a failure would show up only as a timeout.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );

  // Feature: 00-database-foundation, Property 3: A circle item is visible to exactly the owner and members of a linked circle
  // **Validates: Requirements 20.7, 20.2, 14.12, 10.3**
  it(
    "Property 3: a circle item is visible to exactly the owner and members of a linked circle",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, viewerArb, fc.nat(1000), async (spec, viewerSpec, deletePick) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            // One status per business, shared to its all followers circle.
            const extraIds: string[] = [];
            for (const business of fixture.businesses) {
              const circle = await client.query<{ id: string }>(
                "select id from public.circles where owner_profile_id = $1 and is_all_followers",
                [business.id],
              );
              const item = await client.query<{ id: string }>(
                `insert into public.content_items (owner_profile_id, content_type, audience, details)
                 values ($1, 'status', 'circles', '{"text":"hello"}'::jsonb) returning id`,
                [business.id],
              );
              await client.query(
                "insert into public.item_circles (content_item_id, circle_id) values ($1, $2)",
                [item.rows[0]!.id, circle.rows[0]!.id],
              );
              extraIds.push(item.rows[0]!.id);
            }
            const items = circleItems(fixture, extraIds);
            if (items.length === 0) return;
            const user = simulatedUser(fixture, viewerSpec);

            await checkCircleItems(client, fixture, user, items, new Set(), "before delete");

            // Delete one hand picked circle: its links go with it, and an item left with
            // no live circle is visible to its owner (and vouch subject) only.
            const target = pick(fixture.circles, deletePick);
            if (target !== undefined) {
              await client.query("delete from public.circles where id = $1", [target.id]);
              await checkCircleItems(client, fixture, user, items, new Set([target.id]), "after delete");
            }
          });
        }),
        // endOnFailure: see Property 2.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
