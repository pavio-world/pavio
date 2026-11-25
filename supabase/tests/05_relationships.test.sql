-- Relationships: the table, its guards, notification triggers and helpers (Spec 00, Req 8, 15.3 to
-- 15.6, 25.1, 25.4; decision 003; DR-1).
-- The table part comes first (task 11); the relationship RPCs follow with their own fixtures
-- (task 12).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(268);

-- =============================================================================================
-- Relationships table (task 11; Req 8.1 to 8.3, 8.6 to 8.12, 8.16, 8.18, 8.20, 8.21, 15.3 to 15.6)
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Amy, Ben, Cal, Dee and Eve are people. Dee owns dee_shop_r and dee_store_r. Eve owns
-- eve_cafe_r and Ben manages it.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('05050505-0000-4000-8000-000000000001', 'amy.rel@example.invalid'),
  ('05050505-0000-4000-8000-000000000002', 'ben.rel@example.invalid'),
  ('05050505-0000-4000-8000-000000000003', 'cal.rel@example.invalid'),
  ('05050505-0000-4000-8000-000000000004', 'dee.rel@example.invalid'),
  ('05050505-0000-4000-8000-000000000005', 'eve.rel@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('05b00000-0000-4000-8000-000000000001', 'person', '05050505-0000-4000-8000-000000000001', 'amy_r', 'Amy'),
  ('05b00000-0000-4000-8000-000000000002', 'person', '05050505-0000-4000-8000-000000000002', 'ben_r', 'Ben'),
  ('05b00000-0000-4000-8000-000000000003', 'person', '05050505-0000-4000-8000-000000000003', 'cal_r', 'Cal'),
  ('05b00000-0000-4000-8000-000000000004', 'person', '05050505-0000-4000-8000-000000000004', 'dee_r', 'Dee'),
  ('05b00000-0000-4000-8000-000000000005', 'person', '05050505-0000-4000-8000-000000000005', 'eve_r', 'Eve');
insert into public.profiles (id, type, handle, display_name) values
  ('05b00000-0000-4000-8000-000000000011', 'business', 'dee_shop_r', 'Dee''s Shop'),
  ('05b00000-0000-4000-8000-000000000012', 'business', 'dee_store_r', 'Dee''s Store'),
  ('05b00000-0000-4000-8000-000000000013', 'business', 'eve_cafe_r', 'Eve''s Cafe');
insert into public.profile_managers (profile_id, user_id, role) values
  ('05b00000-0000-4000-8000-000000000011', '05050505-0000-4000-8000-000000000004', 'owner'),
  ('05b00000-0000-4000-8000-000000000012', '05050505-0000-4000-8000-000000000004', 'owner'),
  ('05b00000-0000-4000-8000-000000000013', '05050505-0000-4000-8000-000000000005', 'owner'),
  ('05b00000-0000-4000-8000-000000000013', '05050505-0000-4000-8000-000000000002', 'manager');

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, foreign keys, checks, indexes, triggers, RLS and grants
-- (Req 8.1, 8.12, 22.1 to 22.3, 25.5; decision 003).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'relationships', 'relationships exists');
select columns_are('public', 'relationships', array[
  'id', 'requester_profile_id', 'target_profile_id', 'type', 'status', 'created_at', 'updated_at'
], 'relationships has exactly its seven columns');
select col_is_pk('public', 'relationships', 'id', 'relationships.id is the primary key');
select col_type_is('public', 'relationships', 'type', 'relationship_type',
  'relationships.type is the relationship_type enum');
select col_type_is('public', 'relationships', 'status', 'relationship_status',
  'relationships.status is the relationship_status enum');
select col_not_null('public', 'relationships', c, 'relationships.' || c || ' is not null')
from unnest(array['requester_profile_id', 'target_profile_id', 'type', 'status']) as c;
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.relationships'::regclass and contype = 'f'
             and confrelid = 'public.profiles'::regclass
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.relationships'::regclass
                                   and attname = c)]::smallint[]),
  'c', 'the ' || c || ' foreign key to profiles cascades on delete')
from unnest(array['requester_profile_id', 'target_profile_id']) as c;
select ok(exists (select 1 from pg_catalog.pg_constraint
                  where conrelid = 'public.relationships'::regclass and contype = 'c' and conname = c),
  'relationships has the check ' || c)
from unnest(array['relationships_not_self', 'relationships_follow_accepted']) as c;
select index_is_unique('public', 'relationships', 'relationships_pair_uq',
  'relationships_pair_uq is unique');
select ok(pg_catalog.pg_get_indexdef('public.relationships_pair_uq'::regclass)
            like '%LEAST(requester_profile_id, target_profile_id), GREATEST(requester_profile_id, target_profile_id), type)%',
  'relationships_pair_uq covers the unordered pair and the type');
select has_index('public', 'relationships', 'relationships_requester_profile_id_idx', 'requester_profile_id',
  'relationships has the requester index');
select has_index('public', 'relationships', 'relationships_target_type_status_idx',
  array['target_profile_id', 'type', 'status'], 'relationships has the target, type and status index');
select trigger_is('public', 'relationships', t, 'private', t, t || ' calls private.' || t)
from unnest(array['relationships_guard_insert', 'relationships_guard_update',
                  'relationships_after_insert', 'relationships_after_update']) as t;
select trigger_is('public', 'relationships', 'relationships_set_updated_at', 'private', 'set_updated_at',
  'relationships updated_at trigger calls private.set_updated_at');
select ok((select relrowsecurity from pg_class where oid = 'public.relationships'::regclass),
  'RLS is enabled on relationships');
select is((select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'relationships'),
  0, 'relationships has no policies, so RLS denies all direct access');
select table_privs_are('public', 'relationships', r, array[]::text[], r || ' has no privilege on relationships')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_any_column_privilege(r, 'public.relationships', p), r || ' has no column ' || p || ' on relationships')
from unnest(array['anon', 'authenticated']) as r
cross join unnest(array['SELECT', 'INSERT', 'UPDATE']) as p;

-- The new private functions: definer, pinned search_path, no execute for the API roles.
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array[
  'private.relationships_guard_insert()', 'private.relationships_guard_update()',
  'private.relationships_after_insert()', 'private.relationships_after_update()',
  'private.is_connected(uuid, uuid)', 'private.follows(uuid, uuid)', 'private.in_audience(uuid, uuid)'
]) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array[
  'private.relationships_guard_insert()', 'private.relationships_guard_update()',
  'private.relationships_after_insert()', 'private.relationships_after_update()',
  'private.is_connected(uuid, uuid)', 'private.follows(uuid, uuid)', 'private.in_audience(uuid, uuid)'
]) as f;
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array[
  'private.relationships_guard_insert()', 'private.relationships_guard_update()',
  'private.relationships_after_insert()', 'private.relationships_after_update()',
  'private.is_connected(uuid, uuid)', 'private.follows(uuid, uuid)', 'private.in_audience(uuid, uuid)'
]) as f
cross join unnest(array['public', 'anon', 'authenticated']) as r;
select volatility_is('private', f, array['uuid', 'uuid'], 'stable', 'private.' || f || ' is stable')
from unnest(array['is_connected', 'follows', 'in_audience']) as f;

-- ---------------------------------------------------------------------------------------------
-- Allowed shapes; the guard sets the status whatever the writer asks for (Req 8.2, 8.3, 8.6).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type, status)
                   values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000002',
                           'connection', 'accepted') $$,
  'a person can request a connection to a person');
select is((select status::text from public.relationships
           where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
             and target_profile_id = '05b00000-0000-4000-8000-000000000002'),
  'pending', 'a person to person connection starts pending even when accepted is asked for');
select lives_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type, status)
                   values ('05b00000-0000-4000-8000-000000000011', '05b00000-0000-4000-8000-000000000013',
                           'connection', 'declined') $$,
  'a business can request a connection to a business');
select is((select status::text from public.relationships
           where requester_profile_id = '05b00000-0000-4000-8000-000000000011'
             and target_profile_id = '05b00000-0000-4000-8000-000000000013'),
  'pending', 'a business to business connection starts pending even when declined is asked for');
select lives_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type, status)
                   values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000013',
                           'follow', 'pending') $$,
  'a person can follow a business');
select is((select status::text from public.relationships
           where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
             and target_profile_id = '05b00000-0000-4000-8000-000000000013'),
  'accepted', 'a follow is accepted at once even when pending is asked for');
select lives_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                   values ('05b00000-0000-4000-8000-000000000003', '05b00000-0000-4000-8000-000000000004',
                           'connection') $$,
  'Cal can request a connection to Dee');

-- ---------------------------------------------------------------------------------------------
-- Rejected shapes (Req 8.7 to 8.11).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000003',
                            'connection') $$,
  'PT422', 'relationship.business_to_person', 'a business cannot request a connection to a person');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000003',
                            'follow') $$,
  'PT422', 'relationship.business_to_person', 'a business cannot follow a person');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000003',
                            'follow') $$,
  'PT422', 'relationship.follow_shape', 'a person cannot follow a person');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000011', '05b00000-0000-4000-8000-000000000013',
                            'follow') $$,
  'PT422', 'relationship.follow_shape', 'a business cannot follow a business');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000003', '05b00000-0000-4000-8000-000000000013',
                            'connection') $$,
  'PT422', 'relationship.connection_shape', 'a person cannot request a connection to a business');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000001',
                            'connection') $$,
  'PT422', 'relationship.self', 'a person cannot connect with themselves');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000011', '05b00000-0000-4000-8000-000000000011',
                            'connection') $$,
  'PT422', 'relationship.self', 'a business cannot connect with itself');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000004', '05b00000-0000-4000-8000-000000000011',
                            'follow') $$,
  'PT422', 'relationship.managed_page', 'Dee cannot follow the business she owns');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000002', '05b00000-0000-4000-8000-000000000013',
                            'follow') $$,
  'PT422', 'relationship.managed_page', 'Ben cannot follow the business he manages');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000011', '05b00000-0000-4000-8000-000000000012',
                            'connection') $$,
  'PT422', 'relationship.managed_page', 'two businesses with the same owner cannot connect');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000099',
                            'connection') $$,
  'PT404', 'relationship.profile_not_found', 'a relationship to a missing profile is rejected');

-- ---------------------------------------------------------------------------------------------
-- One relationship per unordered pair and type (Req 8.12).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000002',
                            'connection') $$,
  'PT409', 'relationship.exists', 'a repeated connection request is rejected');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000002', '05b00000-0000-4000-8000-000000000001',
                            'connection') $$,
  'PT409', 'relationship.exists', 'a connection request in the other direction of a pending one is rejected');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000011',
                            'connection') $$,
  'PT409', 'relationship.exists', 'a reverse business connection request is rejected');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000013',
                            'follow') $$,
  'PT409', 'relationship.exists', 'a repeated follow is rejected');
select is((select count(*)::int from public.relationships
           where '05b00000-0000-4000-8000-000000000001' in (requester_profile_id, target_profile_id)
             and '05b00000-0000-4000-8000-000000000002' in (requester_profile_id, target_profile_id)),
  1, 'Amy and Ben still have exactly one relationship');

-- ---------------------------------------------------------------------------------------------
-- Requester, target and type are immutable (Req 8.20).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ update public.relationships set requester_profile_id = '05b00000-0000-4000-8000-000000000003'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'PT422', 'relationship.immutable', 'the requester cannot be changed');
select throws_ok($$ update public.relationships set target_profile_id = '05b00000-0000-4000-8000-000000000003'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'PT422', 'relationship.immutable', 'the target cannot be changed');
select throws_ok($$ update public.relationships set type = 'connection'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000013' $$,
  'PT422', 'relationship.immutable', 'the type cannot be changed');

-- ---------------------------------------------------------------------------------------------
-- Status transitions: only pending to accepted or declined, on a connection.
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ update public.relationships set status = 'accepted'
                   where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                     and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'a pending connection can be accepted');
select is((select status::text from public.relationships
           where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
             and target_profile_id = '05b00000-0000-4000-8000-000000000002'),
  'accepted', 'Amy and Ben are now connected');
select lives_ok($$ update public.relationships set status = 'accepted', updated_at = now()
                   where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                     and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'a no-op status update on an accepted connection runs');
select throws_ok($$ update public.relationships set status = 'declined'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'PT422', 'relationship.bad_transition', 'an accepted connection cannot be declined');
select throws_ok($$ update public.relationships set status = 'pending'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000002' $$,
  'PT422', 'relationship.bad_transition', 'an accepted connection cannot go back to pending');
select throws_ok($$ update public.relationships set status = 'pending'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000013' $$,
  'PT422', 'relationship.bad_transition', 'a follow cannot become pending');
select lives_ok($$ update public.relationships set status = 'declined'
                   where requester_profile_id = '05b00000-0000-4000-8000-000000000003'
                     and target_profile_id = '05b00000-0000-4000-8000-000000000004' $$,
  'a pending connection can be declined');
select throws_ok($$ update public.relationships set status = 'accepted'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000003'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000004' $$,
  'PT422', 'relationship.bad_transition', 'a declined connection cannot be accepted later');

-- ---------------------------------------------------------------------------------------------
-- After a decline (Req 8.16, 8.18): the requester cannot ask again, with the same error as a
-- pending duplicate; the former target can, and replaces the declined row.
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000003', '05b00000-0000-4000-8000-000000000004',
                            'connection') $$,
  'PT409', 'relationship.exists', 'the requester of a declined connection cannot ask again');
select lives_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                   values ('05b00000-0000-4000-8000-000000000004', '05b00000-0000-4000-8000-000000000003',
                           'connection') $$,
  'the former target of a declined connection can ask the original requester');
select results_eq($$ select requester_profile_id, target_profile_id, status::text from public.relationships
                     where '05b00000-0000-4000-8000-000000000003' in (requester_profile_id, target_profile_id)
                       and '05b00000-0000-4000-8000-000000000004' in (requester_profile_id, target_profile_id) $$,
  $$ values ('05b00000-0000-4000-8000-000000000004'::uuid, '05b00000-0000-4000-8000-000000000003'::uuid, 'pending') $$,
  'the declined row is replaced by one pending request from the former target');

-- ---------------------------------------------------------------------------------------------
-- Only the target responds when the call comes through the API (Req 8.21). Claims are set while
-- still the test owner, so the guard sees an API caller.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '05050505-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Dee claims');
select throws_ok($$ update public.relationships set status = 'accepted'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000004'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000003' $$,
  'PT403', 'relationship.only_target_responds', 'the requester cannot accept her own request');
select throws_ok($$ update public.relationships set status = 'declined'
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000004'
                      and target_profile_id = '05b00000-0000-4000-8000-000000000003' $$,
  'PT403', 'relationship.only_target_responds', 'the requester cannot decline her own request');
select set_config('request.jwt.claims',
  json_build_object('sub', '05050505-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select lives_ok($$ update public.relationships set status = 'accepted'
                   where requester_profile_id = '05b00000-0000-4000-8000-000000000004'
                     and target_profile_id = '05b00000-0000-4000-8000-000000000003' $$,
  'the target can accept the request');
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------------------------
-- Notifications from the triggers (Req 15.3 to 15.6). Rejected writes, the decline and the no-op
-- update created nothing; the guard's replacement of a declined row created one request.
-- ---------------------------------------------------------------------------------------------
select set_eq($$ select recipient_profile_id, type::text, actor_profile_id from public.notifications
                 where recipient_profile_id::text like '05b00000-%' $$,
  $$ values
     ('05b00000-0000-4000-8000-000000000002'::uuid, 'connection_request',  '05b00000-0000-4000-8000-000000000001'::uuid),
     ('05b00000-0000-4000-8000-000000000013'::uuid, 'connection_request',  '05b00000-0000-4000-8000-000000000011'::uuid),
     ('05b00000-0000-4000-8000-000000000013'::uuid, 'new_follower',        '05b00000-0000-4000-8000-000000000001'::uuid),
     ('05b00000-0000-4000-8000-000000000004'::uuid, 'connection_request',  '05b00000-0000-4000-8000-000000000003'::uuid),
     ('05b00000-0000-4000-8000-000000000001'::uuid, 'connection_accepted', '05b00000-0000-4000-8000-000000000002'::uuid),
     ('05b00000-0000-4000-8000-000000000003'::uuid, 'connection_request',  '05b00000-0000-4000-8000-000000000004'::uuid),
     ('05b00000-0000-4000-8000-000000000004'::uuid, 'connection_accepted', '05b00000-0000-4000-8000-000000000003'::uuid) $$,
  'the triggers created exactly the expected notifications');
select is((select count(*)::int from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000001' and type = 'connection_accepted'),
  1, 'the no-op update of an accepted connection added no second connection_accepted');
select is((select count(*)::int from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000003'
             and type <> 'connection_request'),
  0, 'the decline told Cal nothing (Req 15.5)');
select is((select reference_id from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000002' and type = 'connection_request'),
  (select id from public.relationships
   where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
     and target_profile_id = '05b00000-0000-4000-8000-000000000002'),
  'connection_request references the relationship');
select is((select reference_id from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000001' and type = 'connection_accepted'),
  (select id from public.relationships
   where requester_profile_id = '05b00000-0000-4000-8000-000000000001'
     and target_profile_id = '05b00000-0000-4000-8000-000000000002'),
  'connection_accepted references the relationship');
select is((select data from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000013' and type = 'new_follower'),
  '{"actor_handle": "amy_r", "actor_display_name": "Amy", "actor_type": "person"}'::jsonb,
  'new_follower holds only the follower''s handle, display name and type');
select is((select data from public.notifications
           where recipient_profile_id = '05b00000-0000-4000-8000-000000000013' and type = 'connection_request'),
  '{"actor_handle": "dee_shop_r", "actor_display_name": "Dee''s Shop", "actor_type": "business"}'::jsonb,
  'a business connection_request names the requesting business');

-- ---------------------------------------------------------------------------------------------
-- Helpers used by can_view and the all followers audience.
-- ---------------------------------------------------------------------------------------------
select ok(private.is_connected('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000002'),
  'is_connected is true for an accepted connection');
select ok(private.is_connected('05b00000-0000-4000-8000-000000000002', '05b00000-0000-4000-8000-000000000001'),
  'is_connected does not depend on the order');
select ok(not private.is_connected('05b00000-0000-4000-8000-000000000011', '05b00000-0000-4000-8000-000000000013'),
  'is_connected is false for a pending connection');
select ok(not private.is_connected('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000003'),
  'is_connected is false with no relationship');
select ok(not private.is_connected('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000013'),
  'a follow is not a connection');
select ok(private.follows('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000013'),
  'follows is true for Amy and eve_cafe_r');
select ok(not private.follows('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000001'),
  'follows depends on the direction');
select ok(not private.follows('05b00000-0000-4000-8000-000000000002', '05b00000-0000-4000-8000-000000000013'),
  'follows is false for a non follower');
select ok(private.in_audience('05b00000-0000-4000-8000-000000000002', '05b00000-0000-4000-8000-000000000001'),
  'a connection is in a person''s audience');
select ok(private.in_audience('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000001'),
  'a follower is in a business''s audience');
select ok(not private.in_audience('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000013'),
  'a followed business is not in its follower''s audience');
select ok(not private.in_audience('05b00000-0000-4000-8000-000000000013', '05b00000-0000-4000-8000-000000000011'),
  'a pending business connection is not in the audience');
select ok(not private.in_audience('05b00000-0000-4000-8000-000000000003', '05b00000-0000-4000-8000-000000000001'),
  'a stranger is not in the audience');
select ok(not private.in_audience('05b00000-0000-4000-8000-000000000002', null),
  'a null viewer is not in the audience');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Amy, in the canary order (DR-1): no direct access at all (decision 003).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '05050505-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Amy claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '05050505-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Amy');

select throws_ok($$ select 1 from public.relationships $$,
  '42501', null, 'authenticated cannot read relationships, not even her own');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000003',
                            'connection') $$,
  '42501', null, 'authenticated cannot insert a relationship directly');
select throws_ok($$ update public.relationships set status = 'accepted'
                    where target_profile_id = '05b00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'authenticated cannot update a relationship directly');
select throws_ok($$ delete from public.relationships
                    where requester_profile_id = '05b00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'authenticated cannot delete a relationship directly');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read and no write (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.relationships $$,
  '42501', null, 'anon cannot read relationships');
select throws_ok($$ insert into public.relationships (requester_profile_id, target_profile_id, type)
                    values ('05b00000-0000-4000-8000-000000000001', '05b00000-0000-4000-8000-000000000003',
                            'connection') $$,
  '42501', null, 'anon cannot insert a relationship');
select throws_ok($$ update public.relationships set status = 'accepted' $$,
  '42501', null, 'anon cannot update relationships');
select throws_ok($$ delete from public.relationships $$,
  '42501', null, 'anon cannot delete relationships');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------------------------
-- Deleting a profile deletes its relationships (on delete cascade).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ delete from public.profiles where id = '05b00000-0000-4000-8000-000000000002' $$,
  'Ben''s profile can be deleted');
select is((select count(*)::int from public.relationships
           where '05b00000-0000-4000-8000-000000000002' in (requester_profile_id, target_profile_id)),
  0, 'the deleted profile keeps no relationships');

-- =============================================================================================
-- Relationship RPCs (task 12; Req 8.4, 8.5, 8.13 to 8.19, 8.21, 8.23, 8.24, 22.4, 25.2, 25.3;
-- decision 003). Every call runs as a simulated user, switched in the canary order (DR-1).
-- Relationship ids returned by the RPCs are kept in transaction local settings (test.*).
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Fay, Gus, Hal, Ivy and Jo are people. Ivy owns ivy_bakery_rpc.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('05060606-0000-4000-8000-000000000001', 'fay.rpc@example.invalid'),
  ('05060606-0000-4000-8000-000000000002', 'gus.rpc@example.invalid'),
  ('05060606-0000-4000-8000-000000000003', 'hal.rpc@example.invalid'),
  ('05060606-0000-4000-8000-000000000004', 'ivy.rpc@example.invalid'),
  ('05060606-0000-4000-8000-000000000005', 'jo.rpc@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('05c00000-0000-4000-8000-000000000001', 'person', '05060606-0000-4000-8000-000000000001', 'fay_rpc', 'Fay'),
  ('05c00000-0000-4000-8000-000000000002', 'person', '05060606-0000-4000-8000-000000000002', 'gus_rpc', 'Gus'),
  ('05c00000-0000-4000-8000-000000000003', 'person', '05060606-0000-4000-8000-000000000003', 'hal_rpc', 'Hal'),
  ('05c00000-0000-4000-8000-000000000004', 'person', '05060606-0000-4000-8000-000000000004', 'ivy_rpc', 'Ivy'),
  ('05c00000-0000-4000-8000-000000000005', 'person', '05060606-0000-4000-8000-000000000005', 'jo_rpc', 'Jo');
insert into public.profiles (id, type, handle, display_name) values
  ('05c00000-0000-4000-8000-000000000011', 'business', 'ivy_bakery_rpc', 'Ivy''s Bakery');
insert into public.profile_managers (profile_id, user_id, role) values
  ('05c00000-0000-4000-8000-000000000011', '05060606-0000-4000-8000-000000000004', 'owner');

-- ---------------------------------------------------------------------------------------------
-- Catalog: definer, empty search_path, and execute grants exactly as the design's table (DR-4).
-- ---------------------------------------------------------------------------------------------
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array[
  'public.request_relationship(uuid, uuid, public.relationship_type)',
  'public.respond_to_connection(uuid, boolean)', 'public.remove_relationship(uuid)',
  'public.my_relationships(uuid)', 'public.relationship_counts(uuid)'
]) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array[
  'public.request_relationship(uuid, uuid, public.relationship_type)',
  'public.respond_to_connection(uuid, boolean)', 'public.remove_relationship(uuid)',
  'public.my_relationships(uuid)', 'public.relationship_counts(uuid)'
]) as f;
select ok(has_function_privilege('authenticated', f, 'execute'), 'authenticated can execute ' || f)
from unnest(array[
  'public.request_relationship(uuid, uuid, public.relationship_type)',
  'public.respond_to_connection(uuid, boolean)', 'public.remove_relationship(uuid)',
  'public.my_relationships(uuid)', 'public.relationship_counts(uuid)'
]) as f;
select ok(not has_function_privilege('anon', f, 'execute'), 'anon cannot execute ' || f)
from unnest(array[
  'public.request_relationship(uuid, uuid, public.relationship_type)',
  'public.respond_to_connection(uuid, boolean)', 'public.remove_relationship(uuid)',
  'public.my_relationships(uuid)'
]) as f;
select ok(has_function_privilege('anon', 'public.relationship_counts(uuid)', 'execute'),
  'anon can execute public.relationship_counts(uuid)');
select ok(not has_function_privilege('public', f, 'execute'), 'public cannot execute ' || f)
from unnest(array[
  'public.request_relationship(uuid, uuid, public.relationship_type)',
  'public.respond_to_connection(uuid, boolean)', 'public.remove_relationship(uuid)',
  'public.my_relationships(uuid)', 'public.relationship_counts(uuid)'
]) as f;
select is(pg_catalog.pg_get_function_result('public.relationship_counts(uuid)'::regprocedure),
  'TABLE(connections bigint, followers bigint)',
  'relationship_counts returns two counts and no profile id, handle or name (Req 8.24)');

-- ---------------------------------------------------------------------------------------------
-- As Fay: requests, duplicates, and a requester who cannot respond.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Fay');
select is(auth.uid(), '05060606-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Fay');

select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000002',
                    '05c00000-0000-4000-8000-000000000003', 'connection') $$,
  'PT403', 'acting.not_allowed', 'Fay cannot send a request as Gus');
select ok(set_config('test.r_p1', public.request_relationship('05c00000-0000-4000-8000-000000000001',
            '05c00000-0000-4000-8000-000000000002', 'connection')::text, true) is not null,
  'Fay requests a connection to Gus');
select ok(set_config('test.r_p3', public.request_relationship('05c00000-0000-4000-8000-000000000001',
            '05c00000-0000-4000-8000-000000000003', 'connection')::text, true) is not null,
  'Fay requests a connection to Hal');
select ok(set_config('test.r_f1', public.request_relationship('05c00000-0000-4000-8000-000000000001',
            '05c00000-0000-4000-8000-000000000011', 'follow')::text, true) is not null,
  'Fay follows ivy_bakery_rpc');
select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000001',
                    '05c00000-0000-4000-8000-000000000002', 'connection') $$,
  'PT409', 'relationship.exists', 'a repeated request through the RPC is rejected');
select throws_ok($$ select public.respond_to_connection(current_setting('test.r_p1')::uuid, true) $$,
  'PT404', 'relationship.not_found', 'the requester cannot accept her own request');
select throws_ok($$ select public.respond_to_connection(current_setting('test.r_p1')::uuid, false) $$,
  'PT404', 'relationship.not_found', 'the requester cannot decline her own request');
select throws_ok($$ select * from public.my_relationships('05c00000-0000-4000-8000-000000000002') $$,
  'PT403', 'acting.not_allowed', 'Fay cannot list Gus''s relationships (Req 8.23)');
select throws_ok($$ select public.remove_relationship('05c00000-0000-4000-8000-0000000000ff') $$,
  'PT404', 'relationship.not_found', 'removing a missing relationship is not found');

-- ---------------------------------------------------------------------------------------------
-- As Gus: the target accepts (Req 8.4) and lists his relationships.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Gus claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Gus');
select is(auth.uid(), '05060606-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Gus');

select lives_ok($$ select public.respond_to_connection(current_setting('test.r_p1')::uuid, true) $$,
  'Gus, the target, accepts Fay''s request');
select throws_ok($$ select public.respond_to_connection(current_setting('test.r_p1')::uuid, false) $$,
  'PT422', 'relationship.bad_transition', 'an accepted connection cannot be answered again');
select ok(set_config('test.r_p2', public.request_relationship('05c00000-0000-4000-8000-000000000002',
            '05c00000-0000-4000-8000-000000000003', 'connection')::text, true) is not null,
  'Gus requests a connection to Hal');
select ok(set_config('test.r_f2', public.request_relationship('05c00000-0000-4000-8000-000000000002',
            '05c00000-0000-4000-8000-000000000011', 'follow')::text, true) is not null,
  'Gus follows ivy_bakery_rpc');
select set_eq($$ select relationship_id, type::text, direction, status::text, other_profile_id,
                        other_handle, other_display_name, other_type::text
                 from public.my_relationships('05c00000-0000-4000-8000-000000000002') $$,
  $$ values
     (current_setting('test.r_p1')::uuid, 'connection', 'incoming', 'accepted',
      '05c00000-0000-4000-8000-000000000001'::uuid, 'fay_rpc', 'Fay', 'person'),
     (current_setting('test.r_p2')::uuid, 'connection', 'outgoing', 'pending',
      '05c00000-0000-4000-8000-000000000003'::uuid, 'hal_rpc', 'Hal', 'person'),
     (current_setting('test.r_f2')::uuid, 'follow', 'outgoing', 'accepted',
      '05c00000-0000-4000-8000-000000000011'::uuid, 'ivy_bakery_rpc', 'Ivy''s Bakery', 'business') $$,
  'my_relationships lists exactly Gus''s relationships with direction and the other profile');

-- ---------------------------------------------------------------------------------------------
-- As Hal: the target declines (Req 8.5), accepts, reads counts, removes an accepted connection
-- as its target (Req 8.13).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Hal claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Hal');
select is(auth.uid(), '05060606-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Hal');

select lives_ok($$ select public.respond_to_connection(current_setting('test.r_p3')::uuid, false) $$,
  'Hal, the target, declines Fay''s request');
select lives_ok($$ select public.respond_to_connection(current_setting('test.r_p2')::uuid, true) $$,
  'Hal, the target, accepts Gus''s request');
select results_eq($$ select direction, status::text from public.my_relationships('05c00000-0000-4000-8000-000000000003')
                     where relationship_id = current_setting('test.r_p3')::uuid $$,
  $$ values ('incoming', 'declined') $$,
  'the target of a decline sees it as declined');
select results_eq($$ select connections, followers from public.relationship_counts('05c00000-0000-4000-8000-000000000002') $$,
  $$ values (2::bigint, 0::bigint) $$, 'Gus has two accepted connections and no followers');
select results_eq($$ select connections, followers from public.relationship_counts('05c00000-0000-4000-8000-000000000011') $$,
  $$ values (0::bigint, 2::bigint) $$, 'ivy_bakery_rpc has two followers');
select results_eq($$ select connections, followers from public.relationship_counts('05c00000-0000-4000-8000-000000000003') $$,
  $$ values (1::bigint, 0::bigint) $$, 'a declined connection is not counted');
select lives_ok($$ select public.remove_relationship(current_setting('test.r_p2')::uuid) $$,
  'the target of an accepted connection can remove it');
select is_empty($$ select 1 from public.my_relationships('05c00000-0000-4000-8000-000000000003')
                   where relationship_id = current_setting('test.r_p2')::uuid $$,
  'the removed connection is gone');

-- ---------------------------------------------------------------------------------------------
-- As Fay: the declined request reads as pending (Req 8.19), a re-ask is rejected with the same
-- PT409 (Req 8.16), and the requester removes an accepted connection (Req 8.13).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Fay again');
select is(auth.uid(), '05060606-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Fay again');

select results_eq($$ select direction, status::text from public.my_relationships('05c00000-0000-4000-8000-000000000001')
                     where relationship_id = current_setting('test.r_p3')::uuid $$,
  $$ values ('outgoing', 'pending') $$,
  'the requester of a declined connection reads it as pending');
select is_empty($$ select 1 from public.my_relationships('05c00000-0000-4000-8000-000000000001')
                   where status = 'declined' $$,
  'Fay never reads a declined status');
select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000001',
                    '05c00000-0000-4000-8000-000000000003', 'connection') $$,
  'PT409', 'relationship.exists', 'a re-ask after a decline gives the same error as a pending duplicate');
select throws_ok($$ select public.respond_to_connection(current_setting('test.r_p3')::uuid, true) $$,
  'PT404', 'relationship.not_found', 'the requester cannot answer her declined request');
select lives_ok($$ select public.remove_relationship(current_setting('test.r_p1')::uuid) $$,
  'the requester of an accepted connection can remove it');

-- ---------------------------------------------------------------------------------------------
-- As Hal: the former target re-asks and replaces the declined row (Req 8.18).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Hal claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Hal again');
select is(auth.uid(), '05060606-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Hal again');

select ok(set_config('test.r_p3b', public.request_relationship('05c00000-0000-4000-8000-000000000003',
            '05c00000-0000-4000-8000-000000000001', 'connection')::text, true) is not null,
  'Hal, the former target, asks Fay');
select results_eq($$ select direction, status::text from public.my_relationships('05c00000-0000-4000-8000-000000000003')
                     where other_profile_id = '05c00000-0000-4000-8000-000000000001' $$,
  $$ values ('outgoing', 'pending') $$,
  'one pending request from Hal replaces the declined row');
select isnt(current_setting('test.r_p3b'), current_setting('test.r_p3'),
  'the replacement is a new relationship');

-- ---------------------------------------------------------------------------------------------
-- As Ivy: a business cannot ask a person through the RPC; Ivy asks Fay; a followed business
-- cannot remove its follower's follow.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ivy claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Ivy');
select is(auth.uid(), '05060606-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Ivy');

select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000011',
                    '05c00000-0000-4000-8000-000000000001', 'connection') $$,
  'PT422', 'relationship.business_to_person', 'acting as her business, Ivy cannot ask a person');
select ok(set_config('test.r_p4', public.request_relationship('05c00000-0000-4000-8000-000000000004',
            '05c00000-0000-4000-8000-000000000001', 'connection')::text, true) is not null,
  'Ivy requests a connection to Fay');
select throws_ok($$ select public.remove_relationship(current_setting('test.r_f1')::uuid) $$,
  'PT404', 'relationship.not_found', 'the followed business cannot remove a follow');

-- ---------------------------------------------------------------------------------------------
-- As Fay: decline Ivy, try to remove a pending request she received, unfollow (Req 8.14).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims a third time');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Fay a third time');
select is(auth.uid(), '05060606-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Fay a third time');

select lives_ok($$ select public.respond_to_connection(current_setting('test.r_p4')::uuid, false) $$,
  'Fay declines Ivy''s request');
select throws_ok($$ select public.remove_relationship(current_setting('test.r_p3b')::uuid) $$,
  'PT404', 'relationship.not_found', 'the target cannot remove a pending request');
select lives_ok($$ select public.remove_relationship(current_setting('test.r_f1')::uuid) $$,
  'the follower can unfollow');

-- ---------------------------------------------------------------------------------------------
-- As Ivy: the declined requester cannot ask again.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ivy claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Ivy again');
select is(auth.uid(), '05060606-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Ivy again');

select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000004',
                    '05c00000-0000-4000-8000-000000000001', 'connection') $$,
  'PT409', 'relationship.exists', 'Ivy cannot ask Fay again after the decline');

-- ---------------------------------------------------------------------------------------------
-- As Fay: the target deletes the decline (Req 8.17).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims a fourth time');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Fay a fourth time');
select is(auth.uid(), '05060606-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Fay a fourth time');

select lives_ok($$ select public.remove_relationship(current_setting('test.r_p4')::uuid) $$,
  'the target of a declined connection can delete it');

-- ---------------------------------------------------------------------------------------------
-- As Ivy: after the target deleted the decline, a new request works (Req 8.17).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ivy claims a third time');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Ivy a third time');
select is(auth.uid(), '05060606-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Ivy a third time');

select ok(set_config('test.r_p4b', public.request_relationship('05c00000-0000-4000-8000-000000000004',
            '05c00000-0000-4000-8000-000000000001', 'connection')::text, true) is not null,
  'Ivy can ask Fay again once Fay deleted the decline');
select results_eq($$ select direction, status::text from public.my_relationships('05c00000-0000-4000-8000-000000000004')
                     where other_profile_id = '05c00000-0000-4000-8000-000000000001' $$,
  $$ values ('outgoing', 'pending') $$,
  'the new request is pending');

-- ---------------------------------------------------------------------------------------------
-- As Jo: a stranger cannot remove someone else's follow; a requester withdraws a pending
-- request (Req 8.15).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000005', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Jo claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Jo');
select is(auth.uid(), '05060606-0000-4000-8000-000000000005'::uuid, 'auth.uid() is Jo');

select throws_ok($$ select public.remove_relationship(current_setting('test.r_f2')::uuid) $$,
  'PT404', 'relationship.not_found', 'a stranger cannot remove a relationship');
select ok(set_config('test.r_p6', public.request_relationship('05c00000-0000-4000-8000-000000000005',
            '05c00000-0000-4000-8000-000000000002', 'connection')::text, true) is not null,
  'Jo requests a connection to Gus');
select ok(set_config('test.r_p7', public.request_relationship('05c00000-0000-4000-8000-000000000005',
            '05c00000-0000-4000-8000-000000000003', 'connection')::text, true) is not null,
  'Jo requests a connection to Hal');
select lives_ok($$ select public.remove_relationship(current_setting('test.r_p7')::uuid) $$,
  'the requester can withdraw a pending request');

-- ---------------------------------------------------------------------------------------------
-- As Gus: decline Jo.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Gus claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Gus again');
select is(auth.uid(), '05060606-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Gus again');

select lives_ok($$ select public.respond_to_connection(current_setting('test.r_p6')::uuid, false) $$,
  'Gus declines Jo''s request');

-- ---------------------------------------------------------------------------------------------
-- As Jo: the decline reads as pending, and the requester withdraws it (Req 8.15, 8.19).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '05060606-0000-4000-8000-000000000005', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Jo claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated for Jo again');
select is(auth.uid(), '05060606-0000-4000-8000-000000000005'::uuid, 'auth.uid() is Jo again');

select results_eq($$ select status::text from public.my_relationships('05c00000-0000-4000-8000-000000000005')
                     where relationship_id = current_setting('test.r_p6')::uuid $$,
  $$ values ('pending') $$,
  'Jo reads Gus''s decline as pending');
select lives_ok($$ select public.remove_relationship(current_setting('test.r_p6')::uuid) $$,
  'the requester can withdraw a declined request');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: counts only, and no other relationship RPC (Req 8.24, 22.4).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims in the RPC section');
set local role anon;
select is(current_user::text, 'anon', 'running as anon in the RPC section');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon in the RPC section');

select results_eq($$ select connections, followers from public.relationship_counts('05c00000-0000-4000-8000-000000000011') $$,
  $$ values (0::bigint, 1::bigint) $$, 'anon reads the bakery counts after Fay unfollowed');
select results_eq($$ select connections, followers from public.relationship_counts('05c00000-0000-4000-8000-000000000002') $$,
  $$ values (0::bigint, 0::bigint) $$, 'anon reads Gus''s counts after every connection was removed');
select throws_ok($$ select public.request_relationship('05c00000-0000-4000-8000-000000000001',
                    '05c00000-0000-4000-8000-000000000002', 'connection') $$,
  '42501', null, 'anon cannot call request_relationship');
select throws_ok($$ select * from public.my_relationships('05c00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot call my_relationships');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- What the RPCs left behind, read as the test owner.
select set_eq($$ select requester_profile_id, target_profile_id, type::text, status::text
                 from public.relationships where requester_profile_id::text like '05c00000-%' $$,
  $$ values
     ('05c00000-0000-4000-8000-000000000003'::uuid, '05c00000-0000-4000-8000-000000000001'::uuid, 'connection', 'pending'),
     ('05c00000-0000-4000-8000-000000000004'::uuid, '05c00000-0000-4000-8000-000000000001'::uuid, 'connection', 'pending'),
     ('05c00000-0000-4000-8000-000000000002'::uuid, '05c00000-0000-4000-8000-000000000011'::uuid, 'follow', 'accepted') $$,
  'only the expected relationships remain after the RPC sequence');

select * from finish();
rollback;
