// Relationship properties (spec 00, task 35). Property 7 carries the comment
// `// Feature: 00-database-foundation, Property 7: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every call,
// and runs inside withRolledBackTx.
import { randomUUID } from "node:crypto";
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import { insertBusiness, insertLogin, insertPerson } from "./arbitraries";
import type { BusinessSpec, PersonSpec } from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 30_000;

type Kind = "person" | "business";
type RelType = "connection" | "follow";

interface Actor {
  id: string;
  kind: Kind;
  /** The login that controls this profile. */
  userId: string;
  /** Index of the login (0 or 1) that controls it; equal values share a controller. */
  controller: number;
}

// Fixed world layout. Indexes: 0 person A, 1 person B, 2 business of A,
// 3 business of B, 4 second business of A. Pairs with the same controller
// (0, 2, 4 and 1, 3) are the "managed page" cases.
const LAYOUT: { kind: Kind; controller: number }[] = [
  { kind: "person", controller: 0 },
  { kind: "person", controller: 1 },
  { kind: "business", controller: 0 },
  { kind: "business", controller: 1 },
  { kind: "business", controller: 0 },
];

const person = (): PersonSpec => ({
  type: "person",
  login: { emailTag: "x" },
  displayName: "Test Person",
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
});
const business = (): BusinessSpec => ({
  type: "business",
  ownerPick: 0,
  category: null,
  displayName: "Test Business",
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
});

async function buildWorld(client: Client): Promise<Actor[]> {
  const logins = [
    await insertLogin(client, `r7-${randomUUID()}@pavio-test.invalid`),
    await insertLogin(client, `r7-${randomUUID()}@pavio-test.invalid`),
  ];
  const actors: Actor[] = [];
  for (const slot of LAYOUT) {
    const userId = logins[slot.controller] as string;
    // Random handles: other test files insert concurrently and unique handles would block.
    const handle = `r7_${randomUUID().replace(/-/g, "").slice(0, 14)}`;
    const id =
      slot.kind === "person"
        ? await insertPerson(client, person(), userId, handle)
        : await insertBusiness(client, business(), userId, handle);
    actors.push({ id, kind: slot.kind, userId, controller: slot.controller });
  }
  return actors;
}

/** What the rules say should happen: an error message, or the stored status. */
function expected(
  from: Actor,
  to: Actor,
  type: RelType,
): { error: string } | { status: "pending" | "accepted" } {
  if (from.id === to.id) return { error: "relationship.self" }; // 8.10
  if (from.controller === to.controller) return { error: "relationship.managed_page" }; // 8.11
  if (from.kind === "business" && to.kind === "person") {
    return { error: "relationship.business_to_person" }; // 8.7
  }
  if (type === "follow") {
    return from.kind === "person" && to.kind === "business"
      ? { status: "accepted" } // 8.6
      : { error: "relationship.follow_shape" }; // 8.8
  }
  return from.kind === to.kind
    ? { status: "pending" } // 8.2, 8.3
    : { error: "relationship.connection_shape" }; // 8.9
}

const attemptArb = fc.record({
  from: fc.nat(LAYOUT.length - 1),
  to: fc.nat(LAYOUT.length - 1),
  type: fc.constantFrom<RelType>("connection", "follow"),
});

describe("relationship properties", () => {
  // Feature: 00-database-foundation, Property 7: A business can never start a relationship with a person
  // **Validates: Requirements 8.7, 8.8, 8.9, 8.10, 8.11, 8.2, 8.3, 8.6**
  it(
    "Property 7: business to person is always rejected; follows and connections have their fixed shapes",
    async () => {
      await fc.assert(
        fc.asyncProperty(
          // One attempt per (unordered pair, type), so no case hits the duplicate rule.
          fc.uniqueArray(attemptArb, {
            minLength: 1,
            maxLength: 6,
            selector: (a) => `${Math.min(a.from, a.to)}-${Math.max(a.from, a.to)}-${a.type}`,
          }),
          async (attempts) => {
            await withRolledBackTx(async (client) => {
              const actors = await buildWorld(client);
              for (const attempt of attempts) {
                const from = actors[attempt.from] as Actor;
                const to = actors[attempt.to] as Actor;
                const want = expected(from, to, attempt.type);
                const label = `${from.kind}#${attempt.from} -> ${to.kind}#${attempt.to} (${attempt.type})`;

                await asUser(client, "authenticated", from.userId);
                let error: { code?: string; message: string } | undefined;
                let relId: string | undefined;
                await client.query("savepoint attempt");
                try {
                  const res = await client.query<{ id: string }>(
                    "select public.request_relationship($1, $2, $3::public.relationship_type) as id",
                    [from.id, to.id, attempt.type],
                  );
                  relId = res.rows[0]?.id;
                  await client.query("release savepoint attempt");
                } catch (e) {
                  await client.query("rollback to savepoint attempt");
                  await client.query("release savepoint attempt");
                  error = e as { code?: string; message: string };
                } finally {
                  await resetRole(client);
                }

                if ("error" in want) {
                  if (error === undefined) {
                    throw new Error(`${label}: expected ${want.error} but the request succeeded`);
                  }
                  if (error.code !== "PT422" || error.message !== want.error) {
                    throw new Error(
                      `${label}: expected PT422 ${want.error}, got ${String(error.code)} ${error.message}`,
                    );
                  }
                  continue;
                }

                if (error !== undefined || relId === undefined) {
                  throw new Error(
                    `${label}: expected status ${want.status}, got error ${error?.message ?? "no id"}`,
                  );
                }
                const stored = await client.query<{ status: string; type: string }>(
                  "select status::text as status, type::text as type from public.relationships where id = $1",
                  [relId],
                );
                const row = stored.rows[0];
                if (row?.status !== want.status || row.type !== attempt.type) {
                  throw new Error(
                    `${label}: expected ${attempt.type}/${want.status}, stored ${row?.type}/${row?.status}`,
                  );
                }
              }

              // No relationship from a business to a person exists after any sequence of attempts.
              const bad = await client.query<{ n: string }>(
                `select count(*)::text as n
                   from public.relationships r
                   join public.profiles a on a.id = r.requester_profile_id
                   join public.profiles b on b.id = r.target_profile_id
                  where a.id = any($1::uuid[]) and a.type = 'business' and b.type = 'person'`,
                [actors.map((a) => a.id)],
              );
              if (bad.rows[0]?.n !== "0") {
                throw new Error("a business to person relationship was stored");
              }
            });
          },
        ),
        { numRuns: PROPERTY_RUNS },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
