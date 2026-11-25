-- Business pages, their managers and their details (Spec 00, Req 5.7, 6.1 to 6.7, 7.1 to 7.3,
-- 7.9 to 7.13, 25.1, 25.2, 25.4; DR-1).
-- The manager part comes first (task 8.3); the business_details part follows (task 9).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(154);

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

-- =============================================================================================
-- Business details (task 9; Req 6.1 to 6.6, 25.1, 25.2, 25.4).
-- State here: Mark owns olivia_cafe, Ned owns shared_shop, Olivia and Pat hold no business role.
-- =============================================================================================
set constraints all deferred;
-- Ned also owns ned_garage, which has no details yet.
insert into public.profiles (id, type, handle, display_name) values
  ('6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b', 'business', 'ned_garage', 'Ned''s Garage');
insert into public.profile_managers (profile_id, user_id, role) values
  ('6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b', '55555555-5555-4555-8555-555555555555', 'owner');

-- Catalog: table, uniqueness, index, triggers, RLS, policies and grants (Req 6.2, 22.1 to 22.5).
select has_table('public', 'business_details', 'business_details exists');
select col_is_unique('public', 'business_details', 'profile_id', 'business_details.profile_id is unique');
select has_index('public', 'business_details', 'business_details_category_trgm_idx',
  'business_details has the category trigram index');
select trigger_is('public', 'business_details', 'business_details_guard', 'private', 'business_details_guard',
  'business_details_guard trigger calls private.business_details_guard');
select trigger_is('public', 'business_details', 'business_details_set_updated_at', 'private', 'set_updated_at',
  'business_details updated_at trigger calls private.set_updated_at');
select ok((select relrowsecurity from pg_class where oid = 'public.business_details'::regclass),
  'RLS is enabled on business_details');
select policies_are('public', 'business_details', array[
  'business_details_anon_select', 'business_details_authenticated_select',
  'business_details_authenticated_insert', 'business_details_authenticated_update',
  'business_details_authenticated_delete'
], 'business_details has exactly its five policies');
select table_privs_are('public', 'business_details', 'anon', array['SELECT'],
  'anon may only select business_details');
select table_privs_are('public', 'business_details', 'authenticated', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'authenticated may select, insert, update and delete business_details');

-- Function privileges: the validator keeps execute for the API roles, the guard does not.
select volatility_is('private', 'opening_hours_valid', array['jsonb'], 'immutable',
  'opening_hours_valid is immutable');
select ok(has_function_privilege(r, 'private.opening_hours_valid(jsonb)', 'execute'),
  r || ' can execute private.opening_hours_valid(jsonb)')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public', 'private.opening_hours_valid(jsonb)', 'execute'),
  'public cannot execute private.opening_hours_valid(jsonb)');
select ok(not has_function_privilege(r, 'private.business_details_guard()', 'execute'),
  r || ' cannot execute private.business_details_guard()')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- Opening hours validator (Req 6.4).
select ok(private.opening_hours_valid('{}'), 'empty opening hours are valid');
select ok(private.opening_hours_valid('{"mon": {"open": "08:00", "close": "17:30"}, "sun": null}'),
  'a day with open and close times and a closed day are valid');
select ok(private.opening_hours_valid(
  '{"mon": {"open": "00:00", "close": "23:59"}, "tue": null, "wed": null, "thu": null,
    "fri": null, "sat": null, "sun": null}'),
  'all seven days with boundary times are valid');
select ok(not private.opening_hours_valid('{"monday": {"open": "08:00", "close": "17:00"}}'),
  'an unknown day key is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": "24:00", "close": "17:00"}}'),
  'an hour of 24 is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": "8:00", "close": "17:00"}}'),
  'a single digit hour is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": "08:60", "close": "17:00"}}'),
  'a minute of 60 is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": "08:00"}}'),
  'a day without a close time is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": "08:00", "close": "17:00", "note": "x"}}'),
  'a day with an extra key is rejected');
select ok(not private.opening_hours_valid('{"mon": {"open": 800, "close": 1700}}'),
  'numeric times are rejected');
select ok(not private.opening_hours_valid('{"mon": "closed"}'),
  'a day whose value is a string is rejected');
select ok(not private.opening_hours_valid('[]'), 'an array is rejected');
select ok(not private.opening_hours_valid('"mon"'), 'a scalar is rejected');

-- Checks and the guard bind every writer (Req 6.1 to 6.5, 25.4).
select lives_ok($$ insert into public.business_details (profile_id, category, phone, website, opening_hours, address)
                   values ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', 'hardware', '+254 (20) 123-4567',
                           'https://shared.example', '{"mon": {"open": "08:00", "close": "17:00"}, "sun": null}',
                           'Moi Avenue, Nairobi') $$,
  'details with every field can be stored for a business');
select results_eq(
  $$ select category, phone, website, opening_hours, address from public.business_details
     where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  $$ values ('hardware', '+254 (20) 123-4567', 'https://shared.example',
             '{"mon": {"open": "08:00", "close": "17:00"}, "sun": null}'::jsonb, 'Moi Avenue, Nairobi') $$,
  'the stored details equal the input');
select is((select opening_hours from public.business_details where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b'),
  null::jsonb, 'ned_garage has no details row yet');
select throws_ok($$ insert into public.business_details (profile_id) values ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a') $$,
  '23505', null, 'a second details row for the same business is rejected');
select throws_ok($$ insert into public.business_details (profile_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  'PT422', 'business.not_a_business', 'details for a person profile are rejected');
select throws_ok($$ update public.business_details set profile_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'PT422', 'business.not_a_business', 'moving details onto a person profile is rejected');
select throws_ok($$ update public.business_details set website = 'ftp://shared.example'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'a website starting with ftp:// is rejected');
select throws_ok($$ update public.business_details set website = 'www.shared.example'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'a website without a scheme is rejected');
select lives_ok($$ update public.business_details set website = 'http://shared.example'
                   where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'a website starting with http:// is accepted');
select throws_ok($$ update public.business_details set opening_hours = '{"mon": {"open": "25:00", "close": "17:00"}}'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'invalid opening hours are rejected by the check');
select throws_ok($$ update public.business_details set opening_hours = '[]'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'opening hours that are not an object are rejected by the check');
select throws_ok($$ update public.business_details set phone = 'call me'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'a phone with letters is rejected');
select throws_ok($$ update public.business_details set phone = '12345'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'a phone shorter than 6 characters is rejected');
select lives_ok($$ update public.business_details set address = repeat('a', 300)
                   where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'a 300 character address is accepted');
select throws_ok($$ update public.business_details set address = repeat('a', 301)
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'a 301 character address is rejected');
select throws_ok($$ update public.business_details set category = repeat('a', 81)
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '23514', null, 'an 81 character category is rejected');
update public.business_details set updated_at = '2000-01-01T00:00:00Z'
where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a';
select is((select updated_at from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'),
  now(), 'the trigger overwrites business_details.updated_at on update');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Mark, owner of olivia_cafe only: writes need acts_as on the business.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '22222222-2222-4222-8222-222222222222', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Mark claims (details)');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '22222222-2222-4222-8222-222222222222'::uuid, 'auth.uid() is Mark');

select lives_ok($$ insert into public.business_details (profile_id, category)
                   values ((select id from public.profiles where handle = 'olivia_cafe'), 'cafe') $$,
  'Mark can add details to the business he acts as');
select lives_ok($$ update public.business_details set category = 'coffee shop'
                   where profile_id = (select id from public.profiles where handle = 'olivia_cafe') $$,
  'Mark can update the details of the business he acts as');
select is((select category from public.business_details
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')),
  'coffee shop', 'Mark''s update was applied');
select isnt_empty($$ select 1 from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'Mark can read the details of a business he does not act as');
select throws_ok($$ insert into public.business_details (profile_id) values ('6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b') $$,
  '42501', null, 'Mark cannot add details to a business he does not act as');
select throws_ok($$ insert into public.business_details (profile_id) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  'PT422', 'business.not_a_business', 'Mark cannot add details to his own person profile');
select lives_ok($$ update public.business_details set category = 'taken over'
                   where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'Mark''s update of another business''s details runs without error');
select is((select category from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'),
  'hardware', 'Mark''s update of another business''s details changed nothing');
select throws_ok($$ update public.business_details set profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b'
                    where profile_id = (select id from public.profiles where handle = 'olivia_cafe') $$,
  '42501', null, 'Mark cannot move his details onto a business he does not act as');
select lives_ok($$ delete from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'Mark''s delete of another business''s details runs without error');
select is((select count(*)::int from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'),
  1, 'the other business''s details still exist after Mark''s delete');
select lives_ok($$ delete from public.business_details
                   where profile_id = (select id from public.profiles where handle = 'olivia_cafe') $$,
  'Mark can delete the details of the business he acts as');
select is((select count(*)::int from public.business_details
           where profile_id = (select id from public.profiles where handle = 'olivia_cafe')),
  0, 'Mark''s delete removed the details');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Olivia, who no longer holds any business role: she can read but not write.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-4111-8111-111111111111', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Olivia claims (details)');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-1111-4111-8111-111111111111'::uuid, 'auth.uid() is Olivia');

select throws_ok($$ insert into public.business_details (profile_id)
                    values ((select id from public.profiles where handle = 'olivia_cafe')) $$,
  '42501', null, 'a former owner cannot add details');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: details are public (Req 6.6) and anon cannot write (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select results_eq(
  $$ select category, phone, website, opening_hours, address from public.business_details
     where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  $$ values ('hardware', '+254 (20) 123-4567', 'http://shared.example',
             '{"mon": {"open": "08:00", "close": "17:00"}, "sun": null}'::jsonb, repeat('a', 300)) $$,
  'anon can read every details field');
select throws_ok($$ insert into public.business_details (profile_id) values ('6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b') $$,
  '42501', null, 'anon cannot insert details');
select throws_ok($$ update public.business_details set category = 'x'
                    where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '42501', null, 'anon cannot update details');
select throws_ok($$ delete from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  '42501', null, 'anon cannot delete details');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ned, owner of shared_shop and ned_garage.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '55555555-5555-4555-8555-555555555555', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ned claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '55555555-5555-4555-8555-555555555555'::uuid, 'auth.uid() is Ned');

select lives_ok($$ insert into public.business_details (profile_id, website)
                   values ('6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b', 'https://garage.example') $$,
  'Ned can add details to ned_garage');
select is((select opening_hours from public.business_details where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b'),
  '{}'::jsonb, 'opening hours default to an empty object');
select throws_ok($$ insert into public.business_details (profile_id, website)
                    values ('5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a', 'https://again.example') $$,
  '23505', null, 'Ned cannot add a second details row to shared_shop');
select throws_ok($$ update public.business_details set website = 'garage.example'
                    where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b' $$,
  '23514', null, 'the website check binds an API writer');
select throws_ok($$ update public.business_details set opening_hours = '{"sat": {"open": "09:00"}}'
                    where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b' $$,
  '23514', null, 'the opening hours check binds an API writer');
select lives_ok($$ update public.business_details set opening_hours = '{"sat": {"open": "09:00", "close": "13:00"}}'
                   where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b' $$,
  'Ned can set valid opening hours');
select lives_ok($$ delete from public.business_details where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b' $$,
  'Ned can delete the details of ned_garage');
select is((select count(*)::int from public.business_details where profile_id = '6b6b6b6b-6b6b-4b6b-8b6b-6b6b6b6b6b6b'),
  0, 'Ned''s delete removed the details');

-- Deleting a business deletes its details (on delete cascade).
set local role postgres;
select set_config('request.jwt.claims', '', true);
select lives_ok($$ delete from public.profiles where id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a' $$,
  'shared_shop can be deleted');
select is((select count(*)::int from public.business_details where profile_id = '5a5a5a5a-5a5a-4a5a-8a5a-5a5a5a5a5a5a'),
  0, 'the deleted business keeps no details row');

select * from finish();
rollback;
