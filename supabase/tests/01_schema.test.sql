-- Schema foundation: required extensions and the private schema (Spec 00, Req 1.6, 22.3, 25.10, 25.11; D-8).
begin;
-- supabase test db logs in as cli_login_postgres, a NOINHERIT role with no usage on the
-- extensions schema where pgtap lives, so switch to postgres and put extensions on the path.
set local role postgres;
set local search_path = public, extensions;

select plan(9);

select has_extension('pg_trgm', 'pg_trgm is installed');
select has_extension('extensions', 'pg_trgm', 'pg_trgm lives in the extensions schema');
select has_extension('pg_cron', 'pg_cron is installed');
select has_schema('cron', 'pg_cron created the cron schema');

-- The private schema exists and the API roles can never use it (D-8).
select has_schema('private', 'the private schema exists');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon has no usage on private');
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated has no usage on private');
select ok(not has_schema_privilege('anon', 'private', 'CREATE'), 'anon cannot create in private');
select ok(not has_schema_privilege('authenticated', 'private', 'CREATE'), 'authenticated cannot create in private');

select * from finish();
rollback;
