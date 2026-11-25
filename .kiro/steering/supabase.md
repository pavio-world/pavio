---
inclusion: fileMatch
fileMatchPattern: ["supabase/**", "src/lib/supabase/**", "**/*.sql"]
---

# Pavio: Supabase and migration rules

## Migrations

- Every schema change is a new timestamped file in `supabase/migrations/` created with `supabase migration new <name>`. Never edit a migration that has already been applied; write a new one.
- Each migration enables RLS and adds policies for any table it creates, in the same file.
- Use `uuid` primary keys (`gen_random_uuid()`), `created_at timestamptz not null default now()`, and `updated_at` with a trigger where rows change.
- Use Postgres enums or check constraints for fixed values (profile type, relationship type and status, audience).
- Add indexes for every foreign key and for the columns used by `can_view` and search.
- Content details that vary by type go in a `details jsonb` column validated by a check or by Zod at the edge, so new content types need no schema change.

## Functions

- Security definer functions must set `search_path = ''` and use fully qualified names.
- Keep `can_view` stable, fast and indexed; it runs on every content read.
- Expose only the functions the app needs through the API; revoke execute from `anon` where not needed.

## Tests

- pgTAP tests live in `supabase/tests/*.test.sql` and run with `supabase test db`.
- Every new table gets tests proving an unauthorised role cannot read or write it.

## Remote projects (no local database)

Pavio develops against hosted Supabase projects, not a local stack.

- **`pavio-dev`**: the project linked to this repo (`supabase link`). All building and testing happens here.
- **`pavio-prod`** (if created): the public demo at pavio.world. Only receives migrations that already passed on dev.

Rules:

- Write a migration file, then apply it with `supabase db push` (linked project). A task that adds a migration is not done until it is pushed and the tests pass.
- **Never** run `supabase db reset --linked`, drop tables, truncate, or delete data on any hosted project unless I explicitly ask in chat. Never point any command at `pavio-prod` without my explicit instruction.
- Every test must leave no data behind: pgTAP files run inside a transaction and end with `rollback`; property tests open their own transaction per run and roll it back.
- Enable the `pgtap` extension on the dev project (in the `extensions` schema) for database tests.
- Generate types with `supabase gen types typescript --linked > src/lib/supabase/types.ts` after every pushed migration.
- The direct database connection string for tests lives in `.env.local` as `SUPABASE_DB_URL` and points only at `pavio-dev`.

## Seed

Demo data lives in `supabase/seed/` and uses only invented people and businesses. It may use the secret key.
