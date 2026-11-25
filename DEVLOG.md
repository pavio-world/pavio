# Pavio build diary

A running log of how Pavio was built with Kiro for the Kiroween 2026 hackathon (Resurrection category). New entries are added automatically after each spec task by the build-diary hook.

## 25 Nov 2026 | Setup | Kiro workspace

Set up the `.kiro` workspace before writing any code: seven steering files (product, tech, structure and privacy always on; design system and Supabase loaded by file match; testing loaded automatically when relevant), six hooks (secret key guard, privacy tests on migration, type check, English and Swahili string parity, build diary, on demand privacy audit) and two custom reviewer agents (privacy and design). Chose a database first approach: Spec 00 designs the whole schema and the visibility engine before any feature is built.

## 25 Nov 2026 12:04 | 00-database-foundation | 1.1 Create the spec branch and commit the spec documents

Created the branch `spec/00-database-foundation` and rebuilt the three unpushed local `main` commits onto it as atomic commits, so `main` again matches GitHub. Added `tasks.meta.json` to `.gitignore` because it is Kiro tooling state. Committed the spec documents in `.kiro/specs/00-database-foundation/` and the prompt in `docs/kiro-prompts/00-database-foundation.md`.
