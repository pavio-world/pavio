// Top 8 property (spec 00, task 36). Property 8 carries the comment
// `// Feature: 00-database-foundation, Property 8: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every call,
// and runs inside withRolledBackTx.
import { randomUUID } from "node:crypto";
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import { insertLogin, insertPerson, insertRelationship, insertVouch } from "./arbitraries";
import type { PersonSpec } from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 30_000;

/** Vouches written by the author under test: indexes 0 to 9. Index 10 is written by someone else. */
const OWN_VOUCHES = 10;
const FOREIGN = OWN_VOUCHES;

const person = (): PersonSpec => ({
  type: "person",
  login: { emailTag: "x" },
  displayName: "Test Person",
  bio: null,
  dotColour: "jade",
  whatIDo: [],
  city: null,
});

const newHandle = (): string => `t8_${randomUUID().replace(/-/g, "").slice(0, 14)}`;

interface World {
  authorId: string;
  authorUser: string;
  /** Vouch ids by index; the last one is written by another profile. */
  vouchIds: string[];
}

async function buildWorld(client: Client): Promise<World> {
  const authorUser = await insertLogin(client, `t8-${randomUUID()}@pavio-test.invalid`);
  const otherUser = await insertLogin(client, `t8-${randomUUID()}@pavio-test.invalid`);
  const authorId = await insertPerson(client, person(), authorUser, newHandle());
  const otherId = await insertPerson(client, person(), otherUser, newHandle());

  const vouchIds: string[] = [];
  for (let i = 0; i < OWN_VOUCHES; i += 1) {
    const subjectUser = await insertLogin(client, `t8-${randomUUID()}@pavio-test.invalid`);
    const subjectId = await insertPerson(client, person(), subjectUser, newHandle());
    const rel = await insertRelationship(client, authorId, subjectId, "connection", "accepted");
    const vouch =
      rel === undefined
        ? undefined
        : await insertVouch(client, {
            authorId,
            subjectId,
            body: `vouch ${i}`,
            audience: "public",
            circleIds: [],
            top8Position: null,
            hiddenBySubject: false,
          });
    if (vouch === undefined) throw new Error("fixture vouch was rejected");
    vouchIds.push(vouch.id);
  }

  const back = await insertRelationship(client, otherId, authorId, "connection", "accepted");
  const foreign =
    back === undefined
      ? undefined
      : await insertVouch(client, {
          authorId: otherId,
          subjectId: authorId,
          body: "foreign vouch",
          audience: "public",
          circleIds: [],
          top8Position: null,
          hiddenBySubject: false,
        });
  if (foreign === undefined) throw new Error("fixture foreign vouch was rejected");
  vouchIds.push(foreign.id);
  return { authorId, authorUser, vouchIds };
}

/** What the rules say set_top8 does with this list (checks run in this order). */
function expectedError(list: number[]): string | undefined {
  if (list.length > 8) return "vouch.top8_full"; // 14.16
  if (new Set(list).size !== list.length) return "vouch.top8_duplicate"; // 14.17
  if (list.includes(FOREIGN)) return "vouch.top8_not_author";
  return undefined;
}

interface Featured {
  id: string;
  author_profile_id: string;
  top8_position: number;
}

async function featuredRows(client: Client, authorIds: string[]): Promise<Featured[]> {
  const res = await client.query<Featured>(
    `select id, author_profile_id, top8_position from public.vouches
      where author_profile_id = any($1::uuid[]) and top8_position is not null
      order by author_profile_id, top8_position`,
    [authorIds],
  );
  return res.rows;
}

// A sequence of set_top8 calls. Lists may be empty (unfeature all), partial (feature),
// reordered or overlapping the previous list (swap, replace), too long, duplicated or
// contain another author's vouch.
const listArb = fc.array(fc.nat(FOREIGN), { maxLength: 10 });
const opsArb = fc.array(listArb, { minLength: 1, maxLength: 6 });

describe("top 8 properties", () => {
  // Feature: 00-database-foundation, Property 8: No author ever has more than 8 featured vouches, each at a distinct position
  // **Validates: Requirements 14.16, 14.17, 14.18**
  it(
    "Property 8: after every set_top8 call the author has at most 8 featured vouches at distinct positions",
    async () => {
      await fc.assert(
        fc.asyncProperty(opsArb, async (ops) => {
          await withRolledBackTx(async (client) => {
            const world = await buildWorld(client);
            const authorIds = [world.authorId];
            let model: string[] = []; // featured vouch ids in position order

            for (const [step, list] of ops.entries()) {
              const ids = list.map((i) => world.vouchIds[i] as string);
              const want = expectedError(list);
              const label = `step ${step}, list [${list.join(",")}]`;

              await asUser(client, "authenticated", world.authorUser);
              let error: { code?: string; message: string } | undefined;
              await client.query("savepoint op");
              try {
                await client.query("select public.set_top8($1, $2::uuid[])", [world.authorId, ids]);
                // The unique constraint is deferred to commit, which never happens in a
                // rolled back test, so check it at the end of every operation.
                await client.query("set constraints public.vouches_top8_uq immediate");
                await client.query("set constraints public.vouches_top8_uq deferred");
                await client.query("release savepoint op");
              } catch (e) {
                await client.query("rollback to savepoint op");
                await client.query("release savepoint op");
                error = e as { code?: string; message: string };
              } finally {
                await resetRole(client);
              }

              if (want !== undefined) {
                if (error === undefined) {
                  throw new Error(`${label}: expected ${want} but set_top8 succeeded`);
                }
                if (error.code !== "PT422" || error.message !== want) {
                  throw new Error(
                    `${label}: expected PT422 ${want}, got ${String(error.code)} ${error.message}`,
                  );
                }
                // A rejected call changes nothing.
              } else {
                if (error !== undefined) {
                  throw new Error(`${label}: unexpected error ${String(error.code)} ${error.message}`);
                }
                model = ids;
              }

              // The invariant, after every operation.
              const rows = await featuredRows(client, authorIds);
              if (rows.length > 8) {
                throw new Error(`${label}: author has ${rows.length} featured vouches`);
              }
              const positions = rows.map((r) => r.top8_position);
              if (new Set(positions).size !== positions.length) {
                throw new Error(`${label}: two featured vouches share a position: ${positions.join(",")}`);
              }
              if (positions.some((p) => p < 1 || p > 8)) {
                throw new Error(`${label}: position outside 1 to 8: ${positions.join(",")}`);
              }
              // Stored state matches the list of the last accepted call, in order.
              const stored = rows.map((r) => r.id);
              if (stored.length !== model.length || stored.some((id, i) => id !== model[i])) {
                throw new Error(`${label}: stored top 8 differs from the last accepted list`);
              }
            }

            // The other author's vouch is never featured by the author's calls.
            const foreign = await client.query<{ top8_position: number | null }>(
              "select top8_position from public.vouches where id = $1",
              [world.vouchIds[FOREIGN]],
            );
            if (foreign.rows[0]?.top8_position !== null) {
              throw new Error("another author's vouch was featured");
            }
          });
        }),
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
