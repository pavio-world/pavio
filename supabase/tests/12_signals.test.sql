-- Signals: notifications, profile views and search appearances (Spec 00, Req 15, 16, 25.1, 25.2; DR-1).
-- The notifications table part comes first (task 10). Profile views (task 21), search appearances
-- (task 22) and the weekly summary (task 23) add their own sections below, each with its own
-- fixtures, and raise the plan count.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(57);

-- =============================================================================================
-- Notifications table (task 10; Req 15.1, 15.2, 15.10 to 15.13)
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Rita and Otto are people. Mark owns mark_shop, so he acts as it. Notifications are created
-- through private.notify, the only insert path.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('a1a1a1a1-0000-4000-8000-000000000001', 'rita.signals@example.invalid'),
  ('a1a1a1a1-0000-4000-8000-000000000002', 'otto.signals@example.invalid'),
  ('a1a1a1a1-0000-4000-8000-000000000003', 'mark.signals@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('b2b2b2b2-0000-4000-8000-000000000001', 'person', 'a1a1a1a1-0000-4000-8000-000000000001', 'rita_s', 'Rita'),
  ('b2b2b2b2-0000-4000-8000-000000000002', 'person', 'a1a1a1a1-0000-4000-8000-000000000002', 'otto_s', 'Otto'),
  ('b2b2b2b2-0000-4000-8000-000000000003', 'person', 'a1a1a1a1-0000-4000-8000-000000000003', 'mark_s', 'Mark');
insert into public.profiles (id, type, handle, display_name) values
  ('b2b2b2b2-0000-4000-8000-000000000004', 'business', 'mark_shop', 'Mark''s Shop');
insert into public.profile_managers (profile_id, user_id, role) values
  ('b2b2b2b2-0000-4000-8000-000000000004', 'a1a1a1a1-0000-4000-8000-000000000003', 'owner');

-- Rita: a connection request from Otto, and a count with no actor.
select private.notify('b2b2b2b2-0000-4000-8000-000000000001', 'connection_request',
                      'b2b2b2b2-0000-4000-8000-000000000002', 'c3c3c3c3-0000-4000-8000-000000000001', null);
select private.notify('b2b2b2b2-0000-4000-8000-000000000001', 'weekly_search_appearances',
                      null, null, '{"count": 3}');
-- Otto: a connection request from Rita.
select private.notify('b2b2b2b2-0000-4000-8000-000000000002', 'connection_request',
                      'b2b2b2b2-0000-4000-8000-000000000001', 'c3c3c3c3-0000-4000-8000-000000000002', null);
-- mark_shop: a new follower, Rita.
select private.notify('b2b2b2b2-0000-4000-8000-000000000004', 'new_follower',
                      'b2b2b2b2-0000-4000-8000-000000000001', 'c3c3c3c3-0000-4000-8000-000000000003', null);

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, foreign keys, checks, indexes, RLS, policies and grants
-- (Req 15.1, 15.2, 15.11 to 15.13, 22.1 to 22.5).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'notifications', 'notifications exists');
select columns_are('public', 'notifications', array[
  'id', 'recipient_profile_id', 'type', 'actor_profile_id', 'reference_id', 'data', 'read_at', 'created_at'
], 'notifications has exactly its eight columns');
select col_type_is('public', 'notifications', 'type', 'notification_type',
  'notifications.type is the notification_type enum');
select enum_has_labels('public', 'notification_type', array[
  'connection_request', 'connection_accepted', 'new_follower', 'vouch_received',
  'profile_viewed', 'weekly_search_appearances'
], 'notification_type has the six types');
select col_not_null('public', 'notifications', 'recipient_profile_id', 'a notification always has a recipient');
select col_is_null('public', 'notifications', 'actor_profile_id', 'the actor is optional');
select col_is_null('public', 'notifications', 'reference_id', 'the reference id is optional');
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.notifications'::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.notifications'::regclass
                                   and attname = 'recipient_profile_id')]::smallint[]),
  'c', 'the recipient foreign key cascades on delete');
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.notifications'::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.notifications'::regclass
                                   and attname = 'actor_profile_id')]::smallint[]),
  'c', 'the actor foreign key cascades on delete');
select is((select count(*)::int from pg_catalog.pg_constraint
           where conrelid = 'public.notifications'::regclass and contype = 'f'
             and confrelid <> 'public.profiles'::regclass),
  0, 'reference_id has no foreign key');
select throws_ok($$ insert into public.notifications (recipient_profile_id, type, data)
                    values ('b2b2b2b2-0000-4000-8000-000000000001', 'new_follower', '[]') $$,
  '23514', null, 'data must be a JSON object');
select has_index('public', 'notifications', 'notifications_recipient_created_idx',
  array['recipient_profile_id', 'created_at'], 'notifications has the recipient and created_at index');
select has_index('public', 'notifications', 'notifications_actor_profile_id_idx', 'actor_profile_id',
  'notifications has the actor index');
select ok((select relrowsecurity from pg_class where oid = 'public.notifications'::regclass),
  'RLS is enabled on notifications');
select policies_are('public', 'notifications', array[
  'notifications_authenticated_select', 'notifications_authenticated_update'
], 'notifications has exactly its two policies');
select table_privs_are('public', 'notifications', 'anon', array[]::text[],
  'anon has no privilege on notifications');
select table_privs_are('public', 'notifications', 'authenticated', array['SELECT'],
  'authenticated holds only the table level select on notifications');
select is_empty($$ select a.attname from pg_catalog.pg_attribute a
                   where a.attrelid = 'public.notifications'::regclass and a.attnum > 0 and not a.attisdropped
                     and a.attname <> 'read_at'
                     and has_column_privilege('authenticated', 'public.notifications', a.attname, 'UPDATE') $$,
  'authenticated may update no column other than read_at');
select ok(has_column_privilege('authenticated', 'public.notifications', 'read_at', 'UPDATE'),
  'authenticated may update read_at');
select ok(not has_any_column_privilege(r, 'public.notifications', 'INSERT'), r || ' cannot insert notifications')
from unnest(array['anon', 'authenticated']) as r;

-- The notify helper: definer, pinned search_path, no execute for the API roles (Req 15.11).
select is_definer('private', 'notify', array['uuid', 'notification_type', 'uuid', 'uuid', 'jsonb'],
  'private.notify is security definer');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = 'private.notify(uuid, public.notification_type, uuid, uuid, jsonb)'::regprocedure)) c
                  where c = 'search_path=""'),
  'private.notify sets an empty search_path');
select ok(not has_function_privilege(r, 'private.notify(uuid, public.notification_type, uuid, uuid, jsonb)', 'execute'),
  r || ' cannot execute private.notify')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- The data shape: actor handle, display name and type only, plus the caller's extra fields (Req 15.10).
select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'connection_request'),
  '{"actor_handle": "otto_s", "actor_display_name": "Otto", "actor_type": "person"}'::jsonb,
  'notify stores only the actor''s handle, display name and type');
select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'weekly_search_appearances'),
  '{"count": 3}'::jsonb, 'notify with no actor stores only the extra fields');
select is((select read_at from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'connection_request'),
  null::timestamptz, 'a new notification is unread');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Rita, in the canary order (DR-1): she reads and marks her own notifications.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Rita claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Rita');

select is((select count(*)::int from public.notifications), 2, 'Rita reads exactly her two notifications (Req 15.12)');
select lives_ok($$ update public.notifications set read_at = now()
                   where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
                     and type = 'connection_request' $$,
  'Rita can mark a notification as read (Req 15.13)');
select isnt((select read_at from public.notifications
             where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'connection_request'),
  null::timestamptz, 'read_at is set');
select is((select row(type, actor_profile_id, reference_id, data)::text from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'connection_request'),
  row('connection_request'::public.notification_type, 'b2b2b2b2-0000-4000-8000-000000000002'::uuid,
      'c3c3c3c3-0000-4000-8000-000000000001'::uuid,
      '{"actor_handle": "otto_s", "actor_display_name": "Otto", "actor_type": "person"}'::jsonb)::text,
  'marking as read leaves every other field unchanged');
-- No other field can be changed (Req 15.13).
select throws_ok($$ update public.notifications set type = 'vouch_received'
                    where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' $$,
  '42501', null, 'Rita cannot change the type');
select throws_ok($$ update public.notifications set data = '{"body": "x"}'
                    where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' $$,
  '42501', null, 'Rita cannot change the data');
select throws_ok($$ update public.notifications set recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'
                    where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' $$,
  '42501', null, 'Rita cannot move a notification to another recipient');
select throws_ok($$ update public.notifications set actor_profile_id = null
                    where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' $$,
  '42501', null, 'Rita cannot change the actor');
-- Other people's notifications are invisible and untouchable.
select lives_ok($$ update public.notifications set read_at = now()
                   where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' $$,
  'Rita''s update of Otto''s notification runs without error');
-- Direct writes are rejected (Req 15.11).
select throws_ok($$ insert into public.notifications (recipient_profile_id, type)
                    values ('b2b2b2b2-0000-4000-8000-000000000001', 'new_follower') $$,
  '42501', null, 'authenticated cannot insert a notification directly');
select throws_ok($$ delete from public.notifications
                    where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' $$,
  '42501', null, 'authenticated cannot delete notifications');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Otto: he reads only his own, and Rita's update did not reach his.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Otto claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Otto');

select is_empty($$ select 1 from public.notifications
                   where recipient_profile_id <> 'b2b2b2b2-0000-4000-8000-000000000002' $$,
  'Otto cannot read anyone else''s notifications');
select is((select read_at from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'),
  null::timestamptz, 'Otto''s notification is still unread after Rita''s update');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Mark: acts_as on the business decides access, not the login alone (Req 15.12).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Mark claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Mark');

select results_eq($$ select type::text from public.notifications $$, array['new_follower'],
  'Mark reads only the notification of the business he acts as');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read and no write (Req 15.11, 15.12, 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.notifications $$,
  '42501', null, 'anon cannot read notifications');
select throws_ok($$ insert into public.notifications (recipient_profile_id, type)
                    values ('b2b2b2b2-0000-4000-8000-000000000001', 'new_follower') $$,
  '42501', null, 'anon cannot insert a notification directly');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
