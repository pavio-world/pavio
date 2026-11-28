-- Handles and profiles: format, reserved words, uniqueness, defaults, lengths, one person per login,
-- column grants, image path kinds and acts_as (Spec 00, Req 4.2 to 4.5, 4.8, 4.10, 4.12 to 4.16,
-- 5.2 to 5.4, 7.4 to 7.6, 22.5, 25.1, 25.2, 25.4, 25.9, 25.10; D-6, D-8, DR-1).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(138);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims (so the insert trigger keeps owner_user_id as given).
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'amina.test@example.invalid'),
  ('22222222-2222-4222-8222-222222222222', 'brian.test@example.invalid'),
  ('33333333-3333-4333-8333-333333333333', 'chris.test@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'person', '11111111-1111-4111-8111-111111111111', 'amina_k', 'Amina'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'person', '22222222-2222-4222-8222-222222222222', 'brian_t', 'Brian');

-- ---------------------------------------------------------------------------------------------
-- Handle format (Req 4.3) and handles never rewritten (D-6).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'abc', 'T') $$,
  'a 3 character handle is accepted');
select lives_ok($$ insert into public.profiles (type, handle, display_name)
                   values ('business', 'a' || repeat('b', 29), 'T') $$,
  'a 30 character handle is accepted');
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'a_1', 'T') $$,
  'a handle with a digit and underscore is accepted');
select is((select count(*)::int from public.profiles where handle = 'a_1'), 1,
  'the stored handle equals the input');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'ab', 'T') $$,
  '23514', null, 'a 2 character handle is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name)
                    values ('business', 'a' || repeat('b', 30), 'T') $$,
  '23514', null, 'a 31 character handle is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', '9lives', 'T') $$,
  '23514', null, 'a handle starting with a digit is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', '_abc', 'T') $$,
  '23514', null, 'a handle starting with an underscore is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'with-dash', 'T') $$,
  '23514', null, 'a handle with a dash is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'with space', 'T') $$,
  '23514', null, 'a handle with a space is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'Amina_X', 'T') $$,
  '23514', null, 'a handle with capitals (Amina_X) is rejected');
select ok(not exists (select 1 from public.profiles where handle = 'amina_x'),
  'Amina_X was not lowercased into amina_x');
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'amina_x', 'T') $$,
  'the lowercase handle amina_x is accepted');
select is((select count(*)::int from public.profiles where lower(handle) = 'amina_x' and handle = 'amina_x'), 1,
  'the stored handle amina_x equals its input');

-- ---------------------------------------------------------------------------------------------
-- Reserved words (Req 4.4, 4.5), compared as given (D-6).
-- ---------------------------------------------------------------------------------------------
select throws_ok(
  format($$ insert into public.profiles (type, handle, display_name) values ('business', %L, 'T') $$, w),
  'PT422', 'profile.handle_reserved', 'reserved handle ' || w || ' is rejected')
from unnest(array[
  'api', 'app', 'admin', 'auth', 'login', 'logout', 'signup', 'settings', 'search', 'circles',
  'notifications', 'edit', 'help', 'about', 'terms', 'privacy', 'pavio', 'www', 'static', '_next', 'demo'
]) as w;
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'Admin', 'T') $$,
  '23514', null, 'Admin is rejected by the format check, not lowercased into a reserved word');

-- ---------------------------------------------------------------------------------------------
-- Case insensitive uniqueness (Req 4.2).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'brian_t', 'T') $$,
  '23505', null, 'a duplicate handle is rejected');
select ok((select indisunique from pg_catalog.pg_index where indexrelid = 'public.profiles_handle_uq'::regclass),
  'profiles_handle_uq is unique');
select ok(pg_catalog.pg_get_indexdef('public.profiles_handle_uq'::regclass) like '%lower(handle)%',
  'profiles_handle_uq compares lower(handle)');

-- ---------------------------------------------------------------------------------------------
-- Defaults and checks for language, dot colour, theme and 2006 mode (Req 4.7 to 4.12).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'defaults_biz', 'T') $$,
  'a profile with only the required fields is accepted');
select is((select preferred_language from public.profiles where handle = 'defaults_biz'), 'en',
  'preferred_language defaults to en');
select is((select dot_colour::text from public.profiles where handle = 'defaults_biz'), 'terracotta',
  'dot_colour defaults to terracotta');
select is((select theme from public.profiles where handle = 'defaults_biz'), '{}'::jsonb,
  'theme defaults to an empty object');
select is((select mode_2006 from public.profiles where handle = 'defaults_biz'), false,
  'mode_2006 defaults to false');
select throws_ok($$ insert into public.profiles (type, handle, display_name, preferred_language)
                    values ('business', 'french_biz', 'T', 'fr') $$,
  '23503', null, 'a language outside the languages table is rejected');
select lives_ok($$ insert into public.profiles (type, handle, display_name, preferred_language)
                   values ('business', 'swahili_biz', 'T', 'sw') $$,
  'preferred_language sw is accepted');
select throws_ok($$ insert into public.profiles (type, handle, display_name, dot_colour)
                    values ('business', 'pink_biz', 'T', 'pink') $$,
  '22P02', null, 'a dot colour outside the palette is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name, theme)
                    values ('business', 'array_theme', 'T', '[]'::jsonb) $$,
  '23514', null, 'a theme that is not a json object is rejected');

-- ---------------------------------------------------------------------------------------------
-- Length boundaries and tags (Req 4.13, 4.14).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('business', 'empty_name', '') $$,
  '23514', null, 'an empty display name is rejected');
select lives_ok($$ insert into public.profiles (type, handle, display_name)
                   values ('business', 'name_80', repeat('n', 80)) $$,
  'an 80 character display name is accepted');
select throws_ok($$ insert into public.profiles (type, handle, display_name)
                    values ('business', 'name_81', repeat('n', 81)) $$,
  '23514', null, 'an 81 character display name is rejected');
select lives_ok($$ insert into public.profiles (type, handle, display_name, bio)
                   values ('business', 'bio_1000', 'T', repeat('b', 1000)) $$,
  'a 1000 character bio is accepted');
select throws_ok($$ insert into public.profiles (type, handle, display_name, bio)
                    values ('business', 'bio_1001', 'T', repeat('b', 1001)) $$,
  '23514', null, 'a 1001 character bio is rejected');
select lives_ok($$ insert into public.profiles (type, handle, display_name, what_i_do)
                   values ('business', 'tags_norm', 'T', array['  Founder ', 'founder', '', 'Plumber']) $$,
  'tags with spaces, capitals, duplicates and blanks are accepted');
select is((select what_i_do from public.profiles where handle = 'tags_norm'), array['founder', 'plumber'],
  'tags are trimmed, lowercased, deduplicated and blanks dropped, in first seen order');
select lives_ok($$ insert into public.profiles (type, handle, display_name, what_i_do)
                   values ('business', 'tags_20', 'T', array(select 't' || g from generate_series(1, 20) g)) $$,
  '20 tags are accepted');
select throws_ok($$ insert into public.profiles (type, handle, display_name, what_i_do)
                    values ('business', 'tags_21', 'T', array(select 't' || g from generate_series(1, 21) g)) $$,
  '23514', null, '21 tags are rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name, what_i_do)
                    values ('business', 'tag_41', 'T', array[repeat('t', 41)]) $$,
  '23514', null, 'a 41 character tag is rejected');

-- ---------------------------------------------------------------------------------------------
-- Avatar and cover path kinds: <profile id>/avatar/... and <profile id>/cover/... (Req 4.1).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.profiles (id, type, handle, display_name, avatar_path, cover_path)
                   values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'business', 'paths_biz', 'T',
                           'cccccccc-cccc-4ccc-8ccc-cccccccccccc/avatar/a.png',
                           'cccccccc-cccc-4ccc-8ccc-cccccccccccc/cover/c.jpg') $$,
  'avatar and cover paths under the profile id with the right kind are accepted');
select throws_ok($$ update public.profiles set avatar_path = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc/cover/a.png'
                    where handle = 'paths_biz' $$,
  '23514', null, 'an avatar path with the cover kind is rejected');
select throws_ok($$ update public.profiles set cover_path = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc/avatar/c.jpg'
                    where handle = 'paths_biz' $$,
  '23514', null, 'a cover path with the avatar kind is rejected');
select throws_ok($$ update public.profiles set avatar_path = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/avatar/a.png'
                    where handle = 'paths_biz' $$,
  '23514', null, 'an avatar path under another profile id is rejected');
select throws_ok($$ update public.profiles set cover_path = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/cover/c.jpg'
                    where handle = 'paths_biz' $$,
  '23514', null, 'a cover path under another profile id is rejected');

-- ---------------------------------------------------------------------------------------------
-- One person profile per login (Req 5.1, 5.2).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.profiles (type, owner_user_id, handle, display_name)
                    values ('person', '11111111-1111-4111-8111-111111111111', 'amina_two', 'T') $$,
  '23505', null, 'a second person profile for the same login is rejected');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('person', 'no_owner', 'T') $$,
  '23514', null, 'a person profile without an owner login is rejected');

-- ---------------------------------------------------------------------------------------------
-- Column grants: public fields readable by anon and authenticated, private fields by neither
-- (Req 4.15, 4.16, 22.5, 22.7).
-- ---------------------------------------------------------------------------------------------
select ok(has_column_privilege(r, 'public.profiles', c, 'SELECT'), r || ' can select profiles.' || c)
from unnest(array[
  'id', 'type', 'handle', 'display_name', 'bio', 'avatar_path', 'cover_path', 'city', 'country',
  'dot_colour', 'theme', 'what_i_do', 'created_at', 'updated_at'
]) as c
cross join unnest(array['anon', 'authenticated']) as r;
select ok(not has_column_privilege(r, 'public.profiles', c, 'SELECT'), r || ' cannot select profiles.' || c)
from unnest(array['owner_user_id', 'preferred_language', 'mode_2006', 'tags_text', 'search_tsv']) as c
cross join unnest(array['anon', 'authenticated']) as r;
select ok(not has_table_privilege('anon', 'public.profiles', p), 'anon has no ' || p || ' on profiles')
from unnest(array['INSERT', 'UPDATE', 'DELETE']) as p;

-- Reserve Amina's existing handle after the fact (Req 4.4, 4.6).
insert into public.reserved_handles (word) values ('amina_k');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Amina, in the canary order (DR-1, D-8).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-1111-4111-8111-111111111111', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Amina claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-1111-4111-8111-111111111111'::uuid, 'auth.uid() is Amina');
-- acts_as (Req 7.4, 7.6).
select ok(public.acts_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'acts_as is true for Amina''s own profile');
select ok(not public.acts_as('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 'acts_as is false for Brian''s profile');
select ok(not public.acts_as(gen_random_uuid()), 'acts_as is false for a missing profile id');
select ok(not public.acts_as(null), 'acts_as is false for a null profile id');
-- Public fields readable, private fields not (Req 4.15, 4.16).
select isnt_empty($$ select handle, display_name from public.profiles
                     where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  'authenticated can read public profile fields');
select throws_ok($$ select preferred_language from public.profiles $$, '42501', null,
  'authenticated cannot select preferred_language');
select throws_ok($$ select mode_2006 from public.profiles $$, '42501', null,
  'authenticated cannot select mode_2006');
select throws_ok($$ select owner_user_id from public.profiles $$, '42501', null,
  'authenticated cannot select owner_user_id');
select is((select m.preferred_language from public.my_profiles() m
           where m.profile_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'en',
  'Amina reads her own preferred_language through my_profiles');
-- A handle reserved later never blocks other updates, but cannot be changed to a reserved word (Req 4.4).
select lives_ok($$ update public.profiles set display_name = 'Amina K', bio = 'Founder in Nairobi'
                   where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'a profile whose handle became reserved can still update display_name and bio');
select is((select display_name from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'Amina K',
  'the display_name update was applied');
select throws_ok($$ update public.profiles set handle = 'admin'
                    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'PT422', 'profile.handle_reserved', 'changing a handle to a reserved word is rejected');
select throws_ok($$ update public.profiles set handle = 'Amina_K'
                    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '23514', null, 'changing a handle to one with capitals is rejected');
select is((select handle from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'amina_k',
  'the handle was not rewritten');
-- One person per login through the API (Req 5.4).
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('person', 'amina_again', 'T') $$,
  '23505', null, 'a login that owns a person profile cannot create a second one');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Chris, who has no profile yet (Req 5.3).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '33333333-3333-4333-8333-333333333333', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Chris claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '33333333-3333-4333-8333-333333333333'::uuid, 'auth.uid() is Chris');
select lives_ok($$ insert into public.profiles (type, handle, display_name) values ('person', 'chris', 'Chris') $$,
  'a login without a person profile can create one');
set local role postgres;
select is((select owner_user_id from public.profiles where handle = 'chris'),
  '33333333-3333-4333-8333-333333333333'::uuid, 'the new person profile is owned by the signed in login');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor (Req 7.5, 22.5).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');
select ok(not public.acts_as('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 'acts_as is false for anon');
select isnt_empty($$ select handle, display_name, what_i_do from public.profiles
                     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'anon can read public profile fields');
select throws_ok($$ select preferred_language from public.profiles $$, '42501', null,
  'anon cannot select preferred_language');
select throws_ok($$ insert into public.profiles (type, handle, display_name) values ('person', 'anon_try', 'T') $$,
  '42501', null, 'anon cannot insert a profile');
select throws_ok($$ update public.profiles set display_name = 'x' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null, 'anon cannot update a profile');
select throws_ok($$ delete from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null, 'anon cannot delete a profile');

set local role postgres;
select * from finish();
rollback;
