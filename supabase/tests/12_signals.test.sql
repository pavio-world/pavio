-- Signals: notifications, profile views and search appearances (Spec 00, Req 15, 16, 25.1, 25.2; DR-1).
-- The notifications table part comes first (task 10), then profile views (task 21). Search
-- appearances (task 22) and the weekly summary (task 23) add their own sections below, and raise
-- the plan count. The profile views section reuses the notifications fixtures.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(160);

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

-- =============================================================================================
-- Profile views (task 21; Req 15.7, 15.10, 16.1 to 16.5, 25.1, 25.2)
-- Reuses the fixtures above: Rita, Otto and Mark are people, Mark manages mark_shop.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, keys, indexes, RLS, policy, grants, trigger and function privileges.
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'profile_views', 'profile_views exists');
select columns_are('public', 'profile_views', array[
  'id', 'viewed_profile_id', 'viewer_profile_id', 'viewed_on', 'viewed_at', 'created_at'
], 'profile_views has exactly its six columns (Req 16.1)');
select col_type_is('public', 'profile_views', 'viewed_on', 'date', 'viewed_on is a date');
select col_not_null('public', 'profile_views', 'viewed_on', 'a view always has a Nairobi day');
select is((select count(*)::int from pg_catalog.pg_constraint
           where conrelid = 'public.profile_views'::regclass and contype = 'f'
             and confrelid = 'public.profiles'::regclass and confdeltype = 'c'),
  2, 'both profile foreign keys cascade on delete');
select has_index('public', 'profile_views', 'profile_views_viewer_profile_id_idx', 'viewer_profile_id',
  'profile_views has the viewer index');
select has_index('public', 'profile_views', 'profile_views_viewed_on_idx',
  array['viewed_profile_id', 'viewed_on'], 'profile_views has the viewed page and day index');
select ok((select relrowsecurity from pg_class where oid = 'public.profile_views'::regclass),
  'RLS is enabled on profile_views');
select policies_are('public', 'profile_views', array['profile_views_authenticated_select'],
  'profile_views has exactly its one policy');
select table_privs_are('public', 'profile_views', 'anon', array[]::text[],
  'anon has no privilege on profile_views (Req 16.2)');
select table_privs_are('public', 'profile_views', 'authenticated', array['SELECT'],
  'authenticated holds only select on profile_views');
select ok(not has_any_column_privilege(r, 'public.profile_views', p),
  r || ' has no ' || p || ' privilege on profile_views')
from unnest(array['anon', 'authenticated']) as r, unnest(array['INSERT', 'UPDATE']) as p;
select has_trigger('public', 'profile_views', 'profile_views_after_insert',
  'profile_views has the notification trigger');
select is_definer('public', 'record_profile_view', array['uuid', 'uuid'],
  'record_profile_view is security definer');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = 'public.record_profile_view(uuid, uuid)'::regprocedure)) c
                  where c = 'search_path=""'),
  'record_profile_view sets an empty search_path');
select ok(not has_function_privilege(r, 'public.record_profile_view(uuid, uuid)', 'execute'),
  r || ' cannot execute record_profile_view')
from unnest(array['public', 'anon']) as r;
select ok(has_function_privilege('authenticated', 'public.record_profile_view(uuid, uuid)', 'execute'),
  'authenticated can execute record_profile_view');
select ok(not has_function_privilege(r, 'private.profile_views_after_insert()', 'execute'),
  r || ' cannot execute the notification trigger function')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- ---------------------------------------------------------------------------------------------
-- Signed in as Rita, in the canary order (DR-1): repeated views give one row (Req 16.4).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Rita claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Rita');

select lives_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                     'b2b2b2b2-0000-4000-8000-000000000002') $$,
  'Rita views Otto''s page');
select lives_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                     'b2b2b2b2-0000-4000-8000-000000000002') $$,
  'Rita views Otto''s page a second time on the same day');
select lives_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                     'b2b2b2b2-0000-4000-8000-000000000002') $$,
  'Rita views Otto''s page a third time on the same day');
select is((select count(*)::int from public.profile_views
           where viewer_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
             and viewed_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'),
  1, 'three views on one Nairobi day leave one row, readable by the viewer (Req 16.4, 16.5)');
select is((select viewed_on from public.profile_views
           where viewer_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
             and viewed_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'),
  (now() at time zone 'Africa/Nairobi')::date, 'the row holds the Nairobi day');

-- Rejections (Req 16.2, 16.3).
select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000002',
                                                      'b2b2b2b2-0000-4000-8000-000000000001') $$,
  'PT403', 'acting.not_allowed', 'Rita cannot record a view as Otto');
select throws_ok($$ select public.record_profile_view('d4d4d4d4-0000-4000-8000-000000000099',
                                                      'b2b2b2b2-0000-4000-8000-000000000001') $$,
  'PT403', 'acting.not_allowed', 'a viewer profile that does not exist is refused');
select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                      'b2b2b2b2-0000-4000-8000-000000000001') $$,
  'PT422', 'profile_view.own_page', 'Rita cannot view her own page (Req 16.3)');
-- No direct writes (Req 16.2).
select throws_ok($$ insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
                    values ('b2b2b2b2-0000-4000-8000-000000000003', 'b2b2b2b2-0000-4000-8000-000000000001', current_date) $$,
  '42501', null, 'authenticated cannot insert a profile view directly');
select throws_ok($$ update public.profile_views set viewed_on = current_date $$,
  '42501', null, 'authenticated cannot update a profile view');
select throws_ok($$ delete from public.profile_views $$,
  '42501', null, 'authenticated cannot delete a profile view');

-- A page managed by someone else is a normal page: Rita views the business.
select lives_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                     'b2b2b2b2-0000-4000-8000-000000000004') $$,
  'Rita views the mark_shop page');
select is((select count(*)::int from public.profile_views), 2,
  'Rita reads exactly the two views she made (Req 16.5)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Mark: he manages mark_shop, so his own pages are refused (Req 16.3).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Mark claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Mark');

select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000003',
                                                      'b2b2b2b2-0000-4000-8000-000000000004') $$,
  'PT422', 'profile_view.own_page', 'Mark as himself cannot view the business he manages');
select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000004',
                                                      'b2b2b2b2-0000-4000-8000-000000000003') $$,
  'PT422', 'profile_view.own_page', 'Mark as his business cannot view his own person page');
select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                      'b2b2b2b2-0000-4000-8000-000000000002') $$,
  'PT403', 'acting.not_allowed', 'Mark cannot record a view as Rita');
select lives_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000004',
                                                     'b2b2b2b2-0000-4000-8000-000000000001') $$,
  'Mark acting as mark_shop views Rita''s page');
select is((select count(*)::int from public.profile_views), 2,
  'Mark reads the view of mark_shop (viewed) and the view by mark_shop (viewer) (Req 16.5)');
select is_empty($$ select 1 from public.profile_views
                   where viewed_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' $$,
  'Mark cannot read Rita''s view of Otto');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Otto: he reads only the view of his own page (Req 16.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Otto claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Otto');

select results_eq($$ select viewer_profile_id from public.profile_views $$,
  array['b2b2b2b2-0000-4000-8000-000000000001'::uuid],
  'Otto reads only Rita''s view of his page, not the other views');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read, no execute, no write (Req 16.2, 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.profile_views $$,
  '42501', null, 'anon cannot read profile views');
select throws_ok($$ select public.record_profile_view('b2b2b2b2-0000-4000-8000-000000000001',
                                                      'b2b2b2b2-0000-4000-8000-000000000002') $$,
  '42501', null, 'anon cannot execute record_profile_view');
select throws_ok($$ insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
                    values ('b2b2b2b2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000001', current_date) $$,
  '42501', null, 'anon cannot insert a profile view directly');

-- ---------------------------------------------------------------------------------------------
-- Back as the test owner: the notifications and the table rules (Req 15.7, 15.10, 16.4).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);

select is((select count(*)::int from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' and type = 'profile_viewed'),
  1, 'three views by Rita on one day give Otto one profile_viewed notification (Req 15.7, 16.4)');
select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' and type = 'profile_viewed'),
  '{"actor_handle": "rita_s", "actor_display_name": "Rita", "actor_type": "person"}'::jsonb,
  'the notification data holds only the viewer''s handle, name and type (Req 15.10)');
select is((select row(actor_profile_id, reference_id)::text from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' and type = 'profile_viewed'),
  (select row(viewer_profile_id, id)::text from public.profile_views
   where viewer_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
     and viewed_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'),
  'the notification names the viewer as actor and the view row as reference');
select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001' and type = 'profile_viewed'),
  '{"actor_handle": "mark_shop", "actor_display_name": "Mark''s Shop", "actor_type": "business"}'::jsonb,
  'a view by a business page notifies the viewed person with the business as actor');
select is_empty($$ select 1 from public.notifications n, jsonb_object_keys(n.data) as k
                   where n.type = 'profile_viewed'
                     and k not in ('actor_handle', 'actor_display_name', 'actor_type') $$,
  'no profile_viewed notification holds any field beyond the allowed ones (Req 15.10)');
select is((select count(*)::int from public.notifications
           where type = 'profile_viewed'
             and recipient_profile_id in (select id from public.profiles where handle in ('rita_s', 'otto_s', 'mark_s', 'mark_shop'))),
  3, 'rejected views created no notification: Otto, mark_shop and Rita have one each');

-- A new Nairobi day is a new row and a new notification.
select lives_ok($$ insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
                   values ('b2b2b2b2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000001',
                           (now() at time zone 'Africa/Nairobi')::date - 1) $$,
  'a view on the previous Nairobi day is a different row');
select is((select count(*)::int from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002' and type = 'profile_viewed'),
  2, 'the next day''s view gives a second notification');
select throws_ok($$ insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
                    values ('b2b2b2b2-0000-4000-8000-000000000002', 'b2b2b2b2-0000-4000-8000-000000000001',
                            (now() at time zone 'Africa/Nairobi')::date) $$,
  '23505', null, 'the table itself keeps one row per viewer, page and day (Req 16.4)');
select throws_ok($$ insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
                    values ('b2b2b2b2-0000-4000-8000-000000000001', 'b2b2b2b2-0000-4000-8000-000000000001', current_date) $$,
  '23514', null, 'the table itself rejects a view of one''s own page (Req 16.3)');

-- =============================================================================================
-- Weekly search summary (task 23; Req 15.8, 15.9, 15.10, 16.10, 25.3)
-- Reuses the fixtures above. The week is the seven Nairobi days before today: today - 7 to
-- today - 1. Fixture appearances, by profile:
--   Rita      today - 7: 2, today - 3: 1, today - 1: 3      -> 6 inside the week
--   Otto      today - 2: 4, today: 5, today - 8: 7          -> 4 inside, the rest outside
--   Mark      today: 9, today - 8: 2                        -> none inside the week
--   mark_shop today - 2: 0                                  -> a zero total
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Catalog: the unique index, the function and who may execute it (Req 15.9, 22.3).
-- ---------------------------------------------------------------------------------------------
select ok(exists (select 1 from pg_catalog.pg_index i
                  join pg_catalog.pg_class c on c.oid = i.indexrelid
                  where i.indrelid = 'public.notifications'::regclass
                    and c.relname = 'notifications_weekly_uq'
                    and i.indisunique and i.indpred is not null),
  'notifications_weekly_uq is a partial unique index on notifications');
select has_function('private', 'send_weekly_search_summaries', array[]::text[],
  'private.send_weekly_search_summaries exists');
select function_returns('private', 'send_weekly_search_summaries', array[]::text[], 'integer',
  'the summary function returns the number of notifications created');
select is_definer('private', 'send_weekly_search_summaries', array[]::text[],
  'the summary function is security definer');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = 'private.send_weekly_search_summaries()'::regprocedure)) c
                  where c = 'search_path=""'),
  'the summary function sets an empty search_path');
select ok(not has_function_privilege(r, 'private.send_weekly_search_summaries()', 'execute'),
  r || ' cannot execute the summary function')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- ---------------------------------------------------------------------------------------------
-- Fixtures and the first run, as the test owner with no claims.
-- ---------------------------------------------------------------------------------------------
insert into public.search_appearances (profile_id, appeared_on, count) values
  ('b2b2b2b2-0000-4000-8000-000000000001', (now() at time zone 'Africa/Nairobi')::date - 7, 2),
  ('b2b2b2b2-0000-4000-8000-000000000001', (now() at time zone 'Africa/Nairobi')::date - 3, 1),
  ('b2b2b2b2-0000-4000-8000-000000000001', (now() at time zone 'Africa/Nairobi')::date - 1, 3),
  ('b2b2b2b2-0000-4000-8000-000000000002', (now() at time zone 'Africa/Nairobi')::date - 2, 4),
  ('b2b2b2b2-0000-4000-8000-000000000002', (now() at time zone 'Africa/Nairobi')::date, 5),
  ('b2b2b2b2-0000-4000-8000-000000000002', (now() at time zone 'Africa/Nairobi')::date - 8, 7),
  ('b2b2b2b2-0000-4000-8000-000000000003', (now() at time zone 'Africa/Nairobi')::date, 9),
  ('b2b2b2b2-0000-4000-8000-000000000003', (now() at time zone 'Africa/Nairobi')::date - 8, 2),
  ('b2b2b2b2-0000-4000-8000-000000000004', (now() at time zone 'Africa/Nairobi')::date - 2, 0);

create temp table weekly_run (created integer);
insert into weekly_run select private.send_weekly_search_summaries();

select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
             and type = 'weekly_search_appearances' and data ? 'week_start'),
  jsonb_build_object('count', 6,
                     'week_start', (now() at time zone 'Africa/Nairobi')::date - 7,
                     'week_end', (now() at time zone 'Africa/Nairobi')::date - 1),
  'Rita gets one summary: her six appearances inside the seven Nairobi days, with the two dates (Req 15.8)');
select is((select data from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000002'
             and type = 'weekly_search_appearances' and data ? 'week_start'),
  jsonb_build_object('count', 4,
                     'week_start', (now() at time zone 'Africa/Nairobi')::date - 7,
                     'week_end', (now() at time zone 'Africa/Nairobi')::date - 1),
  'Otto gets one summary that leaves out today and the day before the week');
select is((select count(*)::int from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000003'
             and type = 'weekly_search_appearances'),
  0, 'Mark has appearances only outside the week and gets no summary');
select is((select count(*)::int from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000004'
             and type = 'weekly_search_appearances'),
  0, 'mark_shop has a zero total and gets no summary (Req 15.8)');
select is((select created from weekly_run),
  (select count(*)::int from public.notifications
   where type = 'weekly_search_appearances'
     and data ->> 'week_start' = ((now() at time zone 'Africa/Nairobi')::date - 7)::text),
  'the function returns the number of summaries it created');
select is_empty($$ select 1 from public.notifications n, jsonb_object_keys(n.data) as k
                   where n.type = 'weekly_search_appearances' and n.data ? 'week_start'
                     and k not in ('count', 'week_start', 'week_end') $$,
  'a summary holds only the count and the two dates (Req 15.10)');
select is_empty($$ select 1 from public.notifications
                   where type = 'weekly_search_appearances' and data ? 'week_start'
                     and (actor_profile_id is not null or reference_id is not null) $$,
  'a summary names no actor and points at nothing');

-- ---------------------------------------------------------------------------------------------
-- A re-run in the same week adds nothing (Req 15.9), even after the numbers change.
-- ---------------------------------------------------------------------------------------------
select is(private.send_weekly_search_summaries(), 0, 'a second run in the same week creates nothing');
select is((select count(*)::int from public.notifications
           where recipient_profile_id in ('b2b2b2b2-0000-4000-8000-000000000001',
                                          'b2b2b2b2-0000-4000-8000-000000000002')
             and type = 'weekly_search_appearances' and data ? 'week_start'),
  2, 'Rita and Otto still have one summary each');
update public.search_appearances set count = count + 5
where profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
  and appeared_on = (now() at time zone 'Africa/Nairobi')::date - 1;
select is(private.send_weekly_search_summaries(), 0, 'a third run after the numbers changed still creates nothing');
select is((select (data ->> 'count')::int from public.notifications
           where recipient_profile_id = 'b2b2b2b2-0000-4000-8000-000000000001'
             and type = 'weekly_search_appearances' and data ? 'week_start'),
  6, 'Rita''s sent summary is not rewritten');

-- The index is per recipient and week: another week is allowed, the same week is not.
select lives_ok($$ select private.notify('b2b2b2b2-0000-4000-8000-000000000001', 'weekly_search_appearances',
                     null, null, jsonb_build_object('count', 1,
                       'week_start', (now() at time zone 'Africa/Nairobi')::date - 14,
                       'week_end', (now() at time zone 'Africa/Nairobi')::date - 8)) $$,
  'a summary for a different week is accepted');
select throws_ok($$ select private.notify('b2b2b2b2-0000-4000-8000-000000000001', 'weekly_search_appearances',
                      null, null, jsonb_build_object('count', 1,
                        'week_start', (now() at time zone 'Africa/Nairobi')::date - 14,
                        'week_end', (now() at time zone 'Africa/Nairobi')::date - 8)) $$,
  '23505', null, 'the table itself rejects a second summary for the same recipient and week');

-- ---------------------------------------------------------------------------------------------
-- The schedule (Req 15.8): Monday 05:00 UTC, which is 08:00 in Nairobi.
-- ---------------------------------------------------------------------------------------------
select is((select count(*)::int from cron.job where jobname = 'pavio-weekly-search-summary'),
  1, 'exactly one pavio-weekly-search-summary job exists');
select is((select schedule from cron.job where jobname = 'pavio-weekly-search-summary'),
  '0 5 * * 1', 'the job runs on Mondays at 05:00 UTC');
select is((select command from cron.job where jobname = 'pavio-weekly-search-summary'),
  'select private.send_weekly_search_summaries()', 'the job calls the summary function');
select ok((select active from cron.job where jobname = 'pavio-weekly-search-summary'),
  'the job is active');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Rita, in the canary order (DR-1): she reads her own summary, cannot run the
-- function and cannot read Otto's summary.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', 'a1a1a1a1-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Rita claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), 'a1a1a1a1-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Rita');

select is((select data from public.notifications
           where type = 'weekly_search_appearances'
             and data ->> 'week_start' = ((now() at time zone 'Africa/Nairobi')::date - 7)::text),
  jsonb_build_object('count', 6,
                     'week_start', (now() at time zone 'Africa/Nairobi')::date - 7,
                     'week_end', (now() at time zone 'Africa/Nairobi')::date - 1),
  'Rita reads her own summary and no other (Req 15.12)');
select throws_ok($$ select private.send_weekly_search_summaries() $$,
  '42501', null, 'authenticated cannot execute the summary function');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no execute.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');
select throws_ok($$ select private.send_weekly_search_summaries() $$,
  '42501', null, 'anon cannot execute the summary function');

set local role postgres;
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
