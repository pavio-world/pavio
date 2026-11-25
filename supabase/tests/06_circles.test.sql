-- Circles and circle members: tables, member label switch rules, membership eligibility, the all
-- followers circle, cascades and access (Spec 00, Req 8.22, 9.1 to 9.10, 9.12 to 9.16, 9.18, 10.1,
-- 10.2, 10.6 to 10.8, 22.8, 25.1, 25.2, 25.4; DR-1).
-- Item_Circle_Links (item_circles) arrive with content in migration 12, so the cascade of links on
-- circle delete (Req 9.18) and the private name checks across every surface (09_circle_privacy)
-- are tested there.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(204);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Amy, Ben, Cal, Dee and Eve are people. Dee owns dee_shop_c, Cal owns cal_works_c.
-- Accepted connections: Amy and Ben, Ben and Cal, dee_shop_c and cal_works_c.
-- Pending connection: Amy to Dee. Eve follows dee_shop_c.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('06060606-0000-4000-8000-000000000001', 'amy.circ@example.invalid'),
  ('06060606-0000-4000-8000-000000000002', 'ben.circ@example.invalid'),
  ('06060606-0000-4000-8000-000000000003', 'cal.circ@example.invalid'),
  ('06060606-0000-4000-8000-000000000004', 'dee.circ@example.invalid'),
  ('06060606-0000-4000-8000-000000000005', 'eve.circ@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('06b00000-0000-4000-8000-000000000001', 'person', '06060606-0000-4000-8000-000000000001', 'amy_c', 'Amy'),
  ('06b00000-0000-4000-8000-000000000002', 'person', '06060606-0000-4000-8000-000000000002', 'ben_c', 'Ben'),
  ('06b00000-0000-4000-8000-000000000003', 'person', '06060606-0000-4000-8000-000000000003', 'cal_c', 'Cal'),
  ('06b00000-0000-4000-8000-000000000004', 'person', '06060606-0000-4000-8000-000000000004', 'dee_c', 'Dee'),
  ('06b00000-0000-4000-8000-000000000005', 'person', '06060606-0000-4000-8000-000000000005', 'eve_c', 'Eve');
insert into public.profiles (id, type, handle, display_name) values
  ('06b00000-0000-4000-8000-000000000011', 'business', 'dee_shop_c', 'Dee''s Shop'),
  ('06b00000-0000-4000-8000-000000000012', 'business', 'cal_works_c', 'Cal''s Works');
insert into public.profile_managers (profile_id, user_id, role) values
  ('06b00000-0000-4000-8000-000000000011', '06060606-0000-4000-8000-000000000004', 'owner'),
  ('06b00000-0000-4000-8000-000000000012', '06060606-0000-4000-8000-000000000003', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('06b00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002', 'connection'),
  ('06b00000-0000-4000-8000-000000000002', '06b00000-0000-4000-8000-000000000003', 'connection'),
  ('06b00000-0000-4000-8000-000000000011', '06b00000-0000-4000-8000-000000000012', 'connection'),
  ('06b00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000004', 'connection'),
  ('06b00000-0000-4000-8000-000000000005', '06b00000-0000-4000-8000-000000000011', 'follow');
update public.relationships set status = 'accepted'
where type = 'connection'
  and requester_profile_id in ('06b00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002',
                               '06b00000-0000-4000-8000-000000000011')
  and target_profile_id in ('06b00000-0000-4000-8000-000000000002', '06b00000-0000-4000-8000-000000000003',
                            '06b00000-0000-4000-8000-000000000012');

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, defaults, keys, checks, indexes, triggers (Req 9.1, 9.3, 9.15, 10.1, 25.5).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'circles', 'circles exists');
select has_table('public', 'circle_members', 'circle_members exists');
select columns_are('public', 'circles', array[
  'id', 'owner_profile_id', 'private_name', 'show_member_label', 'member_label', 'is_all_followers',
  'created_at', 'updated_at'
], 'circles has exactly its eight columns');
select columns_are('public', 'circle_members', array['id', 'circle_id', 'member_profile_id', 'created_at'],
  'circle_members has exactly its four columns');
select col_is_pk('public', 'circles', 'id', 'circles.id is the primary key');
select col_is_pk('public', 'circle_members', 'id', 'circle_members.id is the primary key');
select col_default_is('public', 'circles', 'show_member_label', false,
  'the member label switch defaults to off');
select col_default_is('public', 'circles', 'is_all_followers', false,
  'is_all_followers defaults to false');
select col_not_null('public', 'circles', c, 'circles.' || c || ' is not null')
from unnest(array['owner_profile_id', 'private_name', 'show_member_label', 'is_all_followers']) as c;
select col_is_null('public', 'circles', 'member_label', 'circles.member_label is optional');
select ok(exists (select 1 from pg_catalog.pg_constraint
                  where conrelid = 'public.circles'::regclass and contype = 'c' and conname = c),
  'circles has the check ' || c)
from unnest(array['circles_private_name_length', 'circles_member_label_length',
                  'circles_label_when_shown']) as c;
select is((select confdeltype::text from pg_catalog.pg_constraint
           where conrelid = t::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = t::regclass and attname = c)]::smallint[]),
  'c', t || '.' || c || ' cascades on delete')
from (values ('public.circles', 'owner_profile_id'),
             ('public.circle_members', 'circle_id'),
             ('public.circle_members', 'member_profile_id')) as v(t, c);
select index_is_unique('public', 'circles', 'circles_owner_name_uq', 'circles_owner_name_uq is unique');
select ok(pg_catalog.pg_get_indexdef('public.circles_owner_name_uq'::regclass)
            like '%(owner_profile_id, lower(private_name))%',
  'circles_owner_name_uq compares the private name case insensitively per owner');
select index_is_unique('public', 'circles', 'circles_all_followers_uq', 'circles_all_followers_uq is unique');
select ok(pg_catalog.pg_get_indexdef('public.circles_all_followers_uq'::regclass)
            like '%(owner_profile_id) WHERE is_all_followers%',
  'circles_all_followers_uq is partial on is_all_followers');
select has_index('public', 'circles', 'circles_owner_label_order_idx',
  array['owner_profile_id', 'created_at', 'id'], 'circles has the label order index');
select col_is_unique('public', 'circle_members', array['circle_id', 'member_profile_id'],
  'one membership per circle and profile');
select has_index('public', 'circle_members', 'circle_members_member_profile_id_idx', 'member_profile_id',
  'circle_members has the member index');
select trigger_is('public', v.t, v.trg, 'private', v.fn, v.trg || ' calls private.' || v.fn)
from (values ('circles', 'circles_before_write', 'circles_before_write'),
             ('circles', 'circles_before_delete', 'circles_before_delete'),
             ('circles', 'circles_set_updated_at', 'set_updated_at'),
             ('circle_members', 'circle_members_guard', 'circle_members_guard'),
             ('relationships', 'relationships_after_delete', 'relationships_after_delete'),
             ('profiles', 'profiles_after_insert', 'profiles_after_insert')) as v(t, trg, fn);

-- ---------------------------------------------------------------------------------------------
-- RLS, policies and grants (Req 9.9, 9.16, 22.1 to 22.3, 22.5, 22.8).
-- ---------------------------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = t::regclass), 'RLS is enabled on ' || t)
from unnest(array['public.circles', 'public.circle_members']) as t;
select policies_are('public', 'circles', array[
  'circles_authenticated_select', 'circles_authenticated_insert',
  'circles_authenticated_update', 'circles_authenticated_delete'
], 'circles has exactly its four policies');
select policies_are('public', 'circle_members', array[
  'circle_members_authenticated_select', 'circle_members_authenticated_insert',
  'circle_members_authenticated_delete'
], 'circle_members has exactly its three policies');
select is((select count(*)::int from pg_policies
           where schemaname = 'public' and tablename in ('circles', 'circle_members')
             and roles <> array['authenticated']::name[]),
  0, 'every circle policy applies to authenticated only');
select table_privs_are('public', t, 'anon', array[]::text[], 'anon has no privilege on ' || t)
from unnest(array['circles', 'circle_members']) as t;
select ok(not has_any_column_privilege('anon', t, p), 'anon has no column ' || p || ' on ' || t)
from unnest(array['public.circles', 'public.circle_members']) as t
cross join unnest(array['SELECT', 'INSERT', 'UPDATE']) as p;
select table_privs_are('public', 'circles', 'authenticated', array['SELECT', 'DELETE'],
  'authenticated may select and delete circles at table level');
select table_privs_are('public', 'circle_members', 'authenticated', array['SELECT', 'INSERT', 'DELETE'],
  'authenticated may select, insert and delete circle members');
select ok(has_column_privilege('authenticated', 'public.circles', c, 'INSERT'),
  'authenticated may insert circles.' || c)
from unnest(array['owner_profile_id', 'private_name', 'show_member_label', 'member_label']) as c;
select ok(has_column_privilege('authenticated', 'public.circles', c, 'UPDATE'),
  'authenticated may update circles.' || c)
from unnest(array['private_name', 'show_member_label', 'member_label']) as c;
select ok(not has_column_privilege('authenticated', 'public.circles', 'is_all_followers', p),
  'authenticated may not ' || p || ' circles.is_all_followers')
from unnest(array['INSERT', 'UPDATE']) as p;
select ok(not has_column_privilege('authenticated', 'public.circles', 'owner_profile_id', 'UPDATE'),
  'authenticated may not move a circle to another owner');

-- The new and replaced private functions: definer, empty search_path, no execute for the API roles.
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array[
  'private.circles_before_write()', 'private.circles_before_delete()', 'private.circle_members_guard()',
  'private.in_circle(uuid, uuid)', 'private.profiles_after_insert()', 'private.relationships_after_delete()'
]) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array[
  'private.circles_before_write()', 'private.circles_before_delete()', 'private.circle_members_guard()',
  'private.in_circle(uuid, uuid)', 'private.profiles_after_insert()', 'private.relationships_after_delete()'
]) as f;
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array[
  'private.circles_before_write()', 'private.circles_before_delete()', 'private.circle_members_guard()',
  'private.in_circle(uuid, uuid)', 'private.profiles_after_insert()', 'private.relationships_after_delete()'
]) as f
cross join unnest(array['public', 'anon', 'authenticated']) as r;
select volatility_is('private', 'in_circle', array['uuid', 'uuid'], 'stable', 'private.in_circle is stable');

-- ---------------------------------------------------------------------------------------------
-- The all followers circle (Req 10.1, 10.2, 10.6 to 10.8).
-- ---------------------------------------------------------------------------------------------
select results_eq(
  $$ select private_name, show_member_label, member_label is null
     from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000011' $$,
  $$ values ('all followers'::text, false, true) $$,
  'a new business gets exactly one all followers circle, named "all followers", switch off');
select is((select count(*)::int from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000012' and is_all_followers),
  1, 'every business gets its own all followers circle');
select is_empty(
  $$ select 1 from public.circles where owner_profile_id in (
       '06b00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000005') $$,
  'a person gets no automatic circle');
select is_empty(
  $$ select 1 from public.profiles p where p.type = 'business'
     and (select count(*) from public.circles c where c.owner_profile_id = p.id and c.is_all_followers) <> 1 $$,
  'no business in the database lacks its all followers circle (backfill)');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name, is_all_followers)
                    values ('06b00000-0000-4000-8000-000000000001', 'everyone', true) $$,
  'PT422', 'circle.all_followers_business_only', 'an all followers circle on a person is rejected');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name, is_all_followers)
                    values ('06b00000-0000-4000-8000-000000000011', 'more followers', true) $$,
  '23505', null, 'a second all followers circle on a business is rejected');
select throws_ok($$ update public.circles set private_name = 'fans'
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'the all followers circle cannot be renamed');
select throws_ok($$ update public.circles set private_name = 'All Followers'
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'not even by changing its case');
select throws_ok($$ delete from public.circles
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'the all followers circle cannot be deleted on its own');
select throws_ok($$ update public.circles set is_all_followers = false
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.immutable', 'the all followers circle cannot be turned into a normal circle');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    select c.id, '06b00000-0000-4000-8000-000000000005' from public.circles c
                    where c.owner_profile_id = '06b00000-0000-4000-8000-000000000011' and c.is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'the all followers circle cannot be filled by hand, even with a follower');
select ok(private.in_circle(
            (select id from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000011'
             and is_all_followers), '06b00000-0000-4000-8000-000000000005'),
  'a follower is in the all followers circle without a membership row (Req 10.3, 10.4)');
select ok(not private.in_circle(
            (select id from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000011'
             and is_all_followers), '06b00000-0000-4000-8000-000000000003'),
  'a person who does not follow is not in the all followers circle');
select lives_ok($$ update public.circles set show_member_label = true
                   where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'the member label switch on all followers can be turned on (Req 10.7)');
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers),
  'all followers', 'the all followers label is pre-filled like any other circle');
select lives_ok($$ update public.circles set member_label = 'Our regulars'
                   where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'the all followers member label can be changed');
select throws_ok($$ update public.circles set member_label = null
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.label_required', 'the shown all followers label cannot be cleared');
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers),
  'Our regulars', 'the all followers label is unchanged after the rejected clear');

-- ---------------------------------------------------------------------------------------------
-- Member label switch rules (Req 9.4 to 9.8) and private name rules (Req 9.1 to 9.3).
-- ---------------------------------------------------------------------------------------------
insert into public.circles (id, owner_profile_id, private_name) values
  ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000001', 'family'),
  ('06c00000-0000-4000-8000-000000000003', '06b00000-0000-4000-8000-000000000001', 'friends'),
  ('06c00000-0000-4000-8000-000000000004', '06b00000-0000-4000-8000-000000000002', 'mates'),
  ('06c00000-0000-4000-8000-000000000005', '06b00000-0000-4000-8000-000000000011', 'regulars');
insert into public.circles (id, owner_profile_id, private_name, show_member_label, member_label) values
  ('06c00000-0000-4000-8000-000000000002', '06b00000-0000-4000-8000-000000000001', 'the cabal', true,
   'Inner circle');

select results_eq(
  $$ select show_member_label, member_label from public.circles
     where id = '06c00000-0000-4000-8000-000000000001' $$,
  $$ values (false, null::text) $$,
  'a circle created without a switch value has the switch off and no label (Req 9.4)');
select is((select member_label from public.circles where id = '06c00000-0000-4000-8000-000000000002'),
  'Inner circle', 'a label given with the switch on is kept as given');
update public.circles set show_member_label = true where id = '06c00000-0000-4000-8000-000000000001';
select is((select member_label from public.circles where id = '06c00000-0000-4000-8000-000000000001'),
  'family', 'turning the switch on for the first time pre-fills the label from the private name (Req 9.5)');
update public.circles set private_name = 'kin' where id = '06c00000-0000-4000-8000-000000000001';
select results_eq(
  $$ select private_name, member_label from public.circles where id = '06c00000-0000-4000-8000-000000000001' $$,
  $$ values ('kin'::text, 'family'::text) $$,
  'renaming the circle keeps the member label (Req 9.7)');
update public.circles set show_member_label = false where id = '06c00000-0000-4000-8000-000000000001';
select results_eq(
  $$ select show_member_label, member_label from public.circles where id = '06c00000-0000-4000-8000-000000000001' $$,
  $$ values (false, 'family'::text) $$,
  'turning the switch off keeps the member label (Req 9.8)');
update public.circles set show_member_label = true where id = '06c00000-0000-4000-8000-000000000001';
select is((select member_label from public.circles where id = '06c00000-0000-4000-8000-000000000001'),
  'family', 'turning the switch on again shows the same label, not the new private name');
insert into public.circles (owner_profile_id, private_name, show_member_label)
values ('06b00000-0000-4000-8000-000000000001', 'neighbours', true);
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000001' and private_name = 'neighbours'),
  'neighbours', 'a circle created with the switch on and no label is pre-filled');

-- The pre-fill happens only when the switch turns on. While the switch is on, clearing the label
-- is rejected, so the private name is never copied into a label members already see.
select throws_ok($$ update public.circles set member_label = null where id = '06c00000-0000-4000-8000-000000000001' $$,
  'PT422', 'circle.label_required', 'clearing the label while the switch is on is rejected');
select throws_ok($$ update public.circles set member_label = '   ' where id = '06c00000-0000-4000-8000-000000000001' $$,
  'PT422', 'circle.label_required', 'blanking the label while the switch is on is rejected');
select throws_ok($$ update public.circles set show_member_label = true, member_label = null
                    where id = '06c00000-0000-4000-8000-000000000001' $$,
  'PT422', 'circle.label_required', 'keeping the switch on while clearing the label is rejected, not pre-filled');
select throws_ok($$ update public.circles set private_name = 'clan', member_label = null
                    where id = '06c00000-0000-4000-8000-000000000001' $$,
  'PT422', 'circle.label_required', 'renaming while clearing the shown label is rejected');
select results_eq(
  $$ select private_name, member_label from public.circles where id = '06c00000-0000-4000-8000-000000000001' $$,
  $$ values ('kin'::text, 'family'::text) $$,
  'the rejected writes left the name and the shown label as they were');

insert into public.circles (owner_profile_id, private_name, member_label) values
  ('06b00000-0000-4000-8000-000000000003', 'colleagues', 'Work people');
update public.circles set show_member_label = true
where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'colleagues';
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'colleagues'),
  'Work people', 'switching on with a label already set keeps that label');

insert into public.circles (owner_profile_id, private_name) values
  ('06b00000-0000-4000-8000-000000000003', 'cousins');
update public.circles set show_member_label = true, member_label = '  '
where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'cousins';
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'cousins'),
  'cousins', 'switching on with a blank label pre-fills it from the private name');
insert into public.circles (owner_profile_id, private_name, show_member_label, member_label) values
  ('06b00000-0000-4000-8000-000000000003', 'aunts', true, ' ');
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'aunts'),
  'aunts', 'a circle created with the switch on and a blank label is pre-filled');

select lives_ok($$ update public.circles set show_member_label = false, member_label = null
                   where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'cousins' $$,
  'the label may be cleared while the switch is off');
select lives_ok($$ update public.circles set private_name = 'second cousins'
                   where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'cousins' $$,
  'a circle with the switch off and no label can be renamed');
select results_eq(
  $$ select show_member_label, member_label from public.circles
     where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'second cousins' $$,
  $$ values (false, null::text) $$,
  'renaming with the switch off copies nothing into the label');
update public.circles set show_member_label = true
where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'second cousins';
select is((select member_label from public.circles
           where owner_profile_id = '06b00000-0000-4000-8000-000000000003' and private_name = 'second cousins'),
  'second cousins', 'only the off to on switch with no label copies the current private name');

-- Req 9.6: the check is the last line of defence behind the pre-fill and the circle.label_required
-- guard, so the trigger is switched off inside this rolled back transaction to reach it.
alter table public.circles disable trigger circles_before_write;
select throws_ok($$ update public.circles set show_member_label = true, member_label = null
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  '23514', null, 'switching the label on with no label is rejected (Req 9.6)');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name, show_member_label)
                    values ('06b00000-0000-4000-8000-000000000001', 'no label', true) $$,
  '23514', null, 'creating a circle with the switch on and no label is rejected (Req 9.6)');
alter table public.circles enable trigger circles_before_write;

select throws_ok($$ insert into public.circles (owner_profile_id, private_name)
                    values ('06b00000-0000-4000-8000-000000000001', '') $$,
  '23514', null, 'an empty private name is rejected');
select throws_ok(format($$ insert into public.circles (owner_profile_id, private_name)
                           values ('06b00000-0000-4000-8000-000000000001', %L) $$, repeat('a', 51)),
  '23514', null, 'a 51 character private name is rejected');
select lives_ok(format($$ insert into public.circles (owner_profile_id, private_name, member_label)
                          values ('06b00000-0000-4000-8000-000000000001', %L, %L) $$,
                       repeat('b', 50), repeat('c', 50)),
  'a 50 character private name and member label are accepted');
select throws_ok($$ update public.circles set member_label = '' where id = '06c00000-0000-4000-8000-000000000003' $$,
  '23514', null, 'an empty member label is rejected');
select throws_ok(format($$ update public.circles set member_label = %L
                           where id = '06c00000-0000-4000-8000-000000000003' $$, repeat('d', 51)),
  '23514', null, 'a 51 character member label is rejected');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name)
                    values ('06b00000-0000-4000-8000-000000000001', 'KIN') $$,
  '23505', null, 'a private name already used by the owner is rejected, ignoring case (Req 9.3)');
select throws_ok($$ update public.circles set private_name = 'The Cabal'
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  '23505', null, 'renaming onto another of the owner''s names is rejected, ignoring case');
select lives_ok($$ insert into public.circles (owner_profile_id, private_name)
                   values ('06b00000-0000-4000-8000-000000000002', 'the cabal') $$,
  'another owner may use the same private name');
select is((select count(*)::int from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000001'),
  5, 'one owner may hold many circles (Req 9.2)');
select throws_ok($$ update public.circles set is_all_followers = true
                    where id = '06c00000-0000-4000-8000-000000000005' $$,
  'PT422', 'circle.immutable', 'a normal business circle cannot become all followers');
select throws_ok($$ update public.circles set owner_profile_id = '06b00000-0000-4000-8000-000000000002'
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  'PT422', 'circle.immutable', 'a circle cannot move to another owner');

-- ---------------------------------------------------------------------------------------------
-- Membership eligibility (Req 9.12 to 9.15).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.circle_members (circle_id, member_profile_id) values
                   ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002'),
                   ('06c00000-0000-4000-8000-000000000002', '06b00000-0000-4000-8000-000000000002'),
                   ('06c00000-0000-4000-8000-000000000003', '06b00000-0000-4000-8000-000000000002') $$,
  'an accepted connection can be placed in several of the owner''s circles (Req 9.12, 9.14)');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000003') $$,
  'PT422', 'circle.member_not_connected', 'a profile with no relationship cannot be added (Req 9.13)');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000004') $$,
  'PT422', 'circle.member_not_connected', 'a pending connection cannot be added');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000001') $$,
  'PT422', 'circle.self', 'the owner cannot be placed in her own circle');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002') $$,
  '23505', null, 'a duplicate membership is rejected (Req 9.15)');
select throws_ok($$ update public.circle_members set member_profile_id = '06b00000-0000-4000-8000-000000000003'
                    where circle_id = '06c00000-0000-4000-8000-000000000001' $$,
  'PT422', 'circle.member_not_connected', 'a membership cannot be changed to a non connection');
select lives_ok($$ insert into public.circle_members (circle_id, member_profile_id) values
                   ('06c00000-0000-4000-8000-000000000004', '06b00000-0000-4000-8000-000000000001'),
                   ('06c00000-0000-4000-8000-000000000004', '06b00000-0000-4000-8000-000000000003') $$,
  'Ben places both of his connections in his circle');
select lives_ok($$ insert into public.circle_members (circle_id, member_profile_id) values
                   ('06c00000-0000-4000-8000-000000000005', '06b00000-0000-4000-8000-000000000012'),
                   ('06c00000-0000-4000-8000-000000000005', '06b00000-0000-4000-8000-000000000005') $$,
  'a business places a connected business and a follower in a hand picked circle (Req 9.12)');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000005', '06b00000-0000-4000-8000-000000000003') $$,
  'PT422', 'circle.member_not_connected', 'a person who does not follow the business cannot be added');
select ok(private.in_circle('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002'),
  'in_circle is true for a member');
select ok(not private.in_circle('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000003'),
  'in_circle is false for a non member');
select ok(not private.in_circle('06c00000-0000-4000-8000-0000000000ff', '06b00000-0000-4000-8000-000000000002'),
  'in_circle is false for a circle that does not exist');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Amy, in the canary order (DR-1): only her own circles (Req 9.9, 9.10, 9.16, 22.8).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '06060606-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Amy claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '06060606-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Amy');

select is((select count(*)::int from public.circles), 5, 'Amy reads exactly her own five circles');
select is_empty($$ select 1 from public.circles where owner_profile_id <> '06b00000-0000-4000-8000-000000000001' $$,
  'Amy reads no circle of another profile, including the businesses');
select is_empty($$ select 1 from public.circle_members where member_profile_id = '06b00000-0000-4000-8000-000000000001' $$,
  'Amy cannot see that she is in Ben''s circle (Req 9.17 silence)');
select is((select count(*)::int from public.circle_members), 3, 'Amy reads the members of her own circles only');
select lives_ok($$ insert into public.circles (owner_profile_id, private_name)
                   values ('06b00000-0000-4000-8000-000000000001', 'book club') $$,
  'Amy can create a circle for herself');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name)
                    values ('06b00000-0000-4000-8000-000000000002', 'planted') $$,
  '42501', null, 'Amy cannot create a circle for Ben');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name, is_all_followers)
                    values ('06b00000-0000-4000-8000-000000000001', 'sneaky', false) $$,
  '42501', null, 'is_all_followers cannot be written by the API on insert');
select lives_ok($$ update public.circles set private_name = 'old friends'
                   where id = '06c00000-0000-4000-8000-000000000003' $$,
  'Amy can rename her own circle');
select lives_ok($$ update public.circles set show_member_label = true
                   where id = '06c00000-0000-4000-8000-000000000003' $$,
  'Amy can turn on her circle''s label switch');
select throws_ok($$ update public.circles set member_label = null
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  'PT422', 'circle.label_required', 'Amy cannot clear the label of a circle whose switch is on');
select throws_ok($$ update public.circles set is_all_followers = true
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  '42501', null, 'is_all_followers cannot be written by the API on update');
select throws_ok($$ update public.circles set owner_profile_id = '06b00000-0000-4000-8000-000000000002'
                    where id = '06c00000-0000-4000-8000-000000000003' $$,
  '42501', null, 'owner_profile_id cannot be written by the API on update');
select lives_ok($$ update public.circles set private_name = 'hijacked', show_member_label = true
                   where id = '06c00000-0000-4000-8000-000000000004' $$,
  'an update of Ben''s circle by Amy runs but touches nothing');
select lives_ok($$ delete from public.circles where id = '06c00000-0000-4000-8000-000000000004' $$,
  'a delete of Ben''s circle by Amy runs but touches nothing');
select lives_ok($$ delete from public.circle_members where circle_id = '06c00000-0000-4000-8000-000000000004' $$,
  'a delete of Ben''s circle members by Amy runs but touches nothing');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000004', '06b00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'Amy cannot add members to Ben''s circle');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000003') $$,
  'PT422', 'circle.member_not_connected', 'the eligibility guard also binds the API');
select lives_ok($$ delete from public.circle_members
                   where circle_id = '06c00000-0000-4000-8000-000000000003'
                     and member_profile_id = '06b00000-0000-4000-8000-000000000002' $$,
  'Amy can remove a member from her own circle');
select lives_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                   values ('06c00000-0000-4000-8000-000000000003', '06b00000-0000-4000-8000-000000000002') $$,
  'Amy can add a connection to her own circle');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Dee, acting as her business (Req 10.6, 10.7).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '06060606-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Dee claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '06060606-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Dee');

select is((select count(*)::int from public.circles), 2, 'Dee reads her business''s two circles');
select lives_ok($$ update public.circles set show_member_label = false
                   where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'Dee can switch the all followers label off');
select throws_ok($$ update public.circles set private_name = 'fans'
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'Dee cannot rename the all followers circle');
select throws_ok($$ delete from public.circles
                    where owner_profile_id = '06b00000-0000-4000-8000-000000000011' and is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'Dee cannot delete the all followers circle');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    select c.id, '06b00000-0000-4000-8000-000000000005' from public.circles c
                    where c.owner_profile_id = '06b00000-0000-4000-8000-000000000011' and c.is_all_followers $$,
  'PT422', 'circle.all_followers_fixed', 'Dee cannot fill the all followers circle by hand');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read and no write (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.circles $$, '42501', null, 'anon cannot read circles');
select throws_ok($$ select 1 from public.circle_members $$, '42501', null, 'anon cannot read circle members');
select throws_ok($$ insert into public.circles (owner_profile_id, private_name)
                    values ('06b00000-0000-4000-8000-000000000001', 'anon circle') $$,
  '42501', null, 'anon cannot insert a circle');
select throws_ok($$ update public.circles set private_name = 'x' $$, '42501', null, 'anon cannot update circles');
select throws_ok($$ delete from public.circles $$, '42501', null, 'anon cannot delete circles');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('06c00000-0000-4000-8000-000000000001', '06b00000-0000-4000-8000-000000000002') $$,
  '42501', null, 'anon cannot insert a circle member');
select throws_ok($$ delete from public.circle_members $$, '42501', null, 'anon cannot delete circle members');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- What the API calls did and did not change.
select results_eq(
  $$ select private_name, show_member_label from public.circles where id = '06c00000-0000-4000-8000-000000000004' $$,
  $$ values ('mates'::text, false) $$,
  'Ben''s circle is untouched by Amy''s update');
select is((select count(*)::int from public.circle_members where circle_id = '06c00000-0000-4000-8000-000000000004'),
  2, 'Ben''s circle members are untouched by Amy''s delete');
select results_eq(
  $$ select private_name, show_member_label, member_label from public.circles
     where id = '06c00000-0000-4000-8000-000000000003' $$,
  $$ values ('old friends'::text, true, 'old friends'::text) $$,
  'Amy''s rename and switch through the API took effect, with the label pre-filled');
select ok(exists (select 1 from public.circles
                  where owner_profile_id = '06b00000-0000-4000-8000-000000000001' and private_name = 'book club'
                    and not is_all_followers),
  'the circle Amy created through the API is a normal circle');

-- ---------------------------------------------------------------------------------------------
-- Cascades (Req 9.18) and relationship removal (Req 8.22).
-- ---------------------------------------------------------------------------------------------
delete from public.circles where id = '06c00000-0000-4000-8000-000000000003';
select is_empty($$ select 1 from public.circle_members where circle_id = '06c00000-0000-4000-8000-000000000003' $$,
  'deleting a circle deletes its members (Req 9.18)');

-- Amy and Ben disconnect: Ben leaves Amy's circles and Amy leaves Ben's, Cal stays in Ben's.
delete from public.relationships
where type = 'connection'
  and requester_profile_id = '06b00000-0000-4000-8000-000000000001'
  and target_profile_id = '06b00000-0000-4000-8000-000000000002';
select is_empty(
  $$ select 1 from public.circle_members cm join public.circles c on c.id = cm.circle_id
     where c.owner_profile_id = '06b00000-0000-4000-8000-000000000001'
       and cm.member_profile_id = '06b00000-0000-4000-8000-000000000002' $$,
  'removing a connection removes the other profile from the owner''s circles (Req 8.22)');
select is_empty(
  $$ select 1 from public.circle_members cm join public.circles c on c.id = cm.circle_id
     where c.owner_profile_id = '06b00000-0000-4000-8000-000000000002'
       and cm.member_profile_id = '06b00000-0000-4000-8000-000000000001' $$,
  'and removes the owner from the other profile''s circles');
select results_eq(
  $$ select member_profile_id from public.circle_members where circle_id = '06c00000-0000-4000-8000-000000000004' $$,
  $$ values ('06b00000-0000-4000-8000-000000000003'::uuid) $$,
  'memberships that rest on other relationships stay');

-- Eve unfollows Dee's shop: she leaves the hand picked circle and the all followers audience.
delete from public.relationships
where type = 'follow'
  and requester_profile_id = '06b00000-0000-4000-8000-000000000005'
  and target_profile_id = '06b00000-0000-4000-8000-000000000011';
select is_empty($$ select 1 from public.circle_members
                   where circle_id = '06c00000-0000-4000-8000-000000000005'
                     and member_profile_id = '06b00000-0000-4000-8000-000000000005' $$,
  'unfollowing removes the follower from the business''s hand picked circles');
select ok(not private.in_circle(
            (select id from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000011'
             and is_all_followers), '06b00000-0000-4000-8000-000000000005'),
  'a former follower is no longer in the all followers circle (Req 10.5)');
select is((select count(*)::int from public.circle_members where circle_id = '06c00000-0000-4000-8000-000000000005'),
  1, 'the connected business stays in the hand picked circle');

-- Deleting a business takes its all followers circle with it (the only way it goes).
select lives_ok($$ delete from public.profiles where id = '06b00000-0000-4000-8000-000000000012' $$,
  'a business with an all followers circle can be deleted');
select is_empty($$ select 1 from public.circles where owner_profile_id = '06b00000-0000-4000-8000-000000000012' $$,
  'its circles go with it');
select is_empty($$ select 1 from public.circle_members where member_profile_id = '06b00000-0000-4000-8000-000000000012' $$,
  'and so do its memberships in other circles');

select * from finish();
rollback;
