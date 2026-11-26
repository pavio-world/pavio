// Number of cases each property runs (Req 26.17, 26.24; DR-3).
// Read from the PROPERTY_RUNS environment variable, default 25. Run once with
// PROPERTY_RUNS=100 before the pull request.

export const DEFAULT_PROPERTY_RUNS = 25;

/**
 * Parse a PROPERTY_RUNS value. `undefined` (variable not set) gives the
 * default. Any other value must be a positive integer written in digits,
 * otherwise the error names PROPERTY_RUNS.
 */
export function parsePropertyRuns(raw: string | undefined): number {
  if (raw === undefined) return DEFAULT_PROPERTY_RUNS;
  const runs = /^\d+$/.test(raw) ? Number(raw) : Number.NaN;
  if (!Number.isSafeInteger(runs) || runs < 1) {
    throw new Error(
      `PROPERTY_RUNS must be a positive integer (for example 25 or 100), got ${JSON.stringify(raw)}`,
    );
  }
  return runs;
}

export const PROPERTY_RUNS: number = parsePropertyRuns(process.env.PROPERTY_RUNS);
