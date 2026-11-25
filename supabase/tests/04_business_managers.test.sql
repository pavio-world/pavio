-- Business pages and their managers (Spec 00, Req 5.7, 6.7, 7.1 to 7.3, 7.9 to 7.13; DR-1).
-- This file holds the manager part (task 8.3). The business_details part is added by task 9,
-- after migration 6 creates that table.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(68);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims (so the insert triggers keep owner_user_id as given
-- and add no owner row for a business).
-- Olivia owns olivia_cafe (created through the API below), Mark is its manager, Pat is added and
-- removed. Dora is the only owner of dora_bakery and co-owns shared_shop with Ned.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'olivia.test@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'mark.test@example.invalid'),
  ('33333333-3333-4333-8333-333333333333', 'pat.test@example.invalid'),
  ('44444444-4444-4444-8444-444444444444', 'dora.test@example.invalid'),
  ('55555555-5555-4555-8555-555555555555', 'ned.test@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'person', '11111111-1111-4111-8111-111111111111', 'olivia_t', 'Olivia'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'person', '22222222-2222-4222-8222-222222222222', 'mark_t', 'Mark'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'person', '33333333-3333-4333-8333-333333333333', 'pat_t', 'Pat'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'person', '44444444-4444-4444-8444-444444444444', 'dora_t', 'Dora'),
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'person', '55555555-5555-4555-8555-555555555555', 'ned_t', 'Ned');
insert into public.profiles (id, type, handle, display_name) values
  ('d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0', 'business', 'dora_bakery', 'Dora''s Bakery'),
  ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', 'business', 'shared_shop', 'Shared Shop');
insert into public.profile_managers (profile_id, user_id, role) values
  ('d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0', '44444444-4444-4444-8444-444444444444', 'owner'),
  ('d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0', '22222222-2222-4222-8222-222222222222', 'manager'),
  ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', '44444444-4444-4444-8444-444444444444', 'owner'),
  ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', '55555555-5555-4555-8555-555555555555', 'owner');

-- ---------------------------------------------------------------------------------------------
-- Every business needs an owner at commit (Req 7.3). profiles_business_has_owner is deferred, so
-- set constraints all immediate runs it now instead of at commit.
-- ---------------------------------------------------------------------------------------------
select ok((select tgdeferrable and tginitdeferred from pg_catalog.pg_trigger
           where tgname = 'profiles_business_has_owner' and tgrelid = 'public.profiles'::regclass),
  'profiles_business_has_owner is deferrable initially deferred');
select throws_ok($$ do $d$ begin
                      insert into public.profiles (type, handle, display_name) values ('business', 'orphan_biz', 'T');
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'profile.business_needs_owner', 'a business left without an owner is rejected at the deferred check');
set constraints all deferred;

-- Manager rows exist only for businesses (migration 5 deviation: profile_managers_guard).
select throws_ok($$ insert into public.profile_managers (profile_id, user_id, role)
                    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'manager') $$,
  'PT422', 'manager.not_a_business', 'a manager row on a person profile is rejected');
select throws_ok($$ update public.profile_managers set profile_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
                    where profile_id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'
                      and user_id = '22222222-2222-4222-8222-222222222222' $$,
  'PT422', 'manager.not_a_business', 'moving a manager row onto a person profile is rejected');
-- Last owner protection binds every writer, not only the RPCs (Req 7.13).
select throws_ok($$ delete from public.profile_managers
                    where profile_id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'
                      and user_id = '44444444-4444-4444-8444-444444444444' $$,
  'PT422', 'profile.last_owner', 'deleting the only owner row of a business is rejected');
select throws_ok($$ update public.profile_managers set role = 'manager'
                    where profile_id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'
                      and user_id = '44444444-4444-4444-8444-444444444444' $$,
  'PT422', 'profile.last_owner', 'demoting the only owner of a business is rejected');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Olivia, in the canary order (DR-1): she creates a business and manages it.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-4111-8111-111111111111', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Olivia claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-1111-4111-8111-111111111111'::uuid, 'auth.uid() is Olivia');

-- The creating login becomes the owner (Req 6.7, 7.1).
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'olivia_cafe', 'Olivia''s Cafe') $$,
  'Olivia can create a business');
select is((select count(*)::int from public.profile_managers
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')),
  1, 'the new business has exactly one manager row');
select is((select role::text from public.profile_managers
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')
             and user_id = '11111111-1111-4111-8111-111111111111'),
  'owner', 'the creating login holds the owner role');
select ok(public.is_profile_owner((select id from public.profiles where handle = 'olivia_cafe')),
  'is_profile_owner is true for Olivia');
select ok(public.acts_as((select id from public.profiles where handle = 'olivia_cafe')),
  'acts_as is true for Olivia on her business');
select is((select m.role from public.my_profiles() m where m.handle = 'olivia_cafe'), 'owner',
  'my_profiles reports the owner role');
-- A person can hold roles on many businesses (Req 7.2) and still has her person profile.
select is((select count(*)::int from public.my_profiles()), 2, 'my_profiles lists the person and the business');

-- The owner adds and removes managers (Req 7.9).
select lives_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                     'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'manager') $$,
  'the owner can add Mark as a manager');
select is((select role::text from public.profile_managers
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')
             and user_id = '22222222-2222-4222-8222-222222222222'),
  'manager', 'Mark holds the manager role');
select lives_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                     'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'manager') $$,
  'the owner can add Pat as a manager');
select lives_ok($$ select public.remove_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                        'cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  'the owner can remove Pat');
select is((select count(*)::int from public.profile_managers
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')
             and user_id = '33333333-3333-4333-8333-333333333333'),
  0, 'Pat no longer has a manager row');
select throws_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                      gen_random_uuid(), 'manager') $$,
  'PT404', 'manager.person_not_found', 'adding a missing profile is rejected');
select throws_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                      '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', 'manager') $$,
  'PT404', 'manager.person_not_found', 'adding a business profile as a manager is rejected');
select throws_ok($$ select public.add_profile_manager('d0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0',
                                                      'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'manager') $$,
  'PT403', 'manager.owner_only', 'Olivia cannot add managers to a business she does not own');

-- The last owner cannot be removed or demoted (Req 7.13).
select throws_ok($$ select public.remove_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                         'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  'PT422', 'profile.last_owner', 'the last owner cannot remove herself');
select throws_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'manager') $$,
  'PT422', 'profile.last_owner', 'the last owner cannot demote herself to manager');
select is((select role::text from public.profile_managers
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')
             and user_id = '11111111-1111-4111-8111-111111111111'),
  'owner', 'Olivia is still the owner');

-- Writes to profile_managers go only through the RPCs.
select throws_ok($$ insert into public.profile_managers (profile_id, user_id, role)
                    values ((select id from public.profiles where handle = 'olivia_cafe'),
                            '33333333-3333-4333-8333-333333333333', 'manager') $$,
  '42501', null, 'authenticated cannot insert into profile_managers directly');
select throws_ok($$ update public.profile_managers set role = 'owner'
                    where user_id = '22222222-2222-4222-8222-222222222222' $$,
  '42501', null, 'authenticated cannot update profile_managers directly');
select throws_ok($$ delete from public.profile_managers
                    where user_id = '22222222-2222-4222-8222-222222222222' $$,
  '42501', null, 'authenticated cannot delete from profile_managers directly');
-- Olivia sees only manager rows of pages she acts as.
select is_empty($$ select 1 from public.profile_managers where profile_id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0' $$,
  'Olivia cannot read the manager rows of a business she does not act as');

-- Creating then deleting a business in one transaction passes the deferred owner check
-- (migration 5 deviation: profiles_business_has_owner skips a business that no longer exists).
select lives_ok($$ do $d$ begin
                     insert into public.profiles (type, handle, display_name) values ('business', 'temp_biz', 'T');
                     delete from public.profiles where handle = 'temp_biz';
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'creating and deleting a business in one transaction passes the deferred owner check');
select is((select count(*)::int from public.profiles where handle = 'temp_biz'), 0,
  'the owner deleted the business she created');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Mark, a manager of olivia_cafe (Req 7.10 to 7.12).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '22222222-2222-4222-8222-222222222222', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Mark claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '22222222-2222-4222-8222-222222222222'::uuid, 'auth.uid() is Mark');

select ok(public.acts_as((select id from public.profiles where handle = 'olivia_cafe')),
  'acts_as is true for the manager');
select ok(not public.is_profile_owner((select id from public.profiles where handle = 'olivia_cafe')),
  'is_profile_owner is false for the manager');
select is((select m.role from public.my_profiles() m where m.handle = 'olivia_cafe'), 'manager',
  'my_profiles reports the manager role');
select isnt_empty($$ select 1 from public.profile_managers
                     where profile_id = (select id from public.profiles where handle = 'olivia_cafe') $$,
  'the manager can read the manager rows of the business');

-- A manager cannot add, remove or change roles (Req 7.10).
select throws_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                      'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'manager') $$,
  'PT403', 'manager.owner_only', 'a manager cannot add a manager');
select throws_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'owner') $$,
  'PT403', 'manager.owner_only', 'a manager cannot promote himself to owner');
select throws_ok($$ select public.remove_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                         'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  'PT403', 'manager.owner_only', 'a manager cannot remove the owner');
select throws_ok($$ select public.remove_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                         'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  'PT403', 'manager.owner_only', 'a manager cannot remove himself');

-- A manager can edit the business profile (Req 7.12).
select lives_ok($$ update public.profiles set display_name = 'Olivia''s Cafe and Bakery', bio = 'Coffee in Nairobi'
                   where handle = 'olivia_cafe' $$,
  'the manager can update the business profile');
select is((select display_name from public.profiles where handle = 'olivia_cafe'), 'Olivia''s Cafe and Bakery',
  'the manager''s edit was applied');

-- A manager cannot delete the business (Req 7.11). Row security hides the row from the delete.
select lives_ok($$ delete from public.profiles where handle = 'olivia_cafe' $$,
  'the manager''s delete runs without error');
select is((select count(*)::int from public.profiles where handle = 'olivia_cafe'), 1,
  'the business still exists after the manager''s delete');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Pat, who was removed: no access is left.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '33333333-3333-4333-8333-333333333333', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Pat claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '33333333-3333-4333-8333-333333333333'::uuid, 'auth.uid() is Pat');

select ok(not public.acts_as((select id from public.profiles where handle = 'olivia_cafe')),
  'acts_as is false for a removed manager');
select is_empty($$ select 1 from public.profile_managers
                   where profile_id = (select id from public.profiles where handle = 'olivia_cafe') $$,
  'a removed manager cannot read the manager rows');
select lives_ok($$ update public.profiles set display_name = 'Taken over' where handle = 'olivia_cafe' $$,
  'the removed manager''s update runs without error');
select is((select display_name from public.profiles where handle = 'olivia_cafe'), 'Olivia''s Cafe and Bakery',
  'the removed manager''s update changed nothing');

-- ---------------------------------------------------------------------------------------------
-- Back as Olivia: with a second owner, one owner may go (Req 7.9, 7.13).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-4111-8111-111111111111', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Olivia claims again');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-1111-4111-8111-111111111111'::uuid, 'auth.uid() is Olivia again');

select lives_ok($$ select public.add_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                     'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'owner') $$,
  'the owner can promote Mark to owner');
select lives_ok($$ select public.remove_profile_manager((select id from public.profiles where handle = 'olivia_cafe'),
                                                        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  'an owner can remove herself while another owner remains');
select ok(not public.acts_as((select id from public.profiles where handle = 'olivia_cafe')),
  'Olivia no longer acts as the business');

-- ---------------------------------------------------------------------------------------------
-- Deleting the last owner's login deletes the business (Req 5.7); a co-owned business stays.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);
select lives_ok($$ delete from auth.users where id = '44444444-4444-4444-8444-444444444444' $$,
  'Dora''s login can be deleted');
select is((select count(*)::int from public.profiles where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'), 0,
  'Dora''s person profile is deleted with her login');
select is((select count(*)::int from public.profiles where id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'), 0,
  'the business whose last owner login was deleted is deleted');
select is((select count(*)::int from public.profile_managers where profile_id = 'd0d0d0d0-d0d0-4d0d-8d0d-d0d0d0d0d0d0'), 0,
  'the deleted business keeps no manager rows');
select is((select count(*)::int from public.profiles where id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'), 1,
  'a business with another owner left is kept');
select is((select array_agg(user_id) from public.profile_managers where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'),
  array['55555555-5555-4555-8555-555555555555'::uuid], 'the remaining owner is Ned');
select lives_ok($$ set constraints all immediate $$,
  'every business left in the transaction passes the deferred owner check');

select * from finish();
rollback;
