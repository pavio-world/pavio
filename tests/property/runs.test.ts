import fc from "fast-check";
import { describe, expect, it } from "vitest";
import { DEFAULT_PROPERTY_RUNS, parsePropertyRuns } from "./runs";

describe("parsePropertyRuns", () => {
  it("defaults to 25 when the variable is not set", () => {
    expect(DEFAULT_PROPERTY_RUNS).toBe(25);
    expect(parsePropertyRuns(undefined)).toBe(25);
  });

  it("accepts 100", () => {
    expect(parsePropertyRuns("100")).toBe(100);
  });

  it.each(["0", "-5", "2.5", "abc", "", " 5", "1e3", "NaN", "99999999999999999999"])(
    "throws an error naming PROPERTY_RUNS for %j",
    (raw) => {
      expect(() => parsePropertyRuns(raw)).toThrow(/PROPERTY_RUNS/);
    },
  );

  it("round trips any positive integer", () => {
    fc.assert(
      fc.property(fc.integer({ min: 1, max: 1_000_000 }), (n) => {
        expect(parsePropertyRuns(String(n))).toBe(n);
      }),
      { numRuns: 50 },
    );
  });
});
