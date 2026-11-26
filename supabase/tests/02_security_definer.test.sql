-- Function hardening: search_path, volatility and execute privileges, plus the catalog-wide grants
-- and the DR-4 allowlist pin (Spec 00, Req 7.7, 13.13, 20.14, 21.7, 22.3, 22.9, 25.10, 25.11, 25.13; D-8, DR-2, DR-4).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;

select plan(60);

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

-- ---------------------------------------------------------------------------------------------
-- Catalog-wide function checks (Spec 00 task 29; Req 7.7, 13.13, 20.14, 21.7, 22.3, 22.9, 25.13;
-- DR-2, DR-4). Execute grants follow the design's Function execute grants table.
-- ---------------------------------------------------------------------------------------------

-- Every function in public pins search_path, definer or not (private is covered above).
select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and not exists (select 1 from pg_catalog.unnest(p.proconfig) c where c like 'search_path=%') $$,
  'every public function sets search_path'
);

-- The public security definer functions are exactly these 28 (prosecdef true); try_uuid is invoker.
select bag_eq(
  $$ select p.proname::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef $$,
  array['acts_as', 'can_view', 'page_items', 'story_label', 'relationship_counts', 'search_directory',
        'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
        'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
        'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
        'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
        'in_group', 'in_conversation', 'group_linked_circle', 'ai_record_call'],
  'the public security definer functions are exactly the 28 of the design'
);

-- try_uuid is the one public function that is not security definer; it is a plain invoker helper.
select ok(
  not (select prosecdef from pg_catalog.pg_proc where oid = 'public.try_uuid(text)'::regprocedure)
  and has_function_privilege('anon', 'public.try_uuid(text)', 'execute')
  and has_function_privilege('authenticated', 'public.try_uuid(text)', 'execute')
  and not has_function_privilege('public', 'public.try_uuid(text)', 'execute'),
  'try_uuid is invoker, executable by anon and authenticated, never by public'
);

-- Authenticated only row of the grants table, including view_as (Req 21.7, 22.3).
select bag_eq(
  $$ select p.proname::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array[
         'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
         'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
         'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
         'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
         'in_group', 'in_conversation', 'group_linked_circle']) $$,
  array['my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
        'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
        'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
        'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
        'in_group', 'in_conversation', 'group_linked_circle'],
  'each of the 21 authenticated only functions exists exactly once'
);
select is_empty(
  $$ select p.oid::regprocedure::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array[
         'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
         'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
         'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
         'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
         'in_group', 'in_conversation', 'group_linked_circle'])
       and (not p.prosecdef
            or not exists (select 1 from pg_catalog.unnest(p.proconfig) c where c like 'search_path=%')) $$,
  'every authenticated only function is security definer with search_path set'
);
select is_empty(
  $$ select p.oid::regprocedure::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array[
         'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
         'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
         'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
         'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
         'in_group', 'in_conversation', 'group_linked_circle'])
       and has_function_privilege('anon', p.oid, 'execute') $$,
  'anon cannot execute any authenticated only function, view_as included'
);
select is_empty(
  $$ select p.oid::regprocedure::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array[
         'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
         'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
         'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
         'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
         'in_group', 'in_conversation', 'group_linked_circle'])
       and has_function_privilege('public', p.oid, 'execute') $$,
  'public cannot execute any authenticated only function, view_as included'
);
select is_empty(
  $$ select p.oid::regprocedure::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname = any (array[
         'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
         'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
         'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
         'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
         'in_group', 'in_conversation', 'group_linked_circle'])
       and not has_function_privilege('authenticated', p.oid, 'execute') $$,
  'authenticated can execute every authenticated only function'
);

-- ai_record_call is for service_role only (DR-2; Req 17.7, 22.11, 25.13).
select ok(not has_function_privilege('anon', 'public.ai_record_call(uuid,uuid,numeric)', 'execute'),
  'anon cannot execute ai_record_call');
select ok(not has_function_privilege('authenticated', 'public.ai_record_call(uuid,uuid,numeric)', 'execute'),
  'authenticated cannot execute ai_record_call');
select ok(not has_function_privilege('public', 'public.ai_record_call(uuid,uuid,numeric)', 'execute'),
  'public cannot execute ai_record_call');
select ok(has_function_privilege('service_role', 'public.ai_record_call(uuid,uuid,numeric)', 'execute'),
  'service_role can execute ai_record_call');

-- Private functions other than the pure validators and media_kind_allowed are closed to the API roles
-- and to public, including the trigger functions, private.can_view, private.notify and the cron job body.
select is_empty(
  $$ select p.oid::regprocedure::text
     from pg_catalog.pg_proc p
     where p.pronamespace = 'private'::regnamespace
       and p.proname <> all (array['tags_valid', 'immutable_array_to_text', 'content_details_valid',
                                   'opening_hours_valid', 'media_kind_allowed'])
       and (has_function_privilege('anon', p.oid, 'execute')
            or has_function_privilege('authenticated', p.oid, 'execute')
            or has_function_privilege('public', p.oid, 'execute')) $$,
  'no private function other than the validators and media_kind_allowed is executable by anon, authenticated or public'
);
select ok(
  has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute')
  and not has_function_privilege('public', f, 'execute'),
  f || ' is a pure validator: anon and authenticated may execute it, public may not'
)
from unnest(array['private.content_details_valid(content_type,jsonb)', 'private.opening_hours_valid(jsonb)']) as f;
select ok(
  not has_function_privilege('anon', 'private.media_kind_allowed(text,text)', 'execute')
  and not has_function_privilege('public', 'private.media_kind_allowed(text,text)', 'execute')
  and has_function_privilege('authenticated', 'private.media_kind_allowed(text,text)', 'execute'),
  'media_kind_allowed is executable by authenticated only (storage policies)'
);

-- PUBLIC holds execute on no function in public or private (Req 22.3).
select is_empty(
  $$ select p.oid::regprocedure::text from pg_catalog.pg_proc p
     where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
       and has_function_privilege('public', p.oid, 'execute') $$,
  'public holds execute on no function in the public or private schema'
);

-- DR-4 allowlist pin (Req 22.9): the security definer functions in public that anon can execute, and
-- those that authenticated can execute, each equal the design's Function execute grants table.
select bag_eq(
  $$ select p.proname::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and has_function_privilege('anon', p.oid, 'execute') $$,
  array['acts_as', 'can_view', 'page_items', 'story_label', 'relationship_counts', 'search_directory'],
  'the public security definer functions executable by anon equal the DR-4 anon allowlist'
);
select bag_eq(
  $$ select p.proname::text from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and has_function_privilege('authenticated', p.oid, 'execute') $$,
  array['acts_as', 'can_view', 'page_items', 'story_label', 'relationship_counts', 'search_directory',
        'my_profile_ids', 'my_profiles', 'is_profile_owner', 'view_as', 'request_relationship',
        'respond_to_connection', 'remove_relationship', 'my_relationships', 'add_profile_manager',
        'remove_profile_manager', 'create_content_item', 'create_vouch', 'set_item_audience',
        'item_audience', 'set_top8', 'my_received_vouches', 'record_profile_view', 'ai_can_call',
        'in_group', 'in_conversation', 'group_linked_circle'],
  'the public security definer functions executable by authenticated equal the DR-4 authenticated allowlist'
);

select * from finish();
rollback;
