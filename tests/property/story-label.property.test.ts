// Story label property (spec 00, task 39). Property 11 carries the comment
// `// Feature: 00-database-foundation, Property 11: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every call,
// and runs inside withRolledBackTx.
//
// The world is small on purpose: one story owner (a person or a business), up
// to three other people, up to three hand picked circles (plus the automatic
// "all followers" circle for a business), and one circles story linked to a
// random subset of them. Every viewer (signed out, the owner, each other
// person) is checked against an oracle written from the rules in Req 13.
import { randomUUID } from "node:crypto";
import fc from "fast-check";
import { describe, it } from "vitest";
import {
  insertBusiness,
  insertCircle,
  insertCircleMember,
  insertContentItem,
  insertLogin,
  insertPerson,
  insertRelationship,
  type BusinessSpec,
  type ContentSpec,
  type PersonSpec,
} from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

/** Per-test timeout. One generated world takes several seconds to insert over the pooler. */
const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

const MAX_OTHERS = 3;
const MAX_CIRCLES = 3;

const tokenArb = fc.stringMatching(/^[a-z0-9]{4,12}$/);

interface CircleWorld {
  showMemberLabel: boolean;
  /** Prefixed `label-`; stored whether or not the switch is on. */
  memberLabel: string;
  /** Which of the other people the owner tries to place in the circle. */
  memberFlags: boolean[];
}

interface WorldSpec {
  ownerIsBusiness: boolean;
  /** Which of the other people connect with (or follow) the owner. */
  related: boolean[];
  circles: CircleWorld[];
  /** Which hand picked circles the story is shared to. */
  linkFlags: boolean[];
  /** Business only: also share to the automatic all followers circle. */
  linkAllFollowers: boolean;
  allFollowersShowLabel: boolean;
  allFollowersLabel: string;
}

const flagsArb = (length: number) => fc.array(fc.boolean(), { minLength: length, maxLength: length });

const worldArb: fc.Arbitrary<WorldSpec> = fc.record({
  ownerIsBusiness: fc.boolean(),
  related: flagsArb(MAX_OTHERS),
  circles: fc.array(
    fc.record({
      showMemberLabel: fc.boolean(),
      memberLabel: tokenArb.map((t) => `label-${t}`),
      memberFlags: flagsArb(MAX_OTHERS),
    }),
    { minLength: 1, maxLength: MAX_CIRCLES },
  ),
  linkFlags: flagsArb(MAX_CIRCLES),
  linkAllFollowers: fc.boolean(),
  allFollowersShowLabel: fc.boolean(),
  allFollowersLabel: tokenArb.map((t) => `label-${t}`),
});

const PERSON: Omit<PersonSpec, "login"> = {
  type: "person",
  displayName: "Story Label Test",
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
};

const BUSINESS: BusinessSpec = {
  type: "business",
  ownerPick: 0,
  category: null,
  displayName: "Story Label Business",
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
};

const STORY: ContentSpec = {
  ownerPick: 0,
  details: { kind: "story", text: "story", withImage: false },
  audience: "circles",
  circlePicks: [],
  groupPick: 0,
  ageHours: 0,
  parentPick: null,
};

/** A circle the story is shared to, as the oracle sees it. */
interface LinkedCircle {
  id: string;
  isAllFollowers: boolean;
  showMemberLabel: boolean;
  memberLabel: string;
  /** Profile ids that currently belong to the circle (followers, for all followers). */
  members: Set<string>;
}

type Expected = { kind: "member_label"; label: string } | { kind: "only_for_you" | "shared_with_you" } | null;

/** The rules of Req 13, applied to what the database accepted. */
function expectedLabel(
  viewerId: string | null,
  ownerId: string,
  linked: LinkedCircle[],
  ordered: string[],
): Expected {
  if (viewerId === null || viewerId === ownerId) return null; // 13.3
  const mine = linked.filter((c) => c.members.has(viewerId));
  if (mine.length === 0) return null; // the story is not visible to this viewer (13.2)
  const byId = new Map(mine.map((c) => [c.id, c]));
  for (const id of ordered) {
    const circle = byId.get(id);
    if (circle !== undefined && circle.showMemberLabel) {
      return { kind: "member_label", label: circle.memberLabel }; // 13.4, 13.9
    }
  }
  const someoneElse = linked.some((c) => [...c.members].some((m) => m !== viewerId));
  return { kind: someoneElse ? "shared_with_you" : "only_for_you" }; // 13.5, 13.6, 13.8
}

describe("story label properties", () => {
  // Feature: 00-database-foundation, Property 11: The story label follows the member-label rules and reveals nothing else
  // **Validates: Requirements 13.4, 13.5, 13.6, 13.1, 13.9, 13.10, 13.8**
  it(
    "Property 11: story_label follows the member-label rules and reveals nothing else",
    async () => {
      await fc.assert(
        fc.asyncProperty(worldArb, async (world) => {
          await withRolledBackTx(async (client) => {
            const run = randomUUID().replace(/-/g, "").slice(0, 10);

            // People: index 0 owns the story (or the business); the rest are the audience.
            const people: { id: string; userId: string }[] = [];
            for (let i = 0; i <= MAX_OTHERS; i += 1) {
              const userId = await insertLogin(client, `sl-${run}-${i}@pavio-test.invalid`);
              const id = await insertPerson(
                client,
                { ...PERSON, login: { emailTag: "x" } },
                userId,
                `sl${run}_${i}`,
              );
              people.push({ id, userId });
            }
            const [ownerPerson, ...others] = people;
            if (ownerPerson === undefined) throw new Error("no owner person");
            const ownerId = world.ownerIsBusiness
              ? await insertBusiness(client, BUSINESS, ownerPerson.userId, `slb${run}`)
              : ownerPerson.id;

            // Audience: connections (accepted) for a person, followers for a business.
            const related = new Set<string>();
            for (const [i, other] of others.entries()) {
              if (world.related[i] !== true) continue;
              const stored = world.ownerIsBusiness
                ? await insertRelationship(client, other.id, ownerId, "follow", "accepted")
                : await insertRelationship(client, other.id, ownerId, "connection", "accepted");
              if (stored?.status === "accepted") related.add(other.id);
            }

            // Hand picked circles and the members the database accepts.
            const handCircles: LinkedCircle[] = [];
            for (const circle of world.circles) {
              const id = await insertCircle(client, ownerId, {
                ownerPick: 0,
                privateName: `priv-${run}-${handCircles.length}`,
                showMemberLabel: circle.showMemberLabel,
                memberLabel: circle.memberLabel,
              });
              const members = new Set<string>();
              for (const [i, other] of others.entries()) {
                if (circle.memberFlags[i] !== true || !related.has(other.id)) continue;
                if (await insertCircleMember(client, id, other.id)) members.add(other.id);
              }
              handCircles.push({
                id,
                isAllFollowers: false,
                showMemberLabel: circle.showMemberLabel,
                memberLabel: circle.memberLabel,
                members,
              });
            }

            // Business only: the automatic all followers circle holds the current followers.
            const linked: LinkedCircle[] = [];
            handCircles.forEach((c, i) => {
              if (world.linkFlags[i] === true) linked.push(c);
            });
            if (world.ownerIsBusiness && world.linkAllFollowers) {
              const res = await client.query<{ id: string }>(
                "select id from public.circles where owner_profile_id = $1 and is_all_followers",
                [ownerId],
              );
              const allId = res.rows[0]?.id;
              if (allId === undefined) throw new Error("business has no all followers circle");
              if (world.allFollowersShowLabel) {
                await client.query(
                  "update public.circles set show_member_label = true, member_label = $2 where id = $1",
                  [allId, world.allFollowersLabel],
                );
              }
              linked.push({
                id: allId,
                isAllFollowers: true,
                showMemberLabel: world.allFollowersShowLabel,
                memberLabel: world.allFollowersLabel,
                members: new Set(related),
              });
            }
            // A circles story needs at least one link.
            if (linked.length === 0) {
              const first = handCircles[0];
              if (first === undefined) throw new Error("no circle to link");
              linked.push(first);
            }

            const story = await insertContentItem(client, {
              ownerId,
              spec: STORY,
              tag: "story",
              circleIds: linked.map((c) => c.id),
              groupId: null,
              parentId: null,
            });
            if (story === undefined) throw new Error("the database rejected the circles story");

            // Circle_Label_Order, as the database sees it (created_at, then id).
            const orderRes = await client.query<{ id: string }>(
              "select id from public.circles where id = any($1::uuid[]) order by created_at, id",
              [linked.map((c) => c.id)],
            );
            const ordered = orderRes.rows.map((r) => r.id);

            const privateNames = handCircles.map((_, i) => `priv-${run}-${i}`);
            const secrets = [
              ...privateNames,
              ...linked.map((c) => c.id),
              ...people.map((p) => p.id),
              ownerId,
            ];

            const viewers: { role: "anon" | "authenticated"; sub?: string; profileId: string | null }[] = [
              { role: "anon", profileId: null },
              ...people.map((p) => ({ role: "authenticated" as const, sub: p.userId, profileId: p.id })),
            ];

            for (const viewer of viewers) {
              if (viewer.role === "anon") await asUser(client, "anon");
              else await asUser(client, "authenticated", viewer.sub);
              try {
                const res = await client.query<Record<string, unknown>>(
                  "select * from public.story_label($1, $2)",
                  [story.id, viewer.profileId],
                );
                const expected = expectedLabel(viewer.profileId, ownerId, linked, ordered);
                const who = `${viewer.role} viewer ${String(viewer.profileId)}`;

                if (res.rows.length > 1) throw new Error(`${who} got ${res.rows.length} labels, expected at most one`);
                const row = res.rows[0];
                if (expected === null) {
                  if (row !== undefined) throw new Error(`${who} got ${JSON.stringify(row)}, expected no row`);
                  continue;
                }
                if (row === undefined) throw new Error(`${who} got no row, expected ${JSON.stringify(expected)}`);

                const keys = Object.keys(row).sort().join(",");
                if (keys !== "kind,label") throw new Error(`${who} got unexpected columns ${keys}`);
                if (row["kind"] !== expected.kind) {
                  throw new Error(`${who} got kind ${String(row["kind"])}, expected ${expected.kind}`);
                }
                const expectedText = expected.kind === "member_label" ? expected.label : null;
                if (row["label"] !== expectedText) {
                  throw new Error(`${who} got label ${String(row["label"])}, expected ${String(expectedText)}`);
                }
                const text = JSON.stringify(row);
                const leaked = secrets.find((s) => text.includes(s));
                if (leaked !== undefined) throw new Error(`${who} was shown ${leaked}`);
              } finally {
                await resetRole(client);
              }
            }
          });
        }),
        // endOnFailure: a world takes several seconds over the pooler, so shrinking could not
        // finish inside PROPERTY_TIMEOUT_MS and a failure would show up only as a timeout.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
