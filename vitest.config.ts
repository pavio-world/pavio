import { defineConfig } from "vitest/config";

// The property suite talks to the hosted Supabase database, so each test
// gets a long timeout. Tests run once (no watch mode) and one file at a time
// so transactions against the shared database do not compete.
export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
    watch: false,
    testTimeout: 300_000,
    hookTimeout: 120_000,
    fileParallelism: false,
  },
});
