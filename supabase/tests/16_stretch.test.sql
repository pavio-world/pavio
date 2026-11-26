-- Stretch tables: groups and group members (Spec 00, Req 19.1 to 19.3, 19.7, 22.1 to 22.3, 22.5,
-- 25.1, 25.2; DR-1, DR-4).
-- The chat tables (migration 22) follow the groups part. Later tasks add their sections before
-- finish() and raise the plan.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(304);

-- =============================================================================================
-- Groups (migration 11)
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Gia, Hal and Ivy are people. Gia owns the business gia_biz_s.
-- Gia owns group g1 (linked to her circle "book club") and gia_biz_s owns group g2.
-- Hal owns group g3 (linked to his circle "hal crew"). Hal is a member of g1. Ivy is in nothing.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('16161616-0000-4000-8000-000000000001', 'gia.stretch@example.invalid'),
  ('16161616-0000-4000-8000-000000000002', 'hal.stretch@example.invalid'),
  ('16161616-0000-4000-8000-000000000003', 'ivy.stretch@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('16b00000-0000-4000-8000-000000000001', 'person', '16161616-0000-4000-8000-000000000001', 'gia_s', 'Gia'),
  ('16b00000-0000-4000-8000-000000000002', 'person', '16161616-0000-4000-8000-000000000002', 'hal_s', 'Hal'),
  ('16b00000-0000-4000-8000-000000000003', 'person', '16161616-0000-4000-8000-000000000003', 'ivy_s', 'Ivy');
insert into public.profiles (id, type, handle, display_name) values
  ('16b00000-0000-4000-8000-000000000011', 'business', 'gia_biz_s', 'Gia''s Bakery');
insert into public.profile_managers (profile_id, user_id, role) values
  ('16b00000-0000-4000-8000-000000000011', '16161616-0000-4000-8000-000000000001', 'owner');
insert into public.circles (id, owner_profile_id, private_name) values
  ('16c00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000001', 'book club'),
  ('16c00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000002', 'hal crew'),
  ('16c00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000001', 'spare circle');
insert into public.groups (id, owner_profile_id, name, circle_id) values
  ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000001', 'Readers',
   '16c00000-0000-4000-8000-000000000001'),
  ('16d00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000011', 'Bakery fans', null),
  ('16d00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000002', 'Hal''s crew',
   '16c00000-0000-4000-8000-000000000002');
insert into public.group_members (group_id, profile_id) values
  ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000002');

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, keys, checks, indexes, triggers (Req 19.1, 19.3).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'groups', 'groups exists');
select has_table('public', 'group_members', 'group_members exists');
select columns_are('public', 'groups', array['id', 'owner_profile_id', 'name', 'circle_id', 'created_at', 'updated_at'],
  'groups has exactly its six columns');
select columns_are('public', 'group_members', array['id', 'group_id', 'profile_id', 'created_at'],
  'group_members has exactly its four columns');
select col_is_pk('public', 'groups', 'id', 'groups.id is the primary key');
select col_is_pk('public', 'group_members', 'id', 'group_members.id is the primary key');
select col_is_null('public', 'groups', 'circle_id', 'the linked circle is optional');
select ok(exists (select 1 from pg_catalog.pg_constraint
                  where conrelid = 'public.groups'::regclass and contype = 'c' and conname = 'groups_name_length'),
  'groups has the check groups_name_length');
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = v.t::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = v.t::regclass and attname = v.c)]::smallint[]),
  v.action, v.t || '.' || v.c || ' has delete action ' || v.action)
from (values ('public.groups', 'owner_profile_id', 'c'),
             ('public.groups', 'circle_id', 'n'),
             ('public.group_members', 'group_id', 'c'),
             ('public.group_members', 'profile_id', 'c')) as v(t, c, action);
select col_is_unique('public', 'group_members', array['group_id', 'profile_id'],
  'one membership per group and profile (Req 19.3)');
select has_index('public', v.t, v.i, v.c, v.t || ' has the index ' || v.i)
from (values ('groups', 'groups_owner_profile_id_idx', 'owner_profile_id'),
             ('groups', 'groups_circle_id_idx', 'circle_id'),
             ('group_members', 'group_members_profile_id_idx', 'profile_id')) as v(t, i, c);
select trigger_is('public', 'groups', v.trg, 'private', v.fn, v.trg || ' calls private.' || v.fn)
from (values ('groups_guard', 'groups_guard'),
             ('groups_set_updated_at', 'set_updated_at')) as v(trg, fn);

-- ---------------------------------------------------------------------------------------------
-- RLS, policies and grants (Req 19.2, 19.7, 22.1 to 22.3, 22.5).
-- ---------------------------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = t::regclass), 'RLS is enabled on ' || t)
from unnest(array['public.groups', 'public.group_members']) as t;
select policies_are('public', 'groups', array[
  'groups_authenticated_select', 'groups_authenticated_insert',
  'groups_authenticated_update', 'groups_authenticated_delete'
], 'groups has exactly its four policies');
select policies_are('public', 'group_members', array[
  'group_members_authenticated_select', 'group_members_authenticated_insert',
  'group_members_authenticated_delete'
], 'group_members has exactly its three policies');
select is((select count(*)::int from pg_policies
           where schemaname = 'public' and tablename in ('groups', 'group_members')
             and roles <> array['authenticated']::name[]),
  0, 'every group policy applies to authenticated only');
select table_privs_are('public', t, 'anon', array[]::text[], 'anon has no privilege on ' || t)
from unnest(array['groups', 'group_members']) as t;
select ok(not has_any_column_privilege('anon', t, p), 'anon has no column ' || p || ' on ' || t)
from unnest(array['public.groups', 'public.group_members']) as t
cross join unnest(array['SELECT', 'INSERT', 'UPDATE']) as p;
select table_privs_are('public', 'groups', 'authenticated', array['DELETE'],
  'authenticated may only delete groups at table level; the rest is per column');
select table_privs_are('public', 'group_members', 'authenticated', array['SELECT', 'INSERT', 'DELETE'],
  'authenticated may select, insert and delete group members');
select ok(has_column_privilege('authenticated', 'public.groups', c, 'SELECT'),
  'authenticated may select groups.' || c)
from unnest(array['id', 'owner_profile_id', 'name', 'created_at', 'updated_at']) as c;
select ok(not has_column_privilege('authenticated', 'public.groups', 'circle_id', 'SELECT'),
  'authenticated may not select groups.circle_id (Req 19.2)');
select ok(has_column_privilege('authenticated', 'public.groups', c, p),
  'authenticated may ' || p || ' groups.' || c)
from unnest(array['owner_profile_id', 'name', 'circle_id']) as c
cross join unnest(array['INSERT', 'UPDATE']) as p;

-- Functions: definer, empty search_path, execute exactly as the grants table says (DR-4).
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array['public.in_group(uuid)', 'public.group_linked_circle(uuid)', 'private.groups_guard()']) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array['public.in_group(uuid)', 'public.group_linked_circle(uuid)', 'private.groups_guard()']) as f;
select volatility_is('public', f, array['uuid'], 'stable', 'public.' || f || ' is stable')
from unnest(array['in_group', 'group_linked_circle']) as f;
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array['public.in_group(uuid)', 'public.group_linked_circle(uuid)']) as f
cross join unnest(array['public', 'anon']) as r;
select ok(has_function_privilege('authenticated', f, 'execute'), 'authenticated can execute ' || f)
from unnest(array['public.in_group(uuid)', 'public.group_linked_circle(uuid)']) as f;
select ok(not has_function_privilege(r, 'private.groups_guard()', 'execute'),
  r || ' cannot execute private.groups_guard()')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- ---------------------------------------------------------------------------------------------
-- Rules that bind every writer (Req 19.1, 19.3).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.groups (owner_profile_id, name)
                    values ('16b00000-0000-4000-8000-000000000001', '') $$,
  '23514', null, 'an empty group name is rejected');
select throws_ok(format($$ insert into public.groups (owner_profile_id, name)
                           values ('16b00000-0000-4000-8000-000000000001', %L) $$, repeat('a', 81)),
  '23514', null, 'an 81 character group name is rejected');
select lives_ok(format($$ insert into public.groups (owner_profile_id, name)
                          values ('16b00000-0000-4000-8000-000000000001', %L) $$, repeat('b', 80)),
  'an 80 character group name is accepted');
select throws_ok($$ insert into public.groups (owner_profile_id, name, circle_id)
                    values ('16b00000-0000-4000-8000-000000000001', 'Borrowed',
                            '16c00000-0000-4000-8000-000000000002') $$,
  'PT422', 'group.circle_not_owned', 'a group cannot link a circle of another profile (Req 19.1)');
select throws_ok($$ update public.groups set circle_id = '16c00000-0000-4000-8000-000000000002'
                    where id = '16d00000-0000-4000-8000-000000000001' $$,
  'PT422', 'group.circle_not_owned', 'a group cannot be relinked to a circle of another profile');
select throws_ok($$ insert into public.groups (owner_profile_id, name, circle_id)
                    values ('16b00000-0000-4000-8000-000000000011', 'Owner''s circle',
                            '16c00000-0000-4000-8000-000000000001') $$,
  'PT422', 'group.circle_not_owned', 'a business group cannot link a circle of the person who manages it');
select throws_ok($$ update public.groups set owner_profile_id = '16b00000-0000-4000-8000-000000000011'
                    where id = '16d00000-0000-4000-8000-000000000001' $$,
  'PT422', 'group.circle_not_owned', 'moving a linked group to another owner is rejected');
select throws_ok($$ insert into public.group_members (group_id, profile_id)
                    values ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000002') $$,
  '23505', null, 'a duplicate membership is rejected (Req 19.3)');
select ok(public.group_linked_circle('16d00000-0000-4000-8000-000000000001') is null,
  'with no claims, nobody acts as the owner, so the linked circle is hidden');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Gia, the owner of g1 and of gia_biz_s, in the canary order (DR-1).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Gia claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Gia');

select set_eq(
  $$ select name from public.groups $$,
  $$ values ('Bakery fans'::text), ('Readers'::text), (repeat('b', 80)) $$,
  'Gia reads the groups of the profiles she acts as, and not Hal''s');
select throws_ok($$ select circle_id from public.groups $$,
  '42501', null, 'groups.circle_id cannot be read from the table, even by the owner (Req 19.2)');
select is(public.group_linked_circle('16d00000-0000-4000-8000-000000000001'),
  '16c00000-0000-4000-8000-000000000001'::uuid, 'the owner reads the linked circle through group_linked_circle');
select ok(public.group_linked_circle('16d00000-0000-4000-8000-000000000003') is null,
  'Gia cannot read the linked circle of Hal''s group');
select is((select count(*)::int from public.group_members where group_id = '16d00000-0000-4000-8000-000000000001'),
  1, 'the owner reads the members of her group');
select ok(not public.in_group('16d00000-0000-4000-8000-000000000001'),
  'owning a group does not make Gia a member of it');
select lives_ok($$ insert into public.groups (owner_profile_id, name, circle_id)
                   values ('16b00000-0000-4000-8000-000000000001', 'Spare readers',
                           '16c00000-0000-4000-8000-000000000003') $$,
  'Gia can create a group linked to her own circle');
select lives_ok($$ insert into public.groups (owner_profile_id, name)
                   values ('16b00000-0000-4000-8000-000000000011', 'Wholesale') $$,
  'Gia can create a group for the business she acts as');
select throws_ok($$ insert into public.groups (owner_profile_id, name)
                    values ('16b00000-0000-4000-8000-000000000002', 'Planted') $$,
  '42501', null, 'Gia cannot create a group for Hal');
select throws_ok($$ insert into public.groups (owner_profile_id, name, circle_id)
                    values ('16b00000-0000-4000-8000-000000000001', 'Borrowed',
                            '16c00000-0000-4000-8000-000000000002') $$,
  'PT422', 'group.circle_not_owned', 'the linked circle guard also binds the API');
select lives_ok($$ update public.groups set name = 'Book readers'
                   where id = '16d00000-0000-4000-8000-000000000001' $$,
  'Gia can rename her group');
select lives_ok($$ insert into public.group_members (group_id, profile_id)
                   values ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000003') $$,
  'Gia can add a member to her group');
select lives_ok($$ delete from public.group_members
                   where group_id = '16d00000-0000-4000-8000-000000000001'
                     and profile_id = '16b00000-0000-4000-8000-000000000003' $$,
  'Gia can remove a member from her group');
select throws_ok($$ insert into public.group_members (group_id, profile_id)
                    values ('16d00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'Gia cannot add members to Hal''s group');
select lives_ok($$ update public.groups set name = 'Hijacked' where id = '16d00000-0000-4000-8000-000000000003' $$,
  'an update of Hal''s group by Gia runs but touches nothing');
select lives_ok($$ delete from public.groups where id = '16d00000-0000-4000-8000-000000000003' $$,
  'a delete of Hal''s group by Gia runs but touches nothing');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Hal, owner of g3 and a member of g1 (Req 19.2, 19.7).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Hal claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Hal');

select set_eq(
  $$ select name from public.groups $$,
  $$ values ('Book readers'::text), ('Hal''s crew'::text) $$,
  'Hal reads his own group and the group he is a member of, and nothing else');
select ok(public.in_group('16d00000-0000-4000-8000-000000000001'), 'in_group is true for Hal in g1');
select ok(public.group_linked_circle('16d00000-0000-4000-8000-000000000001') is null,
  'a member cannot read the linked circle of the group (Req 19.2)');
select is(public.group_linked_circle('16d00000-0000-4000-8000-000000000003'),
  '16c00000-0000-4000-8000-000000000002'::uuid, 'Hal reads the linked circle of his own group');
select is((select count(*)::int from public.group_members where group_id = '16d00000-0000-4000-8000-000000000001'),
  1, 'a member reads the members of his group');
select throws_ok($$ insert into public.group_members (group_id, profile_id)
                    values ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000003') $$,
  '42501', null, 'a member cannot add members to the group');
select lives_ok($$ update public.groups set name = 'Taken over' where id = '16d00000-0000-4000-8000-000000000001' $$,
  'an update of g1 by its member runs but touches nothing');
select lives_ok($$ delete from public.group_members where group_id = '16d00000-0000-4000-8000-000000000001' $$,
  'a delete of g1 memberships by its member runs but touches nothing');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ivy, who owns nothing and is in no group.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ivy claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Ivy');

select is_empty($$ select 1 from public.groups $$, 'a stranger reads no group');
select is_empty($$ select 1 from public.group_members $$, 'a stranger reads no group member');
select ok(not public.in_group('16d00000-0000-4000-8000-000000000001'), 'in_group is false for a stranger');
select ok(public.group_linked_circle('16d00000-0000-4000-8000-000000000001') is null,
  'a stranger cannot read the linked circle');
select throws_ok($$ insert into public.groups (owner_profile_id, name)
                    values ('16b00000-0000-4000-8000-000000000001', 'Not mine') $$,
  '42501', null, 'a stranger cannot create a group for the owner');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read, no write and no function (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.groups $$, '42501', null, 'anon cannot read groups');
select throws_ok($$ select 1 from public.group_members $$, '42501', null, 'anon cannot read group members');
select throws_ok($$ insert into public.groups (owner_profile_id, name)
                    values ('16b00000-0000-4000-8000-000000000001', 'Anon group') $$,
  '42501', null, 'anon cannot insert a group');
select throws_ok($$ insert into public.group_members (group_id, profile_id)
                    values ('16d00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000003') $$,
  '42501', null, 'anon cannot insert a group member');
select throws_ok($$ select public.in_group('16d00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot call in_group');
select throws_ok($$ select public.group_linked_circle('16d00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot call group_linked_circle');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- What the API calls did and did not change.
select is((select name from public.groups where id = '16d00000-0000-4000-8000-000000000003'),
  'Hal''s crew', 'Hal''s group is untouched by Gia''s update and delete');
select is((select name from public.groups where id = '16d00000-0000-4000-8000-000000000001'),
  'Book readers', 'g1 carries the owner''s rename and not the member''s');
select results_eq(
  $$ select profile_id from public.group_members where group_id = '16d00000-0000-4000-8000-000000000001' $$,
  $$ values ('16b00000-0000-4000-8000-000000000002'::uuid) $$,
  'g1 still has exactly Hal as its member');

-- Cascades: a deleted circle unlinks, a deleted group takes its members.
delete from public.circles where id = '16c00000-0000-4000-8000-000000000002';
select ok((select circle_id from public.groups where id = '16d00000-0000-4000-8000-000000000003') is null,
  'deleting the linked circle leaves the group with no linked circle');
delete from public.groups where id = '16d00000-0000-4000-8000-000000000001';
select is_empty($$ select 1 from public.group_members where group_id = '16d00000-0000-4000-8000-000000000001' $$,
  'deleting a group deletes its memberships');

-- =============================================================================================
-- Chat (migration 22): conversations, conversation_members, messages, message_translations
-- (Spec 00 Req 5.8, 19.4 to 19.8, 22.1 to 22.3, 22.5, 25.1, 25.2; DR-1, DR-4)
-- =============================================================================================

-- Req 19.8: no write path exists yet, so before this file adds fixtures the four tables are empty.
set local role postgres;
select is_empty($$ select 1 from public.conversations $$, 'conversations is empty before fixtures (Req 19.8)');
select is_empty($$ select 1 from public.conversation_members $$, 'conversation_members is empty before fixtures (Req 19.8)');
select is_empty($$ select 1 from public.messages $$, 'messages is empty before fixtures (Req 19.8)');
select is_empty($$ select 1 from public.message_translations $$, 'message_translations is empty before fixtures (Req 19.8)');

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Jo, Kim, Lee, Mo and Zed are people. Jo manages the business jo_biz_c.
-- c1: Jo and Kim. c2: Kim and Lee. c3: jo_biz_c and Kim (Jo reaches it only by managing the
-- business). c4: Kim and Zed. Mo is in nothing.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('16161616-0000-4000-8000-000000000021', 'jo.chat@example.invalid'),
  ('16161616-0000-4000-8000-000000000022', 'kim.chat@example.invalid'),
  ('16161616-0000-4000-8000-000000000023', 'lee.chat@example.invalid'),
  ('16161616-0000-4000-8000-000000000024', 'mo.chat@example.invalid'),
  ('16161616-0000-4000-8000-000000000025', 'zed.chat@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('16b00000-0000-4000-8000-000000000021', 'person', '16161616-0000-4000-8000-000000000021', 'jo_c', 'Jo'),
  ('16b00000-0000-4000-8000-000000000022', 'person', '16161616-0000-4000-8000-000000000022', 'kim_c', 'Kim'),
  ('16b00000-0000-4000-8000-000000000023', 'person', '16161616-0000-4000-8000-000000000023', 'lee_c', 'Lee'),
  ('16b00000-0000-4000-8000-000000000024', 'person', '16161616-0000-4000-8000-000000000024', 'mo_c', 'Mo'),
  ('16b00000-0000-4000-8000-000000000025', 'person', '16161616-0000-4000-8000-000000000025', 'zed_c', 'Zed');
insert into public.profiles (id, type, handle, display_name) values
  ('16b00000-0000-4000-8000-000000000031', 'business', 'jo_biz_c', 'Jo''s Studio');
insert into public.profile_managers (profile_id, user_id, role) values
  ('16b00000-0000-4000-8000-000000000031', '16161616-0000-4000-8000-000000000021', 'owner');
insert into public.conversations (id) values
  ('16e00000-0000-4000-8000-000000000001'),
  ('16e00000-0000-4000-8000-000000000002'),
  ('16e00000-0000-4000-8000-000000000003'),
  ('16e00000-0000-4000-8000-000000000004');
insert into public.conversation_members (conversation_id, profile_id) values
  ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021'),
  ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000022'),
  ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000022'),
  ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000023'),
  ('16e00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000031'),
  ('16e00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000022'),
  ('16e00000-0000-4000-8000-000000000004', '16b00000-0000-4000-8000-000000000022'),
  ('16e00000-0000-4000-8000-000000000004', '16b00000-0000-4000-8000-000000000025');
insert into public.messages (id, conversation_id, sender_profile_id, body, language_code) values
  ('16f00000-0000-4000-8000-000000000001', '16e00000-0000-4000-8000-000000000001',
   '16b00000-0000-4000-8000-000000000021', 'hello', 'en'),
  ('16f00000-0000-4000-8000-000000000002', '16e00000-0000-4000-8000-000000000001',
   '16b00000-0000-4000-8000-000000000022', 'habari', 'sw'),
  ('16f00000-0000-4000-8000-000000000003', '16e00000-0000-4000-8000-000000000002',
   '16b00000-0000-4000-8000-000000000023', 'only for c2', 'en'),
  ('16f00000-0000-4000-8000-000000000004', '16e00000-0000-4000-8000-000000000003',
   '16b00000-0000-4000-8000-000000000031', 'studio hello', 'en'),
  ('16f00000-0000-4000-8000-000000000005', '16e00000-0000-4000-8000-000000000004',
   '16b00000-0000-4000-8000-000000000025', 'from zed', 'en');
insert into public.message_translations (id, message_id, language_code, body) values
  ('16a00000-0000-4000-8000-000000000001', '16f00000-0000-4000-8000-000000000001', 'sw', 'habari yako'),
  ('16a00000-0000-4000-8000-000000000002', '16f00000-0000-4000-8000-000000000002', 'en', 'hello there'),
  ('16a00000-0000-4000-8000-000000000003', '16f00000-0000-4000-8000-000000000003', 'sw', 'kwa c2 tu');

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, keys, checks, indexes, triggers (Req 5.8, 19.4 to 19.6).
-- ---------------------------------------------------------------------------------------------
select has_table('public', t, t || ' exists')
from unnest(array['conversations', 'conversation_members', 'messages', 'message_translations']) as t;
select columns_are('public', 'conversations', array['id', 'created_at', 'updated_at'],
  'conversations has exactly its three columns');
select columns_are('public', 'conversation_members', array['id', 'conversation_id', 'profile_id', 'created_at'],
  'conversation_members has exactly its four columns');
select columns_are('public', 'messages', array['id', 'conversation_id', 'sender_profile_id', 'body',
  'language_code', 'created_at', 'updated_at'], 'messages has exactly its seven columns');
select columns_are('public', 'message_translations', array['id', 'message_id', 'language_code', 'body', 'created_at'],
  'message_translations has exactly its five columns');
select col_is_pk('public', t, 'id', t || '.id is the primary key')
from unnest(array['conversations', 'conversation_members', 'messages', 'message_translations']) as t;
select col_is_null('public', 'messages', 'sender_profile_id', 'a message may have no sender (Req 5.8)');
select col_not_null('public', 'messages', c, 'messages.' || c || ' is not null')
from unnest(array['conversation_id', 'body', 'language_code']) as c;
select col_not_null('public', 'message_translations', c, 'message_translations.' || c || ' is not null')
from unnest(array['message_id', 'language_code', 'body']) as c;
select ok(exists (select 1 from pg_catalog.pg_constraint
                  where conrelid = 'public.messages'::regclass and contype = 'c' and conname = 'messages_body_length'),
  'messages has the check messages_body_length');
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = v.t::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = v.t::regclass and attname = v.c)]::smallint[]),
  v.action, v.t || '.' || v.c || ' has delete action ' || v.action)
from (values ('public.conversation_members', 'conversation_id', 'c'),
             ('public.conversation_members', 'profile_id', 'c'),
             ('public.messages', 'conversation_id', 'c'),
             ('public.messages', 'sender_profile_id', 'n'),
             ('public.messages', 'language_code', 'a'),
             ('public.message_translations', 'message_id', 'c'),
             ('public.message_translations', 'language_code', 'a')) as v(t, c, action);
select col_is_unique('public', 'conversation_members', array['conversation_id', 'profile_id'],
  'one membership per conversation and profile');
select col_is_unique('public', 'message_translations', array['message_id', 'language_code'],
  'one translation per message and language (Req 19.6)');
select has_index('public', v.t, v.i, v.c, v.t || ' has the index ' || v.i)
from (values ('conversation_members', 'conversation_members_profile_id_idx', 'profile_id'),
             ('messages', 'messages_sender_profile_id_idx', 'sender_profile_id'),
             ('messages', 'messages_language_code_idx', 'language_code'),
             ('message_translations', 'message_translations_language_code_idx', 'language_code')) as v(t, i, c);
select has_index('public', 'messages', 'messages_conversation_id_created_at_idx',
  array['conversation_id', 'created_at'], 'messages has the listing index on conversation and time');
select trigger_is('public', v.t, v.trg, 'private', 'set_updated_at', v.trg || ' calls private.set_updated_at')
from (values ('conversations', 'conversations_set_updated_at'),
             ('messages', 'messages_set_updated_at')) as v(t, trg);

-- ---------------------------------------------------------------------------------------------
-- RLS, policies and grants (Req 19.4, 19.5, 19.7, 22.1 to 22.3, 22.5).
-- ---------------------------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = t::regclass), 'RLS is enabled on ' || t)
from unnest(array['public.conversations', 'public.conversation_members', 'public.messages',
                  'public.message_translations']) as t;
select policies_are('public', 'conversations', array['conversations_authenticated_select'],
  'conversations has exactly its select policy');
select policies_are('public', 'conversation_members', array['conversation_members_authenticated_select'],
  'conversation_members has exactly its select policy');
select policies_are('public', 'messages', array['messages_authenticated_select', 'messages_authenticated_insert'],
  'messages has exactly its select and insert policies');
select policies_are('public', 'message_translations', array['message_translations_authenticated_select'],
  'message_translations has exactly its select policy');
select is((select count(*)::int from pg_policies
           where schemaname = 'public'
             and tablename in ('conversations', 'conversation_members', 'messages', 'message_translations')
             and roles <> array['authenticated']::name[]),
  0, 'every chat policy applies to authenticated only');
select table_privs_are('public', t, 'anon', array[]::text[], 'anon has no privilege on ' || t)
from unnest(array['conversations', 'conversation_members', 'messages', 'message_translations']) as t;
select ok(not has_any_column_privilege('anon', t, p), 'anon has no column ' || p || ' on ' || t)
from unnest(array['public.conversations', 'public.conversation_members', 'public.messages',
                  'public.message_translations']) as t
cross join unnest(array['SELECT', 'INSERT', 'UPDATE']) as p;
select table_privs_are('public', t, 'authenticated', array['SELECT'], 'authenticated may only select ' || t)
from unnest(array['conversations', 'conversation_members', 'messages', 'message_translations']) as t;
select ok(has_column_privilege('authenticated', 'public.messages', c, 'INSERT'),
  'authenticated may insert messages.' || c)
from unnest(array['conversation_id', 'sender_profile_id', 'body', 'language_code']) as c;
select ok(not has_column_privilege('authenticated', 'public.messages', c, 'INSERT'),
  'authenticated may not insert messages.' || c)
from unnest(array['id', 'created_at', 'updated_at']) as c;
select ok(not has_any_column_privilege('authenticated', t, p), 'authenticated has no column ' || p || ' on ' || t)
from unnest(array['public.conversations', 'public.conversation_members', 'public.messages',
                  'public.message_translations']) as t
cross join unnest(array['UPDATE']) as p;
select ok(not has_any_column_privilege('authenticated', t, 'INSERT'), 'authenticated has no insert on ' || t)
from unnest(array['public.conversations', 'public.conversation_members',
                  'public.message_translations']) as t;

-- in_conversation: definer, empty search_path, stable, signed in only (DR-4).
select ok((select prosecdef from pg_catalog.pg_proc where oid = 'public.in_conversation(uuid)'::regprocedure),
  'public.in_conversation is security definer');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = 'public.in_conversation(uuid)'::regprocedure)) c where c = 'search_path=""'),
  'public.in_conversation sets an empty search_path');
select volatility_is('public', 'in_conversation', array['uuid'], 'stable', 'public.in_conversation is stable');
select ok(not has_function_privilege(r, 'public.in_conversation(uuid)', 'execute'),
  r || ' cannot execute public.in_conversation')
from unnest(array['public', 'anon']) as r;
select ok(has_function_privilege('authenticated', 'public.in_conversation(uuid)', 'execute'),
  'authenticated can execute public.in_conversation');

-- ---------------------------------------------------------------------------------------------
-- Rules that bind every writer (Req 5.8, 19.4, 19.6).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021', '', 'en') $$,
  '23514', null, 'an empty message body is rejected');
select throws_ok(format($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                           values ('16e00000-0000-4000-8000-000000000001',
                                   '16b00000-0000-4000-8000-000000000021', %L, 'en') $$, repeat('a', 4001)),
  '23514', null, 'a 4001 character message body is rejected');
select lives_ok(format($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                          values ('16e00000-0000-4000-8000-000000000001',
                                  '16b00000-0000-4000-8000-000000000021', %L, 'en') $$, repeat('b', 4000)),
  'a 4000 character message body is accepted');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021', 'hi', 'xx') $$,
  '23503', null, 'an unknown message language is rejected');
select throws_ok($$ insert into public.message_translations (message_id, language_code, body)
                    values ('16f00000-0000-4000-8000-000000000001', 'xx', 'nope') $$,
  '23503', null, 'an unknown translation language is rejected');
select throws_ok($$ insert into public.conversation_members (conversation_id, profile_id)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021') $$,
  '23505', null, 'a duplicate conversation membership is rejected');
select throws_ok($$ insert into public.message_translations (message_id, language_code, body)
                    values ('16f00000-0000-4000-8000-000000000001', 'sw', 'second swahili') $$,
  '23505', null, 'a second translation of one message into one language is rejected (Req 19.6)');
select lives_ok($$ insert into public.message_translations (message_id, language_code, body)
                   values ('16f00000-0000-4000-8000-000000000001', 'en', 'same language other message ok') $$,
  'one message may carry a translation in another language');
select lives_ok($$ insert into public.message_translations (message_id, language_code, body)
                   values ('16f00000-0000-4000-8000-000000000004', 'sw', 'studio in swahili') $$,
  'the same language on another message is accepted');
select lives_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                   values ('16e00000-0000-4000-8000-000000000001', null, 'system note', 'en') $$,
  'a message with no sender is accepted for the table owner (Req 5.8)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Jo: member of c1, and manager of the business that is a member of c3.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000021', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Jo claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000021'::uuid, 'auth.uid() is Jo');

select set_eq($$ select id from public.conversations $$,
  $$ values ('16e00000-0000-4000-8000-000000000001'::uuid), ('16e00000-0000-4000-8000-000000000003'::uuid) $$,
  'Jo reads her conversation and the one her business is in, and no other');
select is((select count(*)::int from public.conversation_members
           where conversation_id = '16e00000-0000-4000-8000-000000000001'),
  2, 'Jo reads both members of c1');
select is((select count(*)::int from public.conversation_members
           where conversation_id = '16e00000-0000-4000-8000-000000000003'),
  2, 'Jo reads both members of c3, through the business she manages');
select is_empty($$ select 1 from public.conversation_members
                   where conversation_id = '16e00000-0000-4000-8000-000000000002' $$,
  'Jo reads no member of c2');
select is_empty($$ select 1 from public.conversation_members
                   where conversation_id = '16e00000-0000-4000-8000-000000000004' $$,
  'Jo reads no member of c4');
select set_eq($$ select body from public.messages
                 where body in ('hello', 'habari', 'only for c2', 'studio hello', 'from zed', 'system note') $$,
  $$ values ('hello'::text), ('habari'), ('studio hello'), ('system note') $$,
  'Jo reads the messages of c1 and c3 and none of c2 or c4');
select set_eq($$ select body from public.message_translations $$,
  $$ values ('habari yako'::text), ('hello there'), ('same language other message ok'), ('studio in swahili') $$,
  'Jo reads the translations of the messages she can read, and not the c2 translation');
select ok(public.in_conversation('16e00000-0000-4000-8000-000000000001'), 'in_conversation is true for Jo in c1');
select ok(public.in_conversation('16e00000-0000-4000-8000-000000000003'),
  'in_conversation is true in c3, through the managed business');
select ok(not public.in_conversation('16e00000-0000-4000-8000-000000000002'), 'in_conversation is false for Jo in c2');

-- Message insert needs acts_as on the sender and membership of that sender (Req 19.5).
select lives_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                   values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021',
                           'jo says hi', 'en') $$,
  'Jo can send as herself in a conversation she is in');
select lives_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                   values ('16e00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000031',
                           'studio says hi', 'sw') $$,
  'Jo can send as the business she manages, which is a member of c3');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000022',
                            'forged as kim', 'en') $$,
  '42501', null, 'Jo cannot send as Kim, whom she does not act as');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000021',
                            'jo in c2', 'en') $$,
  '42501', null, 'Jo cannot send into a conversation she is not a member of');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000003', '16b00000-0000-4000-8000-000000000021',
                            'jo in c3', 'en') $$,
  '42501', null, 'Jo as a person cannot send into c3, where only her business is a member');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000031',
                            'biz in c1', 'en') $$,
  '42501', null, 'Jo as the business cannot send into c1, where only her person profile is a member');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', null, 'no sender', 'en') $$,
  '42501', null, 'an API caller cannot send a message with no sender');
select throws_ok($$ insert into public.messages (id, conversation_id, sender_profile_id, body, language_code)
                    values ('16f00000-0000-4000-8000-0000000000ff', '16e00000-0000-4000-8000-000000000001',
                            '16b00000-0000-4000-8000-000000000021', 'chosen id', 'en') $$,
  '42501', null, 'an API caller cannot choose the message id');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code, created_at)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021',
                            'back dated', 'en', now() - interval '1 day') $$,
  '42501', null, 'an API caller cannot back date a message');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021', '', 'en') $$,
  '23514', null, 'the body check also binds the API');

-- No other write path (Req 19.8).
select throws_ok($$ insert into public.conversations default values $$,
  '42501', null, 'an API caller cannot create a conversation');
select throws_ok($$ insert into public.conversation_members (conversation_id, profile_id)
                    values ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000021') $$,
  '42501', null, 'an API caller cannot add a member to a conversation');
select throws_ok($$ insert into public.message_translations (message_id, language_code, body)
                    values ('16f00000-0000-4000-8000-000000000002', 'sw', 'planted') $$,
  '42501', null, 'an API caller cannot write a translation');
select throws_ok($$ update public.messages set body = 'edited' where body = 'hello' $$,
  '42501', null, 'an API caller cannot edit a message');
select throws_ok($$ delete from public.messages where body = 'hello' $$,
  '42501', null, 'an API caller cannot delete a message');
select throws_ok($$ update public.conversations set updated_at = now() $$,
  '42501', null, 'an API caller cannot update a conversation');
select throws_ok($$ delete from public.conversation_members where conversation_id = '16e00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'an API caller cannot remove a conversation member');
select throws_ok($$ delete from public.message_translations $$,
  '42501', null, 'an API caller cannot delete a translation');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Kim, who is a member of all four conversations.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000022', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Kim claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000022'::uuid, 'auth.uid() is Kim');

select is((select count(*)::int from public.conversations), 4, 'Kim reads the four conversations she is in');
select is((select count(*)::int from public.conversation_members), 8, 'Kim reads all eight memberships');
select is((select count(*)::int from public.message_translations), 5, 'Kim reads every translation');
select lives_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                   values ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000022',
                           'kim says hi', 'en') $$,
  'Kim can send into c2');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000002', '16b00000-0000-4000-8000-000000000023',
                            'forged as lee', 'en') $$,
  '42501', null, 'Kim cannot send as Lee, even in a conversation Lee is in');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Lee: a member of c2 only.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000023', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Lee claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000023'::uuid, 'auth.uid() is Lee');

select set_eq($$ select id from public.conversations $$,
  $$ values ('16e00000-0000-4000-8000-000000000002'::uuid) $$, 'Lee reads c2 and nothing else');
select set_eq($$ select body from public.messages $$,
  $$ values ('only for c2'::text), ('kim says hi') $$, 'Lee reads the messages of c2 only');
select set_eq($$ select body from public.message_translations $$,
  $$ values ('kwa c2 tu'::text) $$, 'Lee reads the translation of the c2 message only');
select is((select count(*)::int from public.conversation_members), 2, 'Lee reads the two members of c2 only');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000023',
                            'lee in c1', 'en') $$,
  '42501', null, 'Lee cannot send into c1');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Mo, who is in no conversation.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '16161616-0000-4000-8000-000000000024', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Mo claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '16161616-0000-4000-8000-000000000024'::uuid, 'auth.uid() is Mo');

select is_empty($$ select 1 from public.conversations $$, 'a stranger reads no conversation');
select is_empty($$ select 1 from public.conversation_members $$, 'a stranger reads no conversation member');
select is_empty($$ select 1 from public.messages $$, 'a stranger reads no message');
select is_empty($$ select 1 from public.message_translations $$, 'a stranger reads no translation');
select ok(not public.in_conversation('16e00000-0000-4000-8000-000000000001'),
  'in_conversation is false for a stranger');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000024',
                            'mo in c1', 'en') $$,
  '42501', null, 'a stranger cannot send into a conversation');
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021',
                            'mo as jo', 'en') $$,
  '42501', null, 'a stranger cannot send as a member');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read, no write and no function (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok(format('select 1 from public.%I', t), '42501', null, 'anon cannot read ' || t)
from unnest(array['conversations', 'conversation_members', 'messages', 'message_translations']) as t;
select throws_ok($$ insert into public.messages (conversation_id, sender_profile_id, body, language_code)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000021',
                            'anon as jo', 'en') $$,
  '42501', null, 'anon cannot insert a message');
select throws_ok($$ insert into public.conversations default values $$,
  '42501', null, 'anon cannot insert a conversation');
select throws_ok($$ insert into public.conversation_members (conversation_id, profile_id)
                    values ('16e00000-0000-4000-8000-000000000001', '16b00000-0000-4000-8000-000000000024') $$,
  '42501', null, 'anon cannot insert a conversation member');
select throws_ok($$ insert into public.message_translations (message_id, language_code, body)
                    values ('16f00000-0000-4000-8000-000000000002', 'sw', 'anon planted') $$,
  '42501', null, 'anon cannot insert a translation');
select throws_ok($$ select public.in_conversation('16e00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot call in_conversation');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- What the API calls did and did not change.
select is((select count(*)::int from public.messages
           where body in ('jo says hi', 'studio says hi', 'kim says hi')), 3,
  'exactly the three allowed API messages were stored');
select is((select sender_profile_id from public.messages where body = 'jo says hi'),
  '16b00000-0000-4000-8000-000000000021'::uuid, 'the stored sender is the profile Jo acted as');
select is((select sender_profile_id from public.messages where body = 'studio says hi'),
  '16b00000-0000-4000-8000-000000000031'::uuid, 'the stored sender is the business Jo acted as');
select is((select count(*)::int from public.messages
           where body in ('forged as kim', 'jo in c2', 'jo in c3', 'biz in c1', 'no sender', 'chosen id',
                          'back dated', 'forged as lee', 'lee in c1', 'mo in c1', 'mo as jo', 'anon as jo')), 0,
  'no rejected message was stored');
select is((select body from public.messages where id = '16f00000-0000-4000-8000-000000000001'),
  'hello', 'the rejected edit and delete left the first message untouched');

-- Deleting a profile keeps its messages with no sender (Req 5.8) and removes its memberships.
select is((select sender_profile_id from public.messages where id = '16f00000-0000-4000-8000-000000000005'),
  '16b00000-0000-4000-8000-000000000025'::uuid, 'Zed''s message starts with Zed as sender');
delete from public.profiles where id = '16b00000-0000-4000-8000-000000000025';
select ok(exists (select 1 from public.messages
                  where id = '16f00000-0000-4000-8000-000000000005' and sender_profile_id is null
                    and body = 'from zed'),
  'deleting the sender profile keeps the message and sets its sender to null (Req 5.8)');
select is_empty($$ select 1 from public.conversation_members
                   where conversation_id = '16e00000-0000-4000-8000-000000000004'
                     and profile_id = '16b00000-0000-4000-8000-000000000025' $$,
  'deleting a profile removes its conversation memberships');
select is((select count(*)::int from public.conversation_members
           where conversation_id = '16e00000-0000-4000-8000-000000000004'), 1,
  'the other member of the conversation stays');

-- Cascades: a deleted message takes its translations, a deleted conversation its members, messages
-- and translations.
delete from public.messages where id = '16f00000-0000-4000-8000-000000000003';
select is_empty($$ select 1 from public.message_translations
                   where message_id = '16f00000-0000-4000-8000-000000000003' $$,
  'deleting a message deletes its translations');
delete from public.conversations where id = '16e00000-0000-4000-8000-000000000001';
select is_empty($$ select 1 from public.conversation_members
                   where conversation_id = '16e00000-0000-4000-8000-000000000001' $$,
  'deleting a conversation deletes its memberships');
select is_empty($$ select 1 from public.messages where conversation_id = '16e00000-0000-4000-8000-000000000001' $$,
  'deleting a conversation deletes its messages');
select is_empty($$ select 1 from public.message_translations
                   where message_id in ('16f00000-0000-4000-8000-000000000001',
                                        '16f00000-0000-4000-8000-000000000002') $$,
  'deleting a conversation deletes the translations of its messages');

select * from finish();
rollback;
