-- Function hardening: search_path, volatility and execute privileges (Spec 00, Req 22.3, 25.10, 25.11; D-8).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;

select plan(41);

-- Every security definer function in public or private pins its search_path.
select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_catalog.pg_proc p
     where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
       and p.prosecdef
       and not exists (select 1 from pg_catalog.unnest(p.proconfig) c where c like 'search_path=%') $$,
  'every security definer function sets search_path'
);

-- Every private function pins its search_path, definer or not.
select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_catalog.pg_proc p
     where p.pronamespace = 'private'::regnamespace
       and not exists (select 1 from pg_catalog.unnest(p.proconfig) c where c like 'search_path=%') $$,
  'every private function sets search_path'
);

-- The six helpers of migration 2 each carry search_path= in proconfig.
select ok(
  exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc where oid = f::regprocedure)) c
          where c like 'search_path=%'),
  f || ' has search_path= in proconfig'
)
from unnest(array[
  'private.set_updated_at()',
  'private.is_api_caller()',
  'private.nairobi_today()',
  'private.nairobi_month_start()',
  'private.immutable_array_to_text(text[])',
  'private.tags_valid(text[])'
]) as f;

-- The validators must be immutable to feed generated columns and checks.
select volatility_is('private', 'immutable_array_to_text', array['text[]'], 'immutable',
  'immutable_array_to_text is immutable');
select volatility_is('private', 'tags_valid', array['text[]'], 'immutable',
  'tags_valid is immutable');

-- Non validator helpers: no execute for public, anon or authenticated.
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array[
  'private.set_updated_at()',
  'private.is_api_caller()',
  'private.nairobi_today()',
  'private.nairobi_month_start()'
]) as f
cross join unnest(array['public', 'anon', 'authenticated']) as r;

-- Pure validators: execute for anon and authenticated (checks run as the writer), never for public.
select ok(has_function_privilege(r, f, 'execute'), r || ' can execute ' || f)
from unnest(array['private.immutable_array_to_text(text[])', 'private.tags_valid(text[])']) as f
cross join unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public', f, 'execute'), 'public cannot execute ' || f)
from unnest(array['private.immutable_array_to_text(text[])', 'private.tags_valid(text[])']) as f;

-- is_api_caller is true only for anon or authenticated claims.
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for anon claims');
select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for authenticated claims');
select set_config('request.jwt.claims', json_build_object('role', 'postgres')::text, true);
select ok(not private.is_api_caller(), 'is_api_caller is false for a non API role claim');
select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-4000-8000-000000000001')::text, true);
select ok(not private.is_api_caller(), 'is_api_caller is false for claims without a role');
select set_config('request.jwt.claims', '', true);
select ok(not private.is_api_caller(), 'is_api_caller is false with no claims');

-- Behaviour of the small helpers.
select is(private.immutable_array_to_text(array['plumber', 'founder']), 'plumber founder',
  'immutable_array_to_text joins tags with a space');
select ok(private.tags_valid(array['plumber', 'nutritionist']), 'tags_valid accepts lowercase trimmed tags');
select ok(not private.tags_valid(array['Plumber']), 'tags_valid rejects capitals');
select ok(not private.tags_valid(array[' plumber']), 'tags_valid rejects untrimmed tags');
select ok(not private.tags_valid(array['']), 'tags_valid rejects an empty tag');
select ok(not private.tags_valid(array[repeat('a', 41)]), 'tags_valid rejects a 41 character tag');
select ok(not private.tags_valid(array(select 't' || g from generate_series(1, 21) g)),
  'tags_valid rejects 21 tags');
select is(private.nairobi_today(), (now() at time zone 'Africa/Nairobi')::date,
  'nairobi_today is the date in Nairobi');

select * from finish();
rollback;
