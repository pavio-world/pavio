// Canary and sanity tests for the simulated API callers (Requirement 26.20 to
// 26.23; design D-8, DR-1). Every test runs in a transaction that is rolled back.
import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  insertContentItem,
  insertLogin,
  insertPerson,
  type ContentSpec,
  type PersonSpec,
} from "./arbitraries";
import { asUser, CanaryError, checkCanary, readCanary, resetRole, withRolledBackTx } from "./db";

const personSpec = (name: string): PersonSpec => ({
  type: "person",
  login: { emailTag: name },
  displayName: name,
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
});

describe("simulated API callers", () => {
  it("authenticated with a random sub passes the canary", async () => {
    await withRolledBackTx(async (client) => {
      const sub = randomUUID();
      await asUser(client, "authenticated", sub);
      const res = await client.query<{ who: string; uid: string }>(
        "select current_user::text as who, auth.uid()::text as uid",
      );
      expect(res.rows[0]).toEqual({ who: "authenticated", uid: sub });
    });
  });

  it("anon passes the canary with a null auth.uid()", async () => {
    await withRolledBackTx(async (client) => {
      await asUser(client, "anon");
      const res = await client.query<{ who: string; uid: string | null }>(
        "select current_user::text as who, auth.uid()::text as uid",
      );
      expect(res.rows[0]).toEqual({ who: "anon", uid: null });
    });
  });

  it("readCanary rejects any role but authenticated and anon", async () => {
    await withRolledBackTx(async (client) => {
      await expect(readCanary(client, "service_role" as never)).rejects.toBeInstanceOf(CanaryError);
    });
  });

  it("service_role claims capture false and checkCanary throws CanaryError", async () => {
    await withRolledBackTx(async (client) => {
      // Claims are built at run time; no token is stored in the repository.
      const claims = JSON.stringify({ role: "service_role", sub: randomUUID() });
      await client.query("select set_config($1, $2, true)", ["request.jwt.claims", claims]);
      const res = await client.query<{ caller: boolean | null }>(
        "select private.is_api_caller() as caller",
      );
      const captured = res.rows[0]?.caller === true;
      expect(captured).toBe(false);

      await client.query("set local role anon");
      await expect(checkCanary(client, "anon", undefined, captured)).rejects.toBeInstanceOf(
        CanaryError,
      );
      await resetRole(client);
    });
  });

  it("neither anon nor authenticated has USAGE on schema private", async () => {
    await withRolledBackTx(async (client) => {
      const res = await client.query<{ anon: boolean; authenticated: boolean }>(
        `select has_schema_privilege('anon', 'private', 'USAGE') as anon,
                has_schema_privilege('authenticated', 'private', 'USAGE') as authenticated`,
      );
      expect(res.rows[0]).toEqual({ anon: false, authenticated: false });
    });
  });

  it("a connections item of B is invisible to stranger A through RLS and can_view", async () => {
    await withRolledBackTx(async (client) => {
      const userA = await insertLogin(client, `a-${randomUUID()}@pavio-test.invalid`);
      const userB = await insertLogin(client, `b-${randomUUID()}@pavio-test.invalid`);
      const profileA = await insertPerson(client, personSpec("alpha"), userA, "canary_a");
      const profileB = await insertPerson(client, personSpec("beta"), userB, "canary_b");
      const spec: ContentSpec = {
        ownerPick: 0,
        details: { kind: "status", text: "hello", emoji: null },
        audience: "connections",
        circlePicks: [],
        groupPick: 0,
        ageHours: 0,
        parentPick: null,
      };
      const item = await insertContentItem(client, {
        ownerId: profileB,
        spec,
        tag: "sanity",
        circleIds: [],
        groupId: null,
        parentId: null,
      });
      expect(item?.audience).toBe("connections");
      const itemId = item?.id ?? "";

      // The owner sees it, so the item exists and the test is not vacuous.
      await asUser(client, "authenticated", userB);
      const own = await client.query("select id from public.content_items where id = $1", [itemId]);
      expect(own.rowCount).toBe(1);
      await resetRole(client);

      await asUser(client, "authenticated", userA);
      const rows = await client.query("select id from public.content_items where id = $1", [itemId]);
      expect(rows.rowCount).toBe(0);
      const visible = await client.query<{ ok: boolean }>(
        "select public.can_view($1, $2) as ok",
        [itemId, profileA],
      );
      expect(visible.rows[0]?.ok).toBe(false);
      await resetRole(client);
    });
  });
});
