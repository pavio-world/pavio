-- Schema foundation: required extensions, the private schema and the enum types
-- (Spec 00, Req 1.6, 3.10, 4.9, 8.1, 11.2, 11.3, 15.2, 22.3, 25.10, 25.11; D-8).
begin;
-- supabase test db logs in as cli_login_postgres, a NOINHERIT role with no usage on the
-- extensions schema where pgtap lives, so switch to postgres and put extensions on the path.
set local role postgres;
set local search_path = public, extensions;

select plan(18);

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

select * from finish();
rollback;
