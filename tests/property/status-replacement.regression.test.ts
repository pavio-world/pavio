// Regression tests for the counterexamples of task 43 (Req 26.18).
//
// Properties 2 and 3 failed because a fixture kept items the database had
// already deleted: a new status replaces the owner's previous status
// (Req 11.13) and the parent foreign key cascades to items nested under it.
// `can_view` then answered false for the owner on a row that no longer
// existed. The generated counterexamples were not shrunk (endOnFailure), so
// each test below is a hand-reduced world of the same shape:
//   - Property 2 (seed -1404945991, path "5"): a person's public status with a
//     connections gallery nested under it, then a second status.
//   - Property 3 (seed 1532429556, path "6"): a business status shared to a
//     circle with a gallery nested under it, then the test's extra status.
import { describe, expect, it } from "vitest";
import {
  existingContent,
  insertScenario,
  type ContentSpec,
  type ScenarioSpec,
} from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";

const status = (ownerPick: number, audience: ContentSpec["audience"]): ContentSpec => ({
  ownerPick,
  details: { kind: "status", text: "busy", emoji: null },
  audience,
  circlePicks: [0],
  groupPick: 0,
  ageHours: 1,
  parentPick: null,
});

const nestedGallery = (ownerPick: number, audience: ContentSpec["audience"]): ContentSpec => ({
  ownerPick,
  details: { kind: "gallery", caption: null },
  audience,
  circlePicks: [0],
  groupPick: 0,
  ageHours: 1,
  parentPick: 0,
});

const baseWorld: ScenarioSpec = {
  persons: [
    {
      type: "person",
      login: { emailTag: "regression" },
      displayName: "Amina",
      bio: null,
      dotColour: "jade",
      whatIDo: [],
      city: null,
    },
  ],
  businesses: [],
  managers: [],
  relationships: [],
  circles: [],
  memberships: [],
  groups: [],
  content: [],
  vouches: [],
};

describe("status replacement regressions", () => {
  it("Property 2 counterexample: the fixture drops a replaced status and its nested item", async () => {
    await withRolledBackTx(async (client) => {
      const fixture = await insertScenario(client, {
        ...baseWorld,
        content: [status(0, "public"), nestedGallery(0, "connections"), status(0, "connections")],
      });
      expect(fixture.content.map((c) => c.spec.details.kind)).toEqual(["status"]);
      expect(fixture.content[0]?.audience).toBe("connections");

      // The owner sees every item the fixture still lists.
      const owner = fixture.persons[0]!;
      await asUser(client, "authenticated", owner.userId);
      try {
        const res = await client.query<{ ok: boolean }>(
          "select public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
          [owner.id, fixture.content.map((c) => c.id)],
        );
        expect(res.rows.map((r) => r.ok)).toEqual([true]);
      } finally {
        await resetRole(client);
      }
    });
  });

  it("Property 3 counterexample: an extra status removes the business's status and its nested item", async () => {
    await withRolledBackTx(async (client) => {
      const fixture = await insertScenario(client, {
        ...baseWorld,
        businesses: [
          {
            type: "business",
            ownerPick: 0,
            category: null,
            displayName: "Cafe",
            bio: null,
            dotColour: "jade",
            whatIDo: [],
            city: null,
          },
        ],
        // profiles are [person, business], so pick 1 is the business.
        circles: [{ ownerPick: 1, privateName: "priv-suppliers", showMemberLabel: false, memberLabel: "label-x" }],
        content: [status(1, "circles"), nestedGallery(1, "circles")],
      });
      const business = fixture.businesses[0]!;
      expect(fixture.content).toHaveLength(2);

      await client.query(
        `insert into public.content_items (owner_profile_id, content_type, audience, details)
         values ($1, 'status', 'public', '{"text":"hello"}'::jsonb)`,
        [business.id],
      );
      fixture.content = await existingContent(client, fixture.content);
      expect(fixture.content).toEqual([]);
    });
  });
});
