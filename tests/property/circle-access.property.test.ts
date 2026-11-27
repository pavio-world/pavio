// Circle access properties (spec 00, task 33). Each property carries the comment
// `// Feature: 00-database-foundation, Property N: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every
// assertion, and runs inside withRolledBackTx.
//
// Layout:
//   1. Shared helpers (who controls a profile, can_view reads).
//   2. One `describe` block per property. Property 12 (task 33.2) is appended
//      as its own `describe` at the end of the file.
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import {
  existingContent,
  insertScenario,
  pick,
  scenarioArb,
  type Fixture,
  type FixtureContent,
  type FixtureProfile,
} from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

// ---------------------------------------------------------------------------
// 1. Shared helpers
// ---------------------------------------------------------------------------

/** Per-test timeout. One generated world takes about 15 s to insert over the pooler. */
export const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

export function profileById(fixture: Fixture, id: string): FixtureProfile {
  const profile = fixture.profiles.find((p) => p.id === id);
  if (profile === undefined) throw new Error(`Unknown profile ${id}`);
  return profile;
}

/** can_view for each item as `viewer`, called as the login that controls `viewer`. */
export async function canViewAs(
  client: Client,
  viewer: FixtureProfile,
  itemIds: string[],
): Promise<Map<string, boolean>> {
  await asUser(client, "authenticated", viewer.userId);
  try {
    const res = await client.query<{ id: string; ok: boolean }>(
      "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
      [viewer.id, itemIds],
    );
    return new Map(res.rows.map((r) => [r.id, r.ok]));
  } finally {
    await resetRole(client);
  }
}

/** Throws when any of `itemIds` does not have the expected answer. */
function expectAnswers(
  answers: Map<string, boolean>,
  itemIds: string[],
  expected: (id: string) => boolean,
  phase: string,
): void {
  for (const id of itemIds) {
    if (answers.get(id) !== expected(id)) {
      throw new Error(
        `${phase}: can_view(${id}) got ${String(answers.get(id))}, expected ${String(expected(id))}`,
      );
    }
  }
}

/** A plain (not nested, not expired) item shared to circles, with its linked hand picked circles. */
function plainCircleItems(fixture: Fixture, ownerId: string): FixtureContent[] {
  return fixture.content.filter(
    (c) =>
      c.ownerId === ownerId &&
      c.audience === "circles" &&
      !c.expired &&
      c.spec.parentPick === null &&
      c.circleIds.length > 0,
  );
}

// ---------------------------------------------------------------------------
// 2. Properties
// ---------------------------------------------------------------------------

describe("circle access properties", () => {
  // Feature: 00-database-foundation, Property 4: Removing a member from a circle immediately removes access
  // **Validates: Requirements 9.19, 8.22, 10.5**
  it(
    "Property 4a: removing a member from a circle removes access to items that circle alone granted",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, fc.nat(1000), async (spec, membershipPick) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            // Memberships with at least one plain item linked to that circle.
            const candidates = fixture.memberships.filter((m) => {
              const circle = fixture.circles.find((c) => c.id === m.circleId);
              return (
                circle !== undefined &&
                plainCircleItems(fixture, circle.ownerId).some((i) => i.circleIds.includes(m.circleId))
              );
            });
            const removed = pick(candidates, membershipPick);
            if (removed === undefined) return;
            const circle = fixture.circles.find((c) => c.id === removed.circleId)!;
            const owner = profileById(fixture, circle.ownerId);
            const member = profileById(fixture, removed.memberId);
            const items = plainCircleItems(fixture, owner.id).filter((i) =>
              i.circleIds.includes(removed.circleId),
            );
            const ids = items.map((i) => i.id);

            // Before: the member sees every one of those items.
            expectAnswers(await canViewAs(client, member, ids), ids, () => true, "before removal");

            // The owner removes the member from the circle.
            await asUser(client, "authenticated", owner.userId);
            try {
              const del = await client.query(
                "delete from public.circle_members where circle_id = $1 and member_profile_id = $2",
                [removed.circleId, removed.memberId],
              );
              if (del.rowCount !== 1) throw new Error(`owner delete removed ${String(del.rowCount)} rows`);
            } finally {
              await resetRole(client);
            }

            // After: the very next read grants access only through another linked circle.
            const remaining = fixture.memberships.filter(
              (m) => !(m.circleId === removed.circleId && m.memberId === removed.memberId),
            );
            const stillGranted = (item: FixtureContent) =>
              remaining.some((m) => m.memberId === member.id && item.circleIds.includes(m.circleId));
            const byId = new Map(items.map((i) => [i.id, i]));
            expectAnswers(
              await canViewAs(client, member, ids),
              ids,
              (id) => stillGranted(byId.get(id)!),
              "after removal",
            );
          });
        }),
        // endOnFailure: a world takes 10 to 30 s over the pooler, so shrinking could not finish
        // inside PROPERTY_TIMEOUT_MS and a failure would show up only as a timeout.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );

  // Feature: 00-database-foundation, Property 4: Removing a member from a circle immediately removes access
  // **Validates: Requirements 9.19, 8.22, 10.5**
  it(
    "Property 4b: ending the relationship removes dependent memberships, including all followers via unfollow",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, fc.nat(1000), async (spec, relationshipPick) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            const rel = pick(
              fixture.relationships.filter((r) => r.status === "accepted"),
              relationshipPick,
            );
            if (rel === undefined) return;
            const requester = profileById(fixture, rel.requesterId);
            const target = profileById(fixture, rel.targetId);

            // A status shared to the business's all followers circle, when this is a follow.
            const followItemIds: string[] = [];
            if (rel.type === "follow") {
              const circle = await client.query<{ id: string }>(
                "select id from public.circles where owner_profile_id = $1 and is_all_followers",
                [target.id],
              );
              const item = await client.query<{ id: string }>(
                `insert into public.content_items (owner_profile_id, content_type, audience, details)
                 values ($1, 'status', 'circles', '{"text":"hello"}'::jsonb) returning id`,
                [target.id],
              );
              await client.query(
                "insert into public.item_circles (content_item_id, circle_id) values ($1, $2)",
                [item.rows[0]!.id, circle.rows[0]!.id],
              );
              followItemIds.push(item.rows[0]!.id);
              // The new status replaced the business's generated status and anything nested under it.
              fixture.content = await existingContent(client, fixture.content);
              expectAnswers(
                await canViewAs(client, requester, followItemIds),
                followItemIds,
                () => true,
                "before unfollow",
              );
            }

            // Both directions: items of `owner` that `other` could see through hand picked circles.
            const pairs: [FixtureProfile, FixtureProfile][] = [
              [requester, target],
              [target, requester],
            ];
            const dependent = new Map<string, FixtureProfile>(); // item id -> viewer
            for (const [owner, other] of pairs) {
              const memberCircles = new Set(
                fixture.memberships
                  .filter((m) => m.memberId === other.id)
                  .map((m) => m.circleId),
              );
              for (const item of plainCircleItems(fixture, owner.id)) {
                if (item.circleIds.some((c) => memberCircles.has(c))) dependent.set(item.id, other);
              }
            }
            for (const [itemId, viewer] of dependent) {
              expectAnswers(await canViewAs(client, viewer, [itemId]), [itemId], () => true, "before removal");
            }

            // Whoever controls the requester ends the relationship (an unfollow for a follow).
            await asUser(client, "authenticated", requester.userId);
            try {
              await client.query("select public.remove_relationship($1)", [rel.id]);
            } finally {
              await resetRole(client);
            }

            // Every membership between the two profiles is gone, in both directions (as the owner of the test).
            const left = await client.query<{ n: number }>(
              `select count(*)::int as n
               from public.circle_members cm
               join public.circles c on c.id = cm.circle_id
               where not c.is_all_followers
                 and ((c.owner_profile_id = $1 and cm.member_profile_id = $2)
                   or (c.owner_profile_id = $2 and cm.member_profile_id = $1))`,
              [requester.id, target.id],
            );
            if (left.rows[0]?.n !== 0) {
              throw new Error(`${String(left.rows[0]?.n)} circle membership(s) survived the end of the relationship`);
            }

            // And the next read denies every item those memberships granted, plus the all followers item.
            for (const [itemId, viewer] of dependent) {
              expectAnswers(await canViewAs(client, viewer, [itemId]), [itemId], () => false, "after removal");
            }
            if (followItemIds.length > 0) {
              expectAnswers(
                await canViewAs(client, requester, followItemIds),
                followItemIds,
                () => false,
                "after unfollow",
              );
            }
          });
        }),
        // endOnFailure: see Property 4a.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});


describe("member label switch properties", () => {
  // Feature: 00-database-foundation, Property 12: Turning off a member-label switch stops the label at the next call
  // **Validates: Requirements 13.11, 9.8**
  it(
    "Property 12: turning the switch off stops the label at the next story_label call and keeps the stored text",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, fc.nat(1000), async (spec, candidatePick) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            // (fresh plain circles story, one linked circle, a member of that circle)
            const candidates: { story: FixtureContent; circleId: string; memberId: string }[] = [];
            for (const story of fixture.content) {
              if (
                story.contentType !== "story" ||
                story.audience !== "circles" ||
                story.expired ||
                story.spec.parentPick !== null
              ) {
                continue;
              }
              for (const circleId of story.circleIds) {
                for (const m of fixture.memberships) {
                  if (m.circleId === circleId && m.memberId !== story.ownerId) {
                    candidates.push({ story, circleId, memberId: m.memberId });
                  }
                }
              }
            }
            const chosen = pick(candidates, candidatePick);
            if (chosen === undefined) return;
            const owner = profileById(fixture, chosen.story.ownerId);
            const viewer = profileById(fixture, chosen.memberId);
            const labelText = `label-p12-${chosen.circleId.slice(0, 8)}`;

            const asOwner = async (sql: string, params: unknown[]): Promise<void> => {
              await asUser(client, "authenticated", owner.userId);
              try {
                const res = await client.query(sql, params);
                if (res.rowCount === 0) throw new Error(`owner update changed no rows: ${sql}`);
              } finally {
                await resetRole(client);
              }
            };
            const labelAs = async (): Promise<{ kind: string; label: string | null }> => {
              await asUser(client, "authenticated", viewer.userId);
              try {
                const res = await client.query<{ kind: string; label: string | null }>(
                  "select kind::text as kind, label from public.story_label($1, $2)",
                  [chosen.story.id, viewer.id],
                );
                if (res.rows.length !== 1) throw new Error(`story_label returned ${res.rows.length} rows`);
                return res.rows[0]!;
              } finally {
                await resetRole(client);
              }
            };

            // Only the chosen circle may supply a label, so the expected result is exact.
            const others = chosen.story.circleIds.filter((c) => c !== chosen.circleId);
            if (others.length > 0) {
              await asOwner("update public.circles set show_member_label = false where id = any($1::uuid[])", [others]);
            }
            await asOwner(
              "update public.circles set show_member_label = true, member_label = $2 where id = $1",
              [chosen.circleId, labelText],
            );
            const on = await labelAs();
            if (on.kind !== "member_label" || on.label !== labelText) {
              throw new Error(`switch on: got ${on.kind} / ${String(on.label)}, expected member_label / ${labelText}`);
            }

            // The owner turns the switch off; the very next call must not return the label.
            await asOwner("update public.circles set show_member_label = false where id = $1", [chosen.circleId]);
            const off = await labelAs();
            if (off.kind !== "only_for_you" && off.kind !== "shared_with_you") {
              throw new Error(`switch off: got kind ${off.kind}`);
            }
            if (off.label !== null) throw new Error(`switch off: label text still returned: ${off.label}`);

            // 9.8: the stored text is kept.
            await asUser(client, "authenticated", owner.userId);
            try {
              const stored = await client.query<{ member_label: string | null }>(
                "select member_label from public.circles where id = $1",
                [chosen.circleId],
              );
              if (stored.rows[0]?.member_label !== labelText) {
                throw new Error(`stored member_label changed to ${String(stored.rows[0]?.member_label)}`);
              }
            } finally {
              await resetRole(client);
            }

            // Turning the switch on again restores the same text.
            await asOwner("update public.circles set show_member_label = true where id = $1", [chosen.circleId]);
            const again = await labelAs();
            if (again.kind !== "member_label" || again.label !== labelText) {
              throw new Error(`switch on again: got ${again.kind} / ${String(again.label)}`);
            }
          });
        }),
        // endOnFailure: see Property 4a.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
