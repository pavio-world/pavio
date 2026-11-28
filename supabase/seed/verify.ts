/**
 * Run twice check for the demo seed (Spec 00, Req 27.9).
 *
 * Run with `npm run seed:verify`. Runs the seed two times and exits non zero unless both fingerprints
 * (row counts, cast notification count, md5 over seeded columns excluding story times) are equal.
 */
import { runSeed, type Fingerprint } from "./seed";

/** Lists every difference between two fingerprints; an empty list means they match. */
function differences(first: Fingerprint, second: Fingerprint): string[] {
  const found: string[] = [];
  const tables = new Set([...Object.keys(first.counts), ...Object.keys(second.counts)]);
  for (const table of tables) {
    const a = first.counts[table];
    const b = second.counts[table];
    if (a !== b) found.push(`row count of ${table}: ${String(a)} then ${String(b)}`);
  }
  if (first.castNotifications !== second.castNotifications) {
    found.push(`cast notifications: ${first.castNotifications} then ${second.castNotifications}`);
  }
  if (first.md5 !== second.md5) found.push(`md5: ${first.md5} then ${second.md5}`);
  return found;
}

async function main(): Promise<void> {
  console.log("seed run 1");
  const first = await runSeed();
  console.log("seed run 2");
  const second = await runSeed();
  const found = differences(first, second);
  if (found.length > 0) {
    console.error("The seed is not idempotent:");
    for (const line of found) console.error(`  ${line}`);
    process.exitCode = 1;
    return;
  }
  console.log("seed verify: both runs produced the same fingerprint");
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
