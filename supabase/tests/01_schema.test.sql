-- Schema foundation: required extensions, the private schema, the enum types and the lookup tables
-- (Spec 00, Req 1.6, 3.5, 3.8, 3.9, 3.10, 4.5, 4.7, 4.9, 8.1, 11.2, 11.3, 15.2, 17.2, 17.6,
-- 22.1, 22.2, 22.3, 22.5, 25.1, 25.4, 25.5, 25.10, 25.11; D-4, D-8).
begin;
-- supabase test db logs in as cli_login_postgres, a NOINHERIT role with no usage on the
-- extensions schema where pgtap lives, so switch to postgres and put extensions on the path.
set local role postgres;
set local search_path = public, extensions;

select plan(61);

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
-- Enum types carry exactly the labels in the design's Enumerated types table, in order.
select enum_has_labels('public', 'profile_type', array['person', 'business'], 'profile_type labels');
select enum_has_labels('public', 'manager_role', array['owner', 'manager'], 'manager_role labels');
select enum_has_labels('public', 'relationship_type', array['connection', 'follow'], 'relationship_type labels');
select enum_has_labels('public', 'relationship_status', array['pending', 'accepted', 'declined'], 'relationship_status labels');
select enum_has_labels('public', 'audience', array['public', 'connections', 'circles', 'group'], 'audience labels');
-- vouch is not a content type (Req 11.2).
select enum_has_labels('public', 'content_type', array['writing', 'gallery', 'status', 'story'], 'content_type labels, no vouch');
select enum_has_labels('public', 'notification_type',
  array['connection_request', 'connection_accepted', 'new_follower', 'vouch_received', 'profile_viewed', 'weekly_search_appearances'],
  'notification_type labels');
select enum_has_labels('public', 'dot_colour', array['terracotta', 'cherry', 'mustard', 'jade', 'lagoon', 'violet'], 'dot_colour labels');
select enum_has_labels('public', 'story_label_kind', array['member_label', 'only_for_you', 'shared_with_you'], 'story_label_kind labels');

-- Lookup tables: uuid keys, created_at and RLS on each (Req 3.8, 22.1, 25.5).
select has_table('public', 'languages', 'languages exists');
select col_is_pk('public', 'languages', 'id', 'languages.id is the primary key');
select col_type_is('public', 'languages', 'id', 'uuid', 'languages.id is uuid');
select col_default_is('public', 'languages', 'id', 'gen_random_uuid()', 'languages.id defaults to gen_random_uuid()');
select col_type_is('public', 'languages', 'created_at', 'timestamp with time zone', 'languages.created_at is timestamptz');
select col_default_is('public', 'languages', 'created_at', 'now()', 'languages.created_at defaults to now()');
select ok((select relrowsecurity from pg_class where oid = 'public.languages'::regclass), 'RLS is enabled on languages');

select has_table('public', 'reserved_handles', 'reserved_handles exists');
select col_is_pk('public', 'reserved_handles', 'id', 'reserved_handles.id is the primary key');
select col_type_is('public', 'reserved_handles', 'id', 'uuid', 'reserved_handles.id is uuid');
select col_default_is('public', 'reserved_handles', 'id', 'gen_random_uuid()', 'reserved_handles.id defaults to gen_random_uuid()');
select col_type_is('public', 'reserved_handles', 'created_at', 'timestamp with time zone', 'reserved_handles.created_at is timestamptz');
select col_default_is('public', 'reserved_handles', 'created_at', 'now()', 'reserved_handles.created_at defaults to now()');
select ok((select relrowsecurity from pg_class where oid = 'public.reserved_handles'::regclass), 'RLS is enabled on reserved_handles');

select has_table('public', 'app_settings', 'app_settings exists');
select col_is_pk('public', 'app_settings', 'id', 'app_settings.id is the primary key');
select col_type_is('public', 'app_settings', 'id', 'uuid', 'app_settings.id is uuid');
select col_default_is('public', 'app_settings', 'id', 'gen_random_uuid()', 'app_settings.id defaults to gen_random_uuid()');
select col_type_is('public', 'app_settings', 'created_at', 'timestamp with time zone', 'app_settings.created_at is timestamptz');
select col_default_is('public', 'app_settings', 'created_at', 'now()', 'app_settings.created_at defaults to now()');
select ok((select relrowsecurity from pg_class where oid = 'public.app_settings'::regclass), 'RLS is enabled on app_settings');

-- app_settings rows change, so updated_at is kept by the shared trigger (Req 3.9).
select col_type_is('public', 'app_settings', 'updated_at', 'timestamp with time zone', 'app_settings.updated_at is timestamptz');
select trigger_is('public', 'app_settings', 'app_settings_set_updated_at', 'private', 'set_updated_at',
  'app_settings updated_at trigger calls private.set_updated_at');
update public.app_settings set updated_at = '2000-01-01T00:00:00Z';
select is((select updated_at from public.app_settings), now(), 'the trigger overwrites updated_at on update');

-- Seeded rows (Req 4.5, 4.7, 17.2; D-4).
select set_eq('select code, name from public.languages',
  $$values ('en', 'English'), ('sw', 'Kiswahili')$$,
  'languages holds en and sw');
select set_eq('select word from public.reserved_handles',
  array['api', 'app', 'admin', 'auth', 'login', 'logout', 'signup', 'settings', 'search', 'circles',
        'notifications', 'edit', 'help', 'about', 'terms', 'privacy', 'pavio', 'www', 'static', '_next', 'demo'],
  'reserved_handles holds the 21 words of Req 4.5');
select results_eq(
  'select monthly_spend_cap_usd, ai_daily_call_limit, max_cost_per_call_usd from public.app_settings',
  $$values (10.00::numeric(10,2), 20, 0.0500::numeric(10,4))$$,
  'app_settings has one row: 10 USD a month, 20 calls a day, 0.05 USD per call');

-- Constraints reject bad rows (Req 25.4).
select throws_ok('insert into public.app_settings default values', '23505', null, 'a second app_settings row is rejected');
select throws_ok('insert into public.app_settings (singleton) values (false)', '23514', null, 'app_settings.singleton must be true');
select throws_ok('update public.app_settings set ai_daily_call_limit = 0', '23514', null, 'app_settings limits must be positive');
select throws_ok($$insert into public.languages (code, name) values ('EN', 'Shouting')$$, '23514', null, 'languages.code must match the code format');

-- API role privileges, checked as postgres (Req 17.6, 22.2, 22.3, 22.5).
select table_privs_are('public', 'languages', 'anon', array['SELECT'], 'anon may only select languages');
select table_privs_are('public', 'languages', 'authenticated', array['SELECT'], 'authenticated may only select languages');
select table_privs_are('public', 'reserved_handles', 'anon', array[]::text[], 'anon has no privilege on reserved_handles');
select table_privs_are('public', 'reserved_handles', 'authenticated', array[]::text[], 'authenticated has no privilege on reserved_handles');
select table_privs_are('public', 'app_settings', 'anon', array[]::text[], 'anon has no privilege on app_settings');
select table_privs_are('public', 'app_settings', 'authenticated', array[]::text[], 'authenticated has no privilege on app_settings');

-- Policies: languages is readable by both API roles; the other two have none, so RLS denies all.
select policies_are('public', 'languages', array['languages_anon_select', 'languages_authenticated_select'], 'languages has exactly its two select policies');
select policy_roles_are('public', 'languages', 'languages_anon_select', array['anon'], 'languages_anon_select applies to anon');
select policy_roles_are('public', 'languages', 'languages_authenticated_select', array['authenticated'], 'languages_authenticated_select applies to authenticated');
select policy_cmd_is('public', 'languages', 'languages_anon_select', 'select', 'languages_anon_select is a select policy');
select policy_cmd_is('public', 'languages', 'languages_authenticated_select', 'select', 'languages_authenticated_select is a select policy');
select is((select count(*)::int from pg_policies where schemaname = 'public' and tablename in ('reserved_handles', 'app_settings')),
  0, 'reserved_handles and app_settings have no policies');

select * from finish();
rollback;
