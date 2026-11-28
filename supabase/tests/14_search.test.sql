-- Directory search and search appearances (Spec 00, Req 14.22, 16.6 to 16.10, 24.2, 24.3, 24.5 to
-- 24.10, 25.3; NQ-2, NQ-4, NQ-6; DR-1). Search_Trust (private.search_trust) is tested at the end of
-- 08_vouches_top8.test.sql. The circle name leak test for search_directory is in 09.
-- Fixtures use made up words so that rows already in the hosted database cannot match; every
-- assertion that lists results keeps only the fixture profiles (ids starting 14b).
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(113);

-- =============================================================================================
-- Catalog: tables, policies, grants and function settings (Req 16.9, 22.1 to 22.3, 24.5, 24.9)
-- =============================================================================================
select has_table('public', 'search_appearances', 'search_appearances exists');
select has_table('public', 'search_appearance_marks', 'search_appearance_marks exists');
select columns_are('public', 'search_appearances',
  array['id', 'profile_id', 'appeared_on', 'count', 'created_at', 'updated_at'],
  'search_appearances has exactly its six columns (Req 16.6)');
select columns_are('public', 'search_appearance_marks',
  array['id', 'searcher_profile_id', 'profile_id', 'appeared_on', 'created_at'],
  'search_appearance_marks has exactly its five columns (Req 16.7)');
select ok((select relrowsecurity from pg_class where oid = 'public.search_appearances'::regclass),
  'RLS is enabled on search_appearances');
select ok((select relrowsecurity from pg_class where oid = 'public.search_appearance_marks'::regclass),
  'RLS is enabled on search_appearance_marks');
select policies_are('public', 'search_appearances', array['search_appearances_authenticated_select'],
  'search_appearances has exactly its one policy');
select policies_are('public', 'search_appearance_marks', array[]::text[],
  'search_appearance_marks has no policy');
select table_privs_are('public', 'search_appearances', 'anon', array[]::text[],
  'anon has no privilege on search_appearances (Req 16.9)');
select table_privs_are('public', 'search_appearance_marks', 'anon', array[]::text[],
  'anon has no privilege on search_appearance_marks');
select table_privs_are('public', 'search_appearances', 'authenticated', array['SELECT'],
  'authenticated holds only select on search_appearances (Req 16.10)');
select table_privs_are('public', 'search_appearance_marks', 'authenticated', array[]::text[],
  'authenticated has no privilege on search_appearance_marks');
select col_is_unique('public', 'search_appearances', array['profile_id', 'appeared_on'],
  'one search_appearances row per profile and day (Req 16.6)');
select col_is_unique('public', 'search_appearance_marks',
  array['searcher_profile_id', 'profile_id', 'appeared_on'],
  'one mark per searcher, profile and day (Req 16.7)');

select ok((select prosecdef from pg_catalog.pg_proc
           where oid = 'public.search_directory(text, public.profile_type, text, integer, integer, uuid)'::regprocedure),
  'search_directory is security definer');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
            where oid = 'public.search_directory(text, public.profile_type, text, integer, integer, uuid)'::regprocedure)) c
          where c = 'search_path=""'),
  'search_directory sets an empty search_path');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
            where oid = 'public.search_directory(text, public.profile_type, text, integer, integer, uuid)'::regprocedure)) c
          where c = 'pg_trgm.word_similarity_threshold=0.3'),
  'search_directory sets the word similarity threshold to 0.3 (Req 24.2)');
select ok(has_function_privilege(r,
    'public.search_directory(text, public.profile_type, text, integer, integer, uuid)', 'execute'),
  r || ' can execute search_directory (Req 24.9)')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public',
    'public.search_directory(text, public.profile_type, text, integer, integer, uuid)', 'execute'),
  'public cannot execute search_directory');
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array['public', 'anon', 'authenticated']) as r
cross join unnest(array['private.record_search_appearances(uuid[], uuid)', 'private.search_trust(uuid)']) as f;
-- The returned column set holds public data only (Req 24.5).
select is((select array_agg(t.n order by t.ord)
           from unnest(
                  (select proargnames from pg_catalog.pg_proc
                   where oid = 'public.search_directory(text, public.profile_type, text, integer, integer, uuid)'::regprocedure),
                  (select proargmodes from pg_catalog.pg_proc
                   where oid = 'public.search_directory(text, public.profile_type, text, integer, integer, uuid)'::regprocedure)
                ) with ordinality as t(n, m, ord)
           where t.m = 't'),
  array['profile_id', 'type', 'handle', 'display_name', 'bio', 'avatar_path', 'city', 'country',
        'what_i_do', 'dot_colour', 'category', 'search_trust', 'rank'],
  'search_directory returns public columns only: no owner, language, theme, phone, address or timestamps (Req 24.5)');

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims. User NN owns person profile NN.
-- 01 name, 02 handle, 03 tag and Nairobi, 04 bio, 05 business with a category, 06 city only,
-- 07 and 08 persons and 09 business sharing one tag for the filters, 10 to 13 equal relevance with
-- Search_Trust 2, 1, 0, 0 (handles ordered against trust), 14 and 15 vouch authors,
-- 16 appearance target, 17 and 18 signed in searchers, 19 and 20 pagination.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email)
select ('14140000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'u' || n || '.search@example.invalid'
from generate_series(1, 20) as n;
insert into public.profiles (id, type, owner_user_id, handle, display_name, bio, city, country, what_i_do) values
  ('14b00000-0000-4000-8000-000000000001', 'person', '14140000-0000-4000-8000-000000000001', 'quillon_zq', 'Zephyrine Quillon', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000002', 'person', '14140000-0000-4000-8000-000000000002', 'zorbatron_x', 'Anna Mwangi', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000003', 'person', '14140000-0000-4000-8000-000000000003', 'wk_search', 'Wanjiru Kamau', null, 'Nairobi', 'KE', '{nutritionist}'),
  ('14b00000-0000-4000-8000-000000000004', 'person', '14140000-0000-4000-8000-000000000004', 'bio_sf', 'Otieno Dube', 'Teaches sourdough fermentation workshops', null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000006', 'person', '14140000-0000-4000-8000-000000000006', 'city_only', 'Mwende Njeri', null, 'Lodwar', 'KE', '{}'),
  ('14b00000-0000-4000-8000-000000000007', 'person', '14140000-0000-4000-8000-000000000007', 'zy_p1', 'Pele Ndegwa', null, 'Nairobi', 'KE', '{zymurgist}'),
  ('14b00000-0000-4000-8000-000000000008', 'person', '14140000-0000-4000-8000-000000000008', 'zy_p2', 'Hawa Salim', null, 'Mombasa', 'KE', '{zymurgist}'),
  ('14b00000-0000-4000-8000-000000000010', 'person', '14140000-0000-4000-8000-000000000010', 'tz_rank', 'Tara Zed', null, null, null, '{trustyword}'),
  ('14b00000-0000-4000-8000-000000000011', 'person', '14140000-0000-4000-8000-000000000011', 'tm_rank', 'Tobi Mola', null, null, null, '{trustyword}'),
  ('14b00000-0000-4000-8000-000000000013', 'person', '14140000-0000-4000-8000-000000000013', 'tb_rank', 'Toby Bell', null, null, null, '{trustyword}'),
  ('14b00000-0000-4000-8000-000000000012', 'person', '14140000-0000-4000-8000-000000000012', 'ta_rank', 'Tina Abel', null, null, null, '{trustyword}'),
  ('14b00000-0000-4000-8000-000000000014', 'person', '14140000-0000-4000-8000-000000000014', 'voucher_one', 'Vera One', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000015', 'person', '14140000-0000-4000-8000-000000000015', 'voucher_two', 'Vera Two', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000016', 'person', '14140000-0000-4000-8000-000000000016', 'ap_target', 'Apollo Target', null, null, null, '{appearword}'),
  ('14b00000-0000-4000-8000-000000000017', 'person', '14140000-0000-4000-8000-000000000017', 'searcher_one', 'Sam One', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000018', 'person', '14140000-0000-4000-8000-000000000018', 'searcher_two', 'Sam Two', null, null, null, '{}'),
  ('14b00000-0000-4000-8000-000000000019', 'person', '14140000-0000-4000-8000-000000000019', 'pg_a', 'Page Alpha', null, null, null, '{pageword}'),
  ('14b00000-0000-4000-8000-000000000020', 'person', '14140000-0000-4000-8000-000000000020', 'pg_b', 'Page Bravo', null, null, null, '{pageword}');
insert into public.profiles (id, type, handle, display_name, city, country, what_i_do) values
  ('14b00000-0000-4000-8000-000000000005', 'business', 'hw_search', 'Rift Valley Traders', 'Nakuru', 'KE', '{}'),
  ('14b00000-0000-4000-8000-000000000009', 'business', 'zy_b1', 'Lakeside Brewers', 'Nairobi', 'KE', '{zymurgist}');
insert into public.profile_managers (profile_id, user_id, role) values
  ('14b00000-0000-4000-8000-000000000005', '14140000-0000-4000-8000-000000000005', 'owner'),
  ('14b00000-0000-4000-8000-000000000009', '14140000-0000-4000-8000-000000000009', 'owner');
insert into public.business_details (profile_id, category) values
  ('14b00000-0000-4000-8000-000000000005', 'Hardware wholesaler'),
  ('14b00000-0000-4000-8000-000000000009', 'Brewery');
-- Voucher one is connected to Tara, Tobi and Tina; voucher two to Tara.
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000010', 'connection'),
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000011', 'connection'),
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000012', 'connection'),
  ('14b00000-0000-4000-8000-000000000015', '14b00000-0000-4000-8000-000000000010', 'connection');
update public.relationships set status = 'accepted'
where type = 'connection'
  and requester_profile_id in ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000015');
-- Featured public vouches: Tara has two authors, Tobi one. Tina's featured vouch is for connections
-- only, so it must not count. Tobi's second vouch, from voucher two, does not exist.
insert into public.vouches (author_profile_id, subject_profile_id, body, audience, top8_position) values
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000010', 'Tara delivers', 'public', 1),
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000011', 'Tobi is steady', 'public', 2),
  ('14b00000-0000-4000-8000-000000000015', '14b00000-0000-4000-8000-000000000010', 'Tara is quick', 'public', 1),
  ('14b00000-0000-4000-8000-000000000014', '14b00000-0000-4000-8000-000000000012', 'Tina is kind', 'connections', 3);
select is((select count(*)::int from public.profiles where id::text like '14b%'), 20, 'twenty fixture profiles');

-- =============================================================================================
-- Too short a query returns nothing and records nothing (Req 24.10)
-- =============================================================================================
select set_config('t14.appearances',
  (select coalesce(sum(count), 0)::text from public.search_appearances where profile_id::text like '14b%'), true);
select set_config('t14.marks',
  (select count(*)::text from public.search_appearance_marks where searcher_profile_id::text like '14b%'), true);
select set_config('request.jwt.claims',
  json_build_object('sub', '14140000-0000-4000-8000-000000000017', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the searcher one claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '14140000-0000-4000-8000-000000000017'::uuid, 'auth.uid() is searcher one');
select is_empty($$ select * from public.search_directory('a', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'a one letter query returns nothing');
select is_empty($$ select * from public.search_directory('   ', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'a blank query returns nothing');
select is_empty($$ select * from public.search_directory('', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'an empty query returns nothing');
select is_empty($$ select * from public.search_directory(null, p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'a null query returns nothing');
set local role postgres;
select is((select coalesce(sum(count), 0)::text from public.search_appearances where profile_id::text like '14b%'),
  current_setting('t14.appearances'), 'short queries recorded no appearance');
select is((select count(*)::text from public.search_appearance_marks where searcher_profile_id::text like '14b%'),
  current_setting('t14.marks'), 'short queries recorded no mark');

-- =============================================================================================
-- Signed out visitor: matching, fields, filters, page bounds and ranking (Req 24.2, 24.3, 24.6, 24.7)
-- =============================================================================================
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

-- Typo tolerance (Req 24.2).
select set_eq($$ select profile_id from public.search_directory('nutritonist') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000003'::uuid) $$,
  'a misspelled "nutritonist" finds the nutritionist');
select set_eq($$ select profile_id from public.search_directory('NUTRITIONIST') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000003'::uuid) $$,
  'matching ignores case');

-- Each searched field (Req 24.3).
select set_eq($$ select profile_id from public.search_directory('quillon') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000001'::uuid) $$, 'a display name word finds the profile');
select set_eq($$ select profile_id from public.search_directory('zorbatron') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000002'::uuid) $$, 'a handle finds the profile');
select set_eq($$ select profile_id from public.search_directory('nutritionist') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000003'::uuid) $$, 'a what I do tag finds the profile');
select set_eq($$ select profile_id from public.search_directory('fermentation') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000004'::uuid) $$, 'a word in the public bio finds the profile');
select set_eq($$ select profile_id from public.search_directory('wholesaler') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000005'::uuid) $$, 'a business category finds the business');
select set_eq($$ select profile_id from public.search_directory('lodwar') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000006'::uuid) $$, 'a city finds the profile');
select set_eq($$ select profile_id from public.search_directory('zymurgist nakuru') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000005'::uuid), ('14b00000-0000-4000-8000-000000000007'::uuid),
            ('14b00000-0000-4000-8000-000000000008'::uuid), ('14b00000-0000-4000-8000-000000000009'::uuid) $$,
  'a query of two words matches a profile on either word');

-- The result carries the public fields of the match.
select results_eq($$ select type::text, handle, display_name, city, country, what_i_do, category, search_trust
                     from public.search_directory('wholesaler') where profile_id::text like '14b%' $$,
  $$ values ('business'::text, 'hw_search'::text, 'Rift Valley Traders'::text, 'Nakuru'::text, 'KE'::text,
             '{}'::text[], 'Hardware wholesaler'::text, 0) $$,
  'a business row carries its category and city');

-- Type and city filters (Req 24.6).
select set_eq($$ select profile_id from public.search_directory('zymurgist') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000007'::uuid), ('14b00000-0000-4000-8000-000000000008'::uuid),
            ('14b00000-0000-4000-8000-000000000009'::uuid) $$,
  'with no filter, both types and both cities match');
select set_eq($$ select profile_id from public.search_directory('zymurgist', 'business') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000009'::uuid) $$, 'the type filter keeps businesses');
select set_eq($$ select profile_id from public.search_directory('zymurgist', 'person') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000007'::uuid), ('14b00000-0000-4000-8000-000000000008'::uuid) $$,
  'the type filter keeps persons');
select set_eq($$ select profile_id from public.search_directory('zymurgist', p_city => 'nairobi') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000007'::uuid), ('14b00000-0000-4000-8000-000000000009'::uuid) $$,
  'the city filter keeps one city');
select set_eq($$ select profile_id from public.search_directory('zymurgist', 'person', '  NAIROBI ') where profile_id::text like '14b%' $$,
  $$ values ('14b00000-0000-4000-8000-000000000007'::uuid) $$,
  'the city filter ignores case and outer spaces, and combines with the type filter');
select is_empty($$ select 1 from public.search_directory('zymurgist', p_city => 'Kisumu') where profile_id::text like '14b%' $$,
  'a city with no match returns nothing');

-- Page size bounds (Req 24.7).
select throws_ok($$ select * from public.search_directory('trustyword', p_limit => 0) $$,
  'PT422', 'search.bad_page', 'a page size of 0 is rejected');
select throws_ok($$ select * from public.search_directory('trustyword', p_limit => 51) $$,
  'PT422', 'search.bad_page', 'a page size of 51 is rejected');
select throws_ok($$ select * from public.search_directory('trustyword', p_offset => -1) $$,
  'PT422', 'search.bad_page', 'a negative offset is rejected');
select throws_ok($$ select * from public.search_directory('trustyword', p_limit => null) $$,
  'PT422', 'search.bad_page', 'a null page size is rejected');
select throws_ok($$ select * from public.search_directory('trustyword', p_offset => null) $$,
  'PT422', 'search.bad_page', 'a null offset is rejected');
select lives_ok($$ select * from public.search_directory('trustyword', p_limit => 50) $$, 'a page size of 50 is accepted');
select is((select count(*)::int from public.search_directory('trustyword', p_limit => 1)), 1,
  'a page size of 1 returns one row');

-- Ranking: trust boost, then handle (Req 24.6, 24.7). The four profiles carry the same tag, so
-- their text relevance is equal. Handles run against trust: tz has the most trust, ta and tb none.
select results_eq($$ select handle from public.search_directory('trustyword') where profile_id::text like '14b%' $$,
  $$ values ('tz_rank'::text), ('tm_rank'::text), ('ta_rank'::text), ('tb_rank'::text) $$,
  'more featured public vouches rank higher; equal trust falls back to handle order');
select results_eq($$ select handle, search_trust from public.search_directory('trustyword')
                     where profile_id::text like '14b%' $$,
  $$ values ('tz_rank'::text, 2), ('tm_rank'::text, 1), ('ta_rank'::text, 0), ('tb_rank'::text, 0) $$,
  'search_trust counts featured public vouches only: the connections vouch about Tina is not counted');
select ok((select rank from public.search_directory('trustyword') where handle = 'tz_rank')
        > (select rank from public.search_directory('trustyword') where handle = 'tm_rank')
      and (select rank from public.search_directory('trustyword') where handle = 'tm_rank')
        > (select rank from public.search_directory('trustyword') where handle = 'ta_rank'),
  'rank rises with trust at equal relevance');
select is((select rank from public.search_directory('trustyword') where handle = 'ta_rank'),
          (select rank from public.search_directory('trustyword') where handle = 'tb_rank'),
  'equal relevance and equal trust give equal rank, so only the handle separates them');
select results_eq($$ select handle from public.search_directory('trustyword', p_limit => 1, p_offset => 1) $$,
  $$ values ('tm_rank'::text) $$, 'the offset skips the first ranked row');

-- =============================================================================================
-- Search appearances (Req 16.6 to 16.10; NQ-6)
-- Target Apollo (16) is found with "appearword". Today is the Nairobi day.
-- =============================================================================================
select lives_ok($$ select * from public.search_directory('appearword') $$, 'a signed out search for appearword runs');
select lives_ok($$ select * from public.search_directory('appearword') $$, 'a second signed out search runs');
-- A searcher id that anon does not act as counts as anonymous (Req 24.9).
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'anon naming a searcher profile runs');
-- Paging records the returned page only.
select lives_ok($$ select * from public.search_directory('pageword', p_limit => 1, p_offset => 0) $$,
  'page one of pageword runs');

set local role postgres;
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000016' and appeared_on = private.nairobi_today()),
  3, 'a signed out searcher counts every time, and an untrusted searcher id counts as anonymous (Req 16.8)');
select is((select count(*)::int from public.search_appearance_marks where searcher_profile_id::text like '14b%'),
  current_setting('t14.marks')::int, 'the untrusted searcher id left no mark');
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000019' and appeared_on = private.nairobi_today()),
  1, 'the first page recorded its row');
select is((select count(*)::int from public.search_appearances where profile_id = '14b00000-0000-4000-8000-000000000020'),
  0, 'the profile on the next page recorded nothing yet (Req 16.6)');

-- Signed in as searcher one: once per profile and day (Req 16.7).
select set_config('request.jwt.claims',
  json_build_object('sub', '14140000-0000-4000-8000-000000000017', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the searcher one claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '14140000-0000-4000-8000-000000000017'::uuid, 'auth.uid() is searcher one');
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'searcher one searches as himself');
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'searcher one repeats the search');
-- Naming a profile he does not control counts as anonymous.
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000018') $$,
  'searcher one names searcher two''s profile');
-- Page two of the pagination fixture.
select lives_ok($$ select * from public.search_directory('pageword', p_limit => 1, p_offset => 1) $$,
  'page two of pageword runs');
-- A private table and private functions are out of reach (Req 16.9, 22.2).
select throws_ok($$ select * from public.search_appearance_marks $$, '42501', null,
  'authenticated cannot read search_appearance_marks');
select throws_ok($$ insert into public.search_appearances (profile_id, appeared_on, count)
                    values ('14b00000-0000-4000-8000-000000000017', current_date, 1) $$,
  '42501', null, 'authenticated cannot insert into search_appearances (Req 16.10)');
select throws_ok($$ update public.search_appearances set count = 99 $$, '42501', null,
  'authenticated cannot update search_appearances');
select throws_ok($$ delete from public.search_appearances $$, '42501', null,
  'authenticated cannot delete from search_appearances');
select throws_ok($$ select private.record_search_appearances(array['14b00000-0000-4000-8000-000000000016'::uuid], null) $$,
  '42501', null, 'authenticated cannot call private.record_search_appearances');
select throws_ok($$ select private.search_trust('14b00000-0000-4000-8000-000000000016') $$,
  '42501', null, 'authenticated cannot call private.search_trust');
select is((select count(*)::int from public.search_appearances), 0,
  'searcher one owns no profile that appeared, so he reads no appearance row (Req 16.9)');

set local role postgres;
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000016' and appeared_on = private.nairobi_today()),
  5, 'searcher one counted once for himself, plus one anonymous count for the profile he does not control');
select is((select count(*)::int from public.search_appearance_marks
           where searcher_profile_id = '14b00000-0000-4000-8000-000000000017'
             and profile_id = '14b00000-0000-4000-8000-000000000016'), 1,
  'searcher one holds one mark for Apollo');
select is((select count(*)::int from public.search_appearance_marks
           where searcher_profile_id = '14b00000-0000-4000-8000-000000000018'), 0,
  'naming searcher two''s profile left no mark for searcher two');
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000020' and appeared_on = private.nairobi_today()),
  1, 'page two recorded the profile it returned');
-- A new Nairobi day counts again: move the existing mark back one day.
update public.search_appearance_marks set appeared_on = appeared_on - 1
where searcher_profile_id = '14b00000-0000-4000-8000-000000000017';
select set_config('request.jwt.claims',
  json_build_object('sub', '14140000-0000-4000-8000-000000000017', 'role', 'authenticated')::text, true);
set local role authenticated;
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000017') $$,
  'searcher one searches again on a new day');
set local role postgres;
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000016' and appeared_on = private.nairobi_today()),
  6, 'a new Nairobi day counts the same searcher again');
select is((select count(*)::int from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000016' and appeared_on = private.nairobi_today()),
  1, 'there is one row per profile and day');

-- Signed in as searcher two: counted once; a search with no searcher id counts as anonymous.
select set_config('request.jwt.claims',
  json_build_object('sub', '14140000-0000-4000-8000-000000000018', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the searcher two claims');
set local role authenticated;
select is(auth.uid(), '14140000-0000-4000-8000-000000000018'::uuid, 'auth.uid() is searcher two');
select lives_ok($$ select * from public.search_directory('appearword', p_searcher => '14b00000-0000-4000-8000-000000000018') $$,
  'searcher two searches as herself');
select lives_ok($$ select * from public.search_directory('appearword') $$,
  'searcher two searches without naming a searcher profile');
select is((select count(*)::int from public.search_appearances), 0,
  'searcher two reads no appearance row of Apollo (Req 16.9)');
set local role postgres;
select is((select count from public.search_appearances
           where profile_id = '14b00000-0000-4000-8000-000000000016' and appeared_on = private.nairobi_today()),
  8, 'searcher two counted once as herself and once as an anonymous searcher');

-- Apollo's owner reads the appearance row (Req 16.10).
select set_config('request.jwt.claims',
  json_build_object('sub', '14140000-0000-4000-8000-000000000016', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Apollo claims');
set local role authenticated;
select is(auth.uid(), '14140000-0000-4000-8000-000000000016'::uuid, 'auth.uid() is Apollo');
select results_eq($$ select profile_id, count from public.search_appearances $$,
  $$ values ('14b00000-0000-4000-8000-000000000016'::uuid, 8) $$,
  'the owner reads her own appearance count and nothing else (Req 16.10)');

-- Signed out: no read access (Req 16.9).
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select throws_ok($$ select * from public.search_appearances $$, '42501', null,
  'anon cannot read search_appearances (Req 16.9)');
select throws_ok($$ select * from public.search_appearance_marks $$, '42501', null,
  'anon cannot read search_appearance_marks');
select throws_ok($$ insert into public.search_appearances (profile_id, appeared_on, count)
                    values ('14b00000-0000-4000-8000-000000000016', current_date, 1) $$,
  '42501', null, 'anon cannot write search_appearances');
select throws_ok($$ select private.record_search_appearances(array['14b00000-0000-4000-8000-000000000016'::uuid], null) $$,
  '42501', null, 'anon cannot call private.record_search_appearances');

set local role postgres;
select set_config('request.jwt.claims', '', true);

-- Latency (Req 24.12): 50 timed search_directory calls, p95 under 200 ms.
set local role postgres;
select set_config('request.jwt.claims', '', true);
create temp table sd_timings (ms numeric) on commit drop;
do $$
declare t timestamptz;
begin
  for i in 1..50 loop
    t := clock_timestamp();
    perform count(*) from public.search_directory('nutritonist');
    insert into sd_timings values (extract(epoch from clock_timestamp() - t) * 1000);
  end loop;
end $$;
select cmp_ok((select percentile_disc(0.95) within group (order by ms) from sd_timings), '<', 200::numeric,
  'p95 of search_directory over 50 calls is under 200 ms (Req 24.12)');
select * from finish();
rollback;
