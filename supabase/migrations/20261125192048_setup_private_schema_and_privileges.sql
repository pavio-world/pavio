-- Migration 2: the private schema, default privilege revokes and the first private helpers.
-- Spec 00 Req 3.9, 4.13, 22.3; design D-8 and "Grants and revokes strategy".

-- The private schema is never exposed to the API roles, now or later (D-8).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Stop Supabase's default grants to anon and authenticated from applying to new objects in public.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
-- The built-in EXECUTE to PUBLIC is a global default that a per-schema revoke cannot remove.
alter default privileges for role postgres revoke execute on functions from public;

-- Shared trigger that maintains updated_at (Req 3.9).
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;
revoke execute on function private.set_updated_at() from public;
revoke execute on function private.set_updated_at() from anon, authenticated;

-- True when the request comes through the API as anon or authenticated.
create or replace function private.is_api_caller()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') in ('anon', 'authenticated');
$$;
revoke execute on function private.is_api_caller() from public;
revoke execute on function private.is_api_caller() from anon, authenticated;

-- Today's date in Nairobi.
create or replace function private.nairobi_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (pg_catalog.now() at time zone 'Africa/Nairobi')::date;
$$;
revoke execute on function private.nairobi_today() from public;
revoke execute on function private.nairobi_today() from anon, authenticated;

-- First day of the current month in Nairobi.
create or replace function private.nairobi_month_start()
returns date
language sql
stable
set search_path = ''
as $$
  select pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'Africa/Nairobi')::date;
$$;
revoke execute on function private.nairobi_month_start() from public;
revoke execute on function private.nairobi_month_start() from anon, authenticated;

-- Immutable wrapper of array_to_string, used by the profiles generated columns.
create or replace function private.immutable_array_to_text(t text[])
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select pg_catalog.array_to_string(t, ' ');
$$;
revoke execute on function private.immutable_array_to_text(text[]) from public;
grant execute on function private.immutable_array_to_text(text[]) to anon, authenticated;

-- "What I do" tags: at most 20, each 1 to 40 characters, lowercase and trimmed (Req 4.13).
create or replace function private.tags_valid(t text[])
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select t is not null
    and pg_catalog.cardinality(t) <= 20
    and not exists (
      select 1
      from pg_catalog.unnest(t) as x(tag)
      where x.tag is null
         or pg_catalog.char_length(x.tag) not between 1 and 40
         or x.tag <> pg_catalog.lower(pg_catalog.btrim(x.tag))
    );
$$;
revoke execute on function private.tags_valid(text[]) from public;
grant execute on function private.tags_valid(text[]) to anon, authenticated;
;
