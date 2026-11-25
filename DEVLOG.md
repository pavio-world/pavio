# Pavio build diary

A running log of how Pavio was built with Kiro for the Kiroween 2026 hackathon (Resurrection category). New entries are added automatically after each spec task by the build-diary hook.

## 25 Nov 2026 | Setup | Kiro workspace

Set up the `.kiro` workspace before writing any code: seven steering files (product, tech, structure and privacy always on; design system and Supabase loaded by file match; testing loaded automatically when relevant), six hooks (secret key guard, privacy tests on migration, type check, English and Swahili string parity, build diary, on demand privacy audit) and two custom reviewer agents (privacy and design). Chose a database first approach: Spec 00 designs the whole schema and the visibility engine before any feature is built.

## 25 Nov 2026 12:04 | 00-database-foundation | 1.1 Create the spec branch and commit the spec documents

Created the branch `spec/00-database-foundation` and rebuilt the three unpushed local `main` commits onto it as atomic commits, so `main` again matches GitHub. Added `tasks.meta.json` to `.gitignore` because it is Kiro tooling state. Committed the spec documents in `.kiro/specs/00-database-foundation/` and the prompt in `docs/kiro-prompts/00-database-foundation.md`.

## 25 Nov 2026 12:08 | 00-database-foundation | 1.2 Verify the existing Supabase folder and link

Confirmed that `supabase/config.toml` exists with `project_id = "pavio"`, that `supabase/.temp/project-ref` holds `tmglpalznmyonaynojyy`, and that `supabase/migrations/20261125040502_enable_pgtap.sql` is present. The Supabase MCP shows `enable_pgtap` as the only applied migration and `pgtap` 1.3.3 installed in the `extensions` schema, on the project at `tmglpalznmyonaynojyy.supabase.co`. Nothing was missing, so neither `supabase init` nor `supabase link` was run and no migration was reapplied.
## 25 Nov 2026 12:15 | 00-database-foundation | 1.3 Add the minimal Node tooling
Added a private `package.json` with dev dependencies only (Vitest, fast-check, pg, dotenv, tsx, TypeScript, the Node and pg type packages, and the Supabase JS client), plus `package-lock.json`, a strict `tsconfig.json` covering `tests/` and `supabase/seed/`, and `vitest.config.ts` with a five minute test timeout, no watch mode and one test file at a time. The tsconfig also includes `vitest.config.ts`, so `npm run typecheck` passes before any test files exist instead of failing with "no inputs". The existing `.gitignore` already covered `node_modules/`, `coverage/` and `*.log`, and the env files were left untouched.
## 25 Nov 2026 12:21 | 00-database-foundation | 2.1 Write docs/decisions/001-vouches-own-table.md
Wrote the first decision record, `docs/decisions/001-vouches-own-table.md`, which explains why vouches live in their own `vouches` table instead of `content_items`. Vouches have two parties with different write rights and a deferrable Top 8 constraint, so a separate table keeps vouch only columns off every other item. Vouch ids share the uuid space with content items, so `can_view` stays the single visibility check and resolves either kind. There was no existing `docs/decisions/` folder or template, so the record uses a title, date, Context, Decision and Consequences.
## 25 Nov 2026 12:27 | 00-database-foundation | 2.2 Write docs/decisions/002-can-view-core-and-wrapper.md
Wrote the second decision record, `docs/decisions/002-can-view-core-and-wrapper.md`. All visibility logic lives in `private.can_view`, which the API cannot call, and `public.can_view` only replaces a viewer id the caller does not act as with null before calling the core. `view_as` checks that the caller owns the page and then passes the simulated viewer straight to `private.page_items`, so it reuses the same rule and never shows more than that viewer could see.
