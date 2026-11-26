-- Stretch tables: groups and group members (Spec 00, Req 19.1 to 19.3, 19.7, 22.1 to 22.3, 22.5,
-- 25.1, 25.2; DR-1, DR-4).
-- Later tasks add their sections below the groups part, before finish(): ai_usage (migration 20),
-- lastfm_links (migration 21) and the chat tables (migration 22). Each section raises the plan.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(123);

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

select * from finish();
rollback;
