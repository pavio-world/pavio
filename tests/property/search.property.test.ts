// Search properties (spec 00, task 37). Property 9 is task 37.1; Properties 20 and 21
// (tasks 37.2 and 37.3) are added below in the same describe block and reuse the
// helpers here (`withSearchWorld`, `runSearch`). Each property carries the comment
// `// Feature: 00-database-foundation, Property N: ...`, uses { numRuns: PROPERTY_RUNS },
// inserts fixtures as the test owner, switches with asUser before every assertion, and
// runs inside withRolledBackTx.
import fc from "fast-check";
import type { Client } from "pg";
import { describe, it } from "vitest";
import {
  insertScenario,
  pick,
  scenarioArb,
  tryInsert,
  type Fixture,
  type FixtureProfile,
  type ScenarioSpec,
} from "./arbitraries";
import { asUser, resetRole, withRolledBackTx } from "./db";
import { PROPERTY_RUNS } from "./runs";

/** Per-test timeout. One generated world takes about 15 s to insert over the pooler. */
const PROPERTY_TIMEOUT_MS = 120_000 + PROPERTY_RUNS * 45_000;

// ---------------------------------------------------------------------------
// Shared helpers (reused by tasks 37.2 and 37.3)
// ---------------------------------------------------------------------------

/** The returns table of public.search_directory (migration create_search), in order. */
export const SEARCH_COLUMNS = [
  "profile_id",
  "type",
  "handle",
  "display_name",
  "bio",
  "avatar_path",
  "city",
  "country",
  "what_i_do",
  "dot_colour",
  "category",
  "search_trust",
  "rank",
] as const;

export interface SearchRow {
  profile_id: string;
  type: string;
  handle: string;
  display_name: string;
  bio: string | null;
  avatar_path: string | null;
  city: string | null;
  country: string | null;
  what_i_do: string[];
  dot_colour: string;
  category: string | null;
  search_trust: number;
  rank: number;
}

export interface SearchArgs {
  query: string;
  type: "person" | "business" | null;
  city: string | null;
  limit: number;
  offset: number;
}

/**
 * Calls public.search_directory as `anon` (searcher null) or as the login that
 * controls `searcher` (searcher id passed), then returns to the test owner.
 */
export async function runSearch(
  client: Client,
  args: SearchArgs,
  searcher: FixtureProfile | null,
): Promise<{ rows: SearchRow[]; fields: string[] }> {
  if (searcher === null) await asUser(client, "anon");
  else await asUser(client, "authenticated", searcher.userId);
  try {
    const res = await client.query<SearchRow>(
      "select * from public.search_directory($1, $2::public.profile_type, $3, $4, $5, $6)",
      [args.query, args.type, args.city, args.limit, args.offset, searcher?.id ?? null],
    );
    return { rows: res.rows, fields: res.fields.map((f) => f.name) };
  } finally {
    await resetRole(client);
  }
}

/** Inserts a generated world and runs `fn` on it, all inside one rolled back transaction. */
export async function withSearchWorld<T>(
  spec: ScenarioSpec,
  fn: (client: Client, fixture: Fixture) => Promise<T>,
): Promise<T> {
  return withRolledBackTx(async (client) => {
    const fixture = await insertScenario(client, spec);
    return fn(client, fixture);
  });
}

// ---------------------------------------------------------------------------
// Property 9 generators
// ---------------------------------------------------------------------------

/**
 * A query described as data, resolved after the world is inserted. It aims at
 * the things that must never be found: circle private names, member labels and
 * non public item text (marked `secret-` below).
 */
type QuerySpec =
  | { kind: "name"; pick: number }
  | { kind: "tag"; pick: number }
  | { kind: "bio"; pick: number }
  | { kind: "private_name"; pick: number }
  | { kind: "member_label"; pick: number }
  | { kind: "secret" }
  | { kind: "random"; text: string };

const querySpecArb: fc.Arbitrary<QuerySpec> = fc.oneof(
  fc.record({ kind: fc.constant("name" as const), pick: fc.nat(1000) }),
  fc.record({ kind: fc.constant("tag" as const), pick: fc.nat(1000) }),
  fc.record({ kind: fc.constant("bio" as const), pick: fc.nat(1000) }),
  fc.record({ kind: fc.constant("private_name" as const), pick: fc.nat(1000) }),
  fc.record({ kind: fc.constant("member_label" as const), pick: fc.nat(1000) }),
  fc.record({ kind: fc.constant("secret" as const) }),
  fc.record({ kind: fc.constant("random" as const), text: fc.string({ maxLength: 20 }) }),
);

interface CallSpec {
  query: QuerySpec;
  type: "person" | "business" | null;
  useCity: boolean;
  limit: number;
  /** A signed in searcher (profile pick), or null for anon. */
  searcherPick: number | null;
}

const callSpecArb: fc.Arbitrary<CallSpec> = fc.record({
  query: querySpecArb,
  type: fc.constantFrom<"person" | "business" | null>(null, null, "person", "business"),
  useCity: fc.boolean(),
  limit: fc.integer({ min: 1, max: 50 }),
  searcherPick: fc.option(fc.nat(1000), { nil: null }),
});

function resolveQueryText(spec: QuerySpec, fixture: Fixture): string {
  switch (spec.kind) {
    case "name":
      return pick(fixture.profiles, spec.pick)?.handle ?? "person";
    case "tag":
    case "bio":
    case "private_name":
    case "member_label":
      return "";
    case "secret":
      return "secret";
    case "random":
      return spec.text;
  }
}

/** Marks every non public item with a unique `secret-` text so a leak is easy to see. */
async function markNonPublicItems(client: Client): Promise<void> {
  await tryInsert(client, async () => {
    await client.query(
      `update public.content_items
         set details = details || jsonb_build_object('text', 'secret-' || left(id::text, 8))
       where audience <> 'public' and content_type in ('status', 'story')`,
    );
    await client.query(
      `update public.content_items
         set details = details || jsonb_build_object('caption', 'secret-' || left(id::text, 8))
       where audience <> 'public' and content_type = 'gallery'`,
    );
    return true;
  });
  await tryInsert(client, async () => {
    await client.query(
      "update public.vouches set body = 'secret-' || left(id::text, 8) where audience <> 'public'",
    );
    return true;
  });
}

interface ProfileFacts {
  type: string;
  handle: string;
  display_name: string;
  bio: string | null;
  avatar_path: string | null;
  city: string | null;
  country: string | null;
  what_i_do: string[];
  dot_colour: string;
  category: string | null;
  search_trust: number;
}

/** Reads the public truth about every profile as the test owner. */
async function readProfileFacts(client: Client): Promise<Map<string, ProfileFacts>> {
  const res = await client.query<ProfileFacts & { id: string }>(
    `select p.id, p.type::text as type, p.handle, p.display_name, p.bio, p.avatar_path,
            p.city, p.country, p.what_i_do, p.dot_colour::text as dot_colour,
            bd.category, private.search_trust(p.id) as search_trust
       from public.profiles p
       left join public.business_details bd on bd.profile_id = p.id`,
  );
  return new Map(
    res.rows.map(({ id, ...rest }): [string, ProfileFacts] => [id, rest]),
  );
}

describe("search properties", () => {
  // Feature: 00-database-foundation, Property 9: Search returns only public fields and public items
  // **Validates: Requirements 24.5, 24.2, 22.4**
  it(
    "Property 9: search_directory returns only the public column set and only public data",
    async () => {
      await fc.assert(
        fc.asyncProperty(
          scenarioArb,
          fc.array(callSpecArb, { minLength: 3, maxLength: 5 }),
          async (spec, calls) => {
            await withSearchWorld(spec, async (client, fixture) => {
              // Make every private value recognisable. Language 'sw' differs from the default.
              await client.query("update public.profiles set preferred_language = 'sw'");
              await markNonPublicItems(client);
              const facts = await readProfileFacts(client);

              // Strings that must never appear in any result.
              const forbidden = [
                ...fixture.circles.flatMap((c) => [c.spec.privateName, c.spec.memberLabel]),
                ...fixture.profiles.flatMap((p) => [p.userId, ...p.controllerIds]),
              ];
              const secretMarker = "secret-";

              for (const call of calls) {
                // Text drawn from private data is aimed at the search, not at the result check.
                let text = resolveQueryText(call.query, fixture);
                const circle = pick(fixture.circles, "pick" in call.query ? call.query.pick : 0);
                const profile = pick(fixture.profiles, "pick" in call.query ? call.query.pick : 0);
                const profileFacts = profile === undefined ? undefined : facts.get(profile.id);
                if (call.query.kind === "tag") text = profileFacts?.what_i_do[0] ?? "tag";
                if (call.query.kind === "bio") text = profileFacts?.bio ?? "bio";
                if (call.query.kind === "private_name") text = circle?.spec.privateName ?? "priv";
                if (call.query.kind === "member_label") text = circle?.spec.memberLabel ?? "label";
                if (call.query.kind === "name") text = profileFacts?.display_name ?? text;

                const city = call.useCity ? (profileFacts?.city ?? "nairobi") : null;
                const searcher =
                  call.searcherPick === null ? null : (pick(fixture.profiles, call.searcherPick) ?? null);
                const args = { query: text, type: call.type, city, limit: call.limit, offset: 0 };
                const label = `search_directory(${JSON.stringify(args)}) as ${searcher?.handle ?? "anon"}`;

                const { rows, fields } = await runSearch(client, args, searcher);

                // 24.5: exactly the public column set, nothing added.
                if (JSON.stringify(fields) !== JSON.stringify(SEARCH_COLUMNS)) {
                  throw new Error(`${label} returned columns ${fields.join(",")}`);
                }
                if (rows.length > call.limit) {
                  throw new Error(`${label} returned ${rows.length} rows, over the limit`);
                }

                const seen = new Set<string>();
                for (const row of rows) {
                  if (seen.has(row.profile_id)) throw new Error(`${label} repeated ${row.profile_id}`);
                  seen.add(row.profile_id);
                  const truth = facts.get(row.profile_id);
                  if (truth === undefined) {
                    throw new Error(`${label} returned an unknown profile ${row.profile_id}`);
                  }
                  // Every value is the stored public value of that profile (24.2).
                  for (const key of Object.keys(truth) as (keyof ProfileFacts)[]) {
                    if (JSON.stringify(row[key]) !== JSON.stringify(truth[key])) {
                      throw new Error(
                        `${label}: ${key} of ${truth.handle} is ${JSON.stringify(row[key])}, stored public value ${JSON.stringify(truth[key])}`,
                      );
                    }
                  }
                  if (call.type !== null && row.type !== call.type) {
                    throw new Error(`${label} ignored the type filter`);
                  }
                  if (city !== null && (row.city ?? "").toLowerCase() !== city.trim().toLowerCase()) {
                    throw new Error(`${label} ignored the city filter`);
                  }
                }

                // 22.4: no private name, label, login id or non public item text anywhere.
                const dump = JSON.stringify(rows);
                for (const value of forbidden) {
                  if (value !== "" && dump.includes(value)) {
                    throw new Error(`${label} leaked ${JSON.stringify(value)}`);
                  }
                }
                // Public bios and names are random text and could contain this by chance only if
                // it begins with the marker, which the generators never produce.
                if (dump.includes(secretMarker)) {
                  throw new Error(`${label} leaked non public item text`);
                }
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
