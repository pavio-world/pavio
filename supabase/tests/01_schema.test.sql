-- Schema foundation: required extensions (Spec 00, Req 1.6, 25.10, 25.11).
begin;
-- supabase test db logs in as cli_login_postgres, a NOINHERIT role with no usage on the
-- extensions schema where pgtap lives, so switch to postgres and put extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(4);

select has_extension('pg_trgm', 'pg_trgm is installed');
select has_extension('extensions', 'pg_trgm', 'pg_trgm lives in the extensions schema');
select has_extension('pg_cron', 'pg_cron is installed');
select has_schema('cron', 'pg_cron created the cron schema');

select * from finish();
rollback;
