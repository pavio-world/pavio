// Circle privacy property (spec 00, task 38). Property 10 carries the comment
// `// Feature: 00-database-foundation, Property 10: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every
// assertion, and runs inside withRolledBackTx.
//
// Circle private names are generated as `priv-<token>` and member labels as
// `label-<token>`, so a label can never equal or contain a private name.
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import { insertScenario, resolveViewer, scenarioArb, viewerArb } from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

/** Per-test timeout. One generated world takes about 15 s to insert over the pooler. */
const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

/**
 * Runs one read as the current API caller inside a savepoint and returns every
 * row as text. A rule rejection (PT* error) or a missing grant is a legitimate
 * refusal and returns an empty string; any other error is rethrown.
 */
async function readSurface(client: Client, sql: string, params: unknown[]): Promise<string> {
  await client.query("savepoint surface_read");
  try {
    const res = await client.query(sql, params);
    await client.query("release savepoint surface_read");
    return JSON.stringify(res.rows);
  } catch (error) {
    await client.query("rollback to savepoint surface_read");
    await client.query("release savepoint surface_read");
    const code = (error as { code?: unknown }).code;
    // 42501: the role has no grant on the surface, so nothing can be read from it.
    if (typeof code === "string" && (code.startsWith("PT") || code === "42501")) return "";
    throw error;
  }
}

describe("circle privacy properties", () => {
  // Feature: 00-database-foundation, Property 10: A circle private name never reaches a non-owner
  // **Validates: Requirements 9.10, 9.11, 9.17, 22.8, 13.10**
  it(
    "Property 10: no granted surface returns a circle private name to a viewer who does not own the circle",
    async () => {
      await fc.assert(
        fc.asyncProperty(scenarioArb, viewerArb, async (spec, viewerSpec) => {
          await withRolledBackTx(async (client) => {
            const fixture = await insertScenario(client, spec);
            if (fixture.circles.length === 0) return;
            const viewer = resolveViewer(fixture, viewerSpec);

            // Private names this viewer does not own. A name the viewer owns itself may be seen.
            const ownedNames = new Set(
              fixture.circles
                .filter((c) => {
                  const owner = fixture.profiles.find((p) => p.id === c.ownerId);
                  return (
                    viewer.sub !== undefined && owner !== undefined && owner.controllerIds.includes(viewer.sub)
                  );
                })
                .map((c) => c.spec.privateName),
            );
            const secrets = [...new Set(fixture.circles.map((c) => c.spec.privateName))].filter(
              (n) => !ownedNames.has(n),
            );
            if (secrets.length === 0) return;

            const profileIds = fixture.profiles.map((p) => p.id);
            const itemIds = fixture.content.map((c) => c.id);
            const storyIds = fixture.content.filter((c) => c.contentType === "story").map((c) => c.id);
            const viewerId = viewer.profileId;

            const surfaces: [string, string, unknown[]][] = [
              ["circles", "select * from public.circles", []],
              ["circle_members", "select * from public.circle_members", []],
              ["item_circles", "select * from public.item_circles", []],
              ["groups", "select * from public.groups", []],
              ["notifications", "select * from public.notifications", []],
              [
                "can_view",
                "select t.id, public.can_view(t.id, $1) as ok from unnest($2::uuid[]) as t(id)",
                [viewerId, itemIds],
              ],
              [
                "page_items",
                `select t.id, p.* from unnest($2::uuid[]) as t(id)
                 cross join lateral public.page_items(t.id, $1) as p`,
                [viewerId, profileIds],
              ],
              [
                "story_label",
                `select t.id, l.* from unnest($2::uuid[]) as t(id)
                 cross join lateral public.story_label(t.id, $1) as l`,
                [viewerId, storyIds],
              ],
              [
                "relationship_counts",
                `select t.id, c.* from unnest($1::uuid[]) as t(id)
                 cross join lateral public.relationship_counts(t.id) as c`,
                [profileIds],
              ],
              ...secrets.flatMap((s): [string, string, unknown[]][] => [
                [
                  "search_directory (private name query)",
                  "select * from public.search_directory($1, null, null, 50, 0, $2)",
                  [s, viewerId],
                ],
              ]),
              [
                "search_directory (broad query)",
                "select * from public.search_directory($1, null, null, 100, 0, $2)",
                ["person", viewerId],
              ],
            ];
            if (viewerId !== null) {
              surfaces.push([
                "my_relationships",
                "select * from public.my_relationships($1)",
                [viewerId],
              ]);
              // view_as is allowed only on a page the viewer acts as; the simulated viewer is the viewer.
              surfaces.push([
                "view_as",
                "select * from public.view_as($1, $1)",
                [viewerId],
              ]);
            }

            if (viewer.role === "anon") await asUser(client, "anon");
            else await asUser(client, "authenticated", viewer.sub);
            try {
              for (const [name, sql, params] of surfaces) {
                const text = await readSurface(client, sql, params);
                const leaked = secrets.find((s) => text.includes(s));
                if (leaked !== undefined) {
                  throw new Error(
                    `${name} returned circle private name ${leaked} to ${viewer.role} viewer ${String(viewerId)}`,
                  );
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
});
