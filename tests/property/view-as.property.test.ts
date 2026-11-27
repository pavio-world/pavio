// View as property (spec 00, task 34). Property 6 carries the comment
// `// Feature: 00-database-foundation, Property 6: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every
// assertion, and runs inside withRolledBackTx.
import fc from "fast-check";
import { describe, it } from "vitest";
import { insertScenario, pick, scenarioArb } from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

/** Per-test timeout. One generated world takes about 15 s to insert over the pooler. */
const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

describe("view as properties", () => {
  // Feature: 00-database-foundation, Property 6: view_as never shows more than the simulated viewer could see
  // **Validates: Requirements 21.1, 21.4, 21.5, 21.3, 20.15**
  it(
    "Property 6: view_as returns exactly the owner's page items the simulated viewer can see",
    async () => {
      await fc.assert(
        fc.asyncProperty(
          scenarioArb,
          fc.nat(1000),
          // Simulated viewer: null (signed out) or any profile, including the owner.
          fc.option(fc.nat(1000), { nil: null }),
          async (spec, ownerPick, viewerPick) => {
            await withRolledBackTx(async (client) => {
              const fixture = await insertScenario(client, spec);
              const owner = pick(fixture.profiles, ownerPick);
              if (owner === undefined) return;
              const simulated =
                viewerPick === null ? undefined : pick(fixture.profiles, viewerPick);
              const simulatedId = simulated?.id ?? null;

              // 21.1: the candidate items of the owner's page, read as the test owner.
              const cand = await client.query<{ id: string }>(
                `select id from public.content_items where owner_profile_id = $1
                 union
                 select id from public.vouches where author_profile_id = $1 and top8_position is not null
                 union
                 select id from public.vouches where subject_profile_id = $1 and not hidden_by_subject`,
                [owner.id],
              );
              const candidateIds = cand.rows.map((r) => r.id);

              // What the simulated viewer could see directly: can_view called as that viewer's own login.
              if (simulated === undefined) await asUser(client, "anon");
              else await asUser(client, "authenticated", simulated.userId);
              let allowed: Set<string>;
              try {
                const res = await client.query<{ id: string; ok: boolean }>(
                  "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
                  [simulatedId, candidateIds],
                );
                allowed = new Set(res.rows.filter((r) => r.ok).map((r) => r.id));
              } finally {
                await resetRole(client);
              }

              // view_as, called by the login that controls the owner's page.
              await asUser(client, "authenticated", owner.userId);
              let rows: { section: string; item_id: string; audience: string | null }[];
              try {
                const res = await client.query<{
                  section: string;
                  item_id: string;
                  audience: string | null;
                }>("select section, item_id, audience::text as audience from public.view_as($1, $2)", [
                  owner.id,
                  simulatedId,
                ]);
                rows = res.rows;
              } finally {
                await resetRole(client);
              }

              const returned = new Set(rows.map((r) => r.item_id));
              const tooMuch = [...returned].filter((id) => !allowed.has(id));
              if (tooMuch.length > 0) {
                throw new Error(
                  `view_as(${owner.handle}) as ${String(simulatedId)} returned item(s) the viewer cannot see: ${tooMuch.join(", ")}`,
                );
              }
              // 21.1 equality: every visible page item is listed.
              const missing = candidateIds.filter((id) => allowed.has(id) && !returned.has(id));
              if (missing.length > 0) {
                throw new Error(
                  `view_as(${owner.handle}) as ${String(simulatedId)} omitted visible item(s): ${missing.join(", ")}`,
                );
              }
              // Nothing outside the page: every returned id is a candidate.
              const stray = [...returned].filter((id) => !candidateIds.includes(id));
              if (stray.length > 0) {
                throw new Error(`view_as returned item(s) not on the owner's page: ${stray.join(", ")}`);
              }
              // 21.5: the owner's own audience is shown only when the simulated viewer is the owner.
              if (simulatedId !== owner.id && rows.some((r) => r.audience !== null)) {
                throw new Error("view_as returned an audience for a simulated viewer other than the owner");
              }
            });
          },
        ),
        // endOnFailure: a world takes 10 to 30 s over the pooler, so shrinking could not finish
        // inside PROPERTY_TIMEOUT_MS and a failure would show up only as a timeout.
        { numRuns: PROPERTY_RUNS, endOnFailure: true },
      );
    },
    PROPERTY_TIMEOUT_MS,
  );
});
