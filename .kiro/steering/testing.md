---
inclusion: auto
name: testing
description: How Pavio is tested. Use when writing, running or fixing tests, including pgTAP database tests, fast-check property based tests, Vitest unit tests and Playwright end to end tests.
---

# Pavio: testing

## Layers

| Layer | Tool | Location | Command |
|---|---|---|---|
| Database rules | pgTAP | `supabase/tests/` | `supabase test db --linked` |
| Properties | Vitest plus fast-check | `tests/property/` | `npm run test:property` |
| Units | Vitest | next to the code (`*.test.ts`) | `npm test` |
| Flows | Playwright | `tests/e2e/` | `npm run test:e2e` |

## Property based tests

Use them wherever a requirement says "for any" or "never": visibility, audiences, circles, Top 8 limits, expiry, string key parity between English and Swahili, colour contrast of AI themes. Generate random profiles, relationships, circles and items, run them against the real `pavio` database through a direct connection (`SUPABASE_DB_URL`), and assert the property. Each run happens inside its own transaction that is always rolled back, and simulates users with `set local role authenticated` plus `set local request.jwt.claims`, so RLS is tested exactly as the app experiences it and no data is left behind. Each property names the requirement it validates.

## Rules

- A task that changes behaviour is not complete until its tests pass.
- Never weaken or delete a failing test to make it pass; fix the code or raise the issue.
- When a property test finds a bug, keep the shrunk counterexample as a regular regression test and note it in `DEVLOG.md`.

## End to end demo flows

Keep a Playwright test for each demo moment: search for a nutritionist, open a page, connect, assign a circle, view as, post a story to a circle, switch to Swahili, toggle 2006 mode.
