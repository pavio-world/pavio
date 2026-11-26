-- Vouches and Top 8: the vouch RPCs, eligibility, author and subject rights, the Top 8 rules and
-- the vouch_received notification (Spec 00, Req 14.5 to 14.18, 14.21, 14.23, 15.10, 25.1 to 25.4;
-- NQ-2; DR-1).
-- The RPC part comes first (task 16). Page listings of hidden vouches (task 20) and Search_Trust
-- (task 22) add their own sections below, each with its own fixtures, and raise the plan count.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(127);

-- =============================================================================================
-- Vouch RPCs, eligibility, rights and Top 8 (task 16)
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- People: Ada, Ben, Cal, Dot (a stranger to Ada), Eve (owns the business Cafe), Fin (follows
-- Cafe), Gus (owns the business Mill).
-- Accepted connections: Ada and Ben, Ada and Cal, Ben and Cal, Cafe and Mill.
-- Pending: Ada asked Dot. Fin follows Cafe.
-- Circles: Ada's inner (Ben), Ben's mates (Ada).
-- Vouches: 01 Ada about Ben, 02 Ada about Cal, 03 Ben about Ada, all public.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('08080808-0000-4000-8000-000000000001', 'ada.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000002', 'ben.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000003', 'cal.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000004', 'dot.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000005', 'eve.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000006', 'fin.vt@example.invalid'),
  ('08080808-0000-4000-8000-000000000007', 'gus.vt@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('08b00000-0000-4000-8000-000000000001', 'person', '08080808-0000-4000-8000-000000000001', 'ada_vt', 'Ada'),
  ('08b00000-0000-4000-8000-000000000002', 'person', '08080808-0000-4000-8000-000000000002', 'ben_vt', 'Ben'),
  ('08b00000-0000-4000-8000-000000000003', 'person', '08080808-0000-4000-8000-000000000003', 'cal_vt', 'Cal'),
  ('08b00000-0000-4000-8000-000000000004', 'person', '08080808-0000-4000-8000-000000000004', 'dot_vt', 'Dot'),
  ('08b00000-0000-4000-8000-000000000005', 'person', '08080808-0000-4000-8000-000000000005', 'eve_vt', 'Eve'),
  ('08b00000-0000-4000-8000-000000000006', 'person', '08080808-0000-4000-8000-000000000006', 'fin_vt', 'Fin'),
  ('08b00000-0000-4000-8000-000000000007', 'person', '08080808-0000-4000-8000-000000000007', 'gus_vt', 'Gus');
insert into public.profiles (id, type, handle, display_name) values
  ('08b00000-0000-4000-8000-000000000011', 'business', 'cafe_vt', 'Eve''s Cafe'),
  ('08b00000-0000-4000-8000-000000000012', 'business', 'mill_vt', 'Gus''s Mill');
insert into public.profile_managers (profile_id, user_id, role) values
  ('08b00000-0000-4000-8000-000000000011', '08080808-0000-4000-8000-000000000005', 'owner'),
  ('08b00000-0000-4000-8000-000000000012', '08080808-0000-4000-8000-000000000007', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('08b00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000002', 'connection'),
  ('08b00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000003', 'connection'),
  ('08b00000-0000-4000-8000-000000000002', '08b00000-0000-4000-8000-000000000003', 'connection'),
  ('08b00000-0000-4000-8000-000000000011', '08b00000-0000-4000-8000-000000000012', 'connection'),
  ('08b00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000004', 'connection'),
  ('08b00000-0000-4000-8000-000000000006', '08b00000-0000-4000-8000-000000000011', 'follow');
update public.relationships set status = 'accepted'
where type = 'connection'
  and target_profile_id <> '08b00000-0000-4000-8000-000000000004'
  and requester_profile_id in ('08b00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000002',
                               '08b00000-0000-4000-8000-000000000011');
insert into public.circles (id, owner_profile_id, private_name) values
  ('08c00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000001', 'inner'),
  ('08c00000-0000-4000-8000-000000000002', '08b00000-0000-4000-8000-000000000002', 'mates');
insert into public.circle_members (circle_id, member_profile_id) values
  ('08c00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000002'),
  ('08c00000-0000-4000-8000-000000000002', '08b00000-0000-4000-8000-000000000001');
insert into public.vouches (id, author_profile_id, subject_profile_id, body) values
  ('08f00000-0000-4000-8000-000000000001', '08b00000-0000-4000-8000-000000000001',
   '08b00000-0000-4000-8000-000000000002', 'Ben builds things that last'),
  ('08f00000-0000-4000-8000-000000000002', '08b00000-0000-4000-8000-000000000001',
   '08b00000-0000-4000-8000-000000000003', 'Cal tells the truth'),
  ('08f00000-0000-4000-8000-000000000003', '08b00000-0000-4000-8000-000000000002',
   '08b00000-0000-4000-8000-000000000001', 'Ada keeps her word');
select is((select count(*)::int from public.relationships
           where status = 'accepted' and type = 'connection'
             and requester_profile_id::text like '08b%'), 4, 'four accepted connections in the fixtures');

-- ---------------------------------------------------------------------------------------------
-- Catalog: the six RPCs and the notification trigger (Req 22.3; DR-4, function execute grants).
-- ---------------------------------------------------------------------------------------------
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array[
  'public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid)',
  'public.create_vouch(uuid, uuid, text, public.audience, uuid[])',
  'public.set_item_audience(uuid, public.audience, uuid[])',
  'public.item_audience(uuid)',
  'public.set_top8(uuid, uuid[])',
  'public.my_received_vouches(uuid)',
  'private.vouches_after_insert()'
]) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array[
  'public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid)',
  'public.create_vouch(uuid, uuid, text, public.audience, uuid[])',
  'public.set_item_audience(uuid, public.audience, uuid[])',
  'public.item_audience(uuid)',
  'public.set_top8(uuid, uuid[])',
  'public.my_received_vouches(uuid)',
  'private.vouches_after_insert()'
]) as f;
-- Execute for authenticated only (revoked from public and anon).
select ok(has_function_privilege('authenticated', f, 'execute'), 'authenticated can execute ' || f)
from unnest(array[
  'public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid)',
  'public.create_vouch(uuid, uuid, text, public.audience, uuid[])',
  'public.set_item_audience(uuid, public.audience, uuid[])',
  'public.item_audience(uuid)',
  'public.set_top8(uuid, uuid[])',
  'public.my_received_vouches(uuid)'
]) as f;
select ok(not has_function_privilege(r, f, 'execute'), r || ' cannot execute ' || f)
from unnest(array[
  'public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid)',
  'public.create_vouch(uuid, uuid, text, public.audience, uuid[])',
  'public.set_item_audience(uuid, public.audience, uuid[])',
  'public.item_audience(uuid)',
  'public.set_top8(uuid, uuid[])',
  'public.my_received_vouches(uuid)'
]) as f
cross join unnest(array['public', 'anon']) as r;
select ok(not has_function_privilege(r, 'private.vouches_after_insert()', 'execute'),
  r || ' cannot execute private.vouches_after_insert')
from unnest(array['public', 'anon', 'authenticated']) as r;
select trigger_is('public', 'vouches', 'vouches_after_insert', 'private', 'vouches_after_insert',
  'vouches_after_insert calls private.vouches_after_insert');
select volatility_is('public', f, a, v, 'public.' || f || ' is ' || v)
from (values ('item_audience', array['uuid'], 'stable'),
             ('my_received_vouches', array['uuid'], 'stable'),
             ('set_top8', array['uuid', 'uuid[]'], 'volatile')) as x(f, a, v);

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ada.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '08080808-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ada claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '08080808-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ada');

-- Eligibility (Req 14.5 to 14.9).
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000001', 'me') $$,
  'PT422', 'vouch.self', 'Ada cannot vouch for herself (Req 14.5)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000004', 'Dot is fine') $$,
  'PT422', 'vouch.not_eligible', 'a pending connection is not enough to vouch (Req 14.7)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000011', 'good coffee') $$,
  'PT422', 'vouch.not_eligible', 'a person who does not follow a business cannot vouch for it (Req 14.7)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000002', 'again') $$,
  '23505', null, 'one vouch per author and subject (Req 14.9)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000002',
                                               '08b00000-0000-4000-8000-000000000003', 'as Ben') $$,
  'PT403', 'acting.not_allowed', 'Ada cannot vouch as Ben (Req 14.7)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000003', 'x', 'group') $$,
  '23514', null, 'a vouch cannot take the group audience (D-5)');

-- Author rights (Req 14.11): edit text, change audience, delete.
select lives_ok($$ update public.vouches set body = 'Ben builds things that last, and fixes them'
                   where id = '08f00000-0000-4000-8000-000000000001' $$,
  'the author can edit her vouch');
select lives_ok($$ select public.set_item_audience('08f00000-0000-4000-8000-000000000002', 'connections') $$,
  'the author can change her vouch''s audience');
select results_eq($$ select audience::text, circle_ids from public.item_audience('08f00000-0000-4000-8000-000000000002') $$,
  $$ values ('connections'::text, '{}'::uuid[]) $$, 'item_audience shows the author the new audience');
select throws_ok($$ select public.set_item_audience('08f00000-0000-4000-8000-000000000002', 'circles',
                                                    array['08c00000-0000-4000-8000-000000000002'::uuid]) $$,
  'PT422', 'audience.circle_not_owned', 'a vouch cannot be linked to a circle the author does not own (Req 14.12)');
select lives_ok($$ do $d$ begin
                     perform public.set_item_audience('08f00000-0000-4000-8000-000000000002', 'circles',
                                                      array['08c00000-0000-4000-8000-000000000001'::uuid]);
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'the author can move her vouch to her own circle, checked at commit');
select results_eq($$ select audience::text, circle_ids from public.item_audience('08f00000-0000-4000-8000-000000000002') $$,
  $$ values ('circles'::text, array['08c00000-0000-4000-8000-000000000001'::uuid]) $$,
  'item_audience shows the author her own circle link');
select throws_ok($$ update public.vouches set hidden_by_subject = true
                    where id = '08f00000-0000-4000-8000-000000000001' $$,
  'PT403', 'vouch.subject_only', 'the author cannot hide her vouch (Req 14.15)');
select throws_ok($$ update public.vouches set body = 'Ada is perfect'
                    where id = '08f00000-0000-4000-8000-000000000003' $$,
  'PT403', 'vouch.author_only', 'the subject cannot edit a vouch about her (Req 14.14)');
select lives_ok($$ delete from public.vouches where id = '08f00000-0000-4000-8000-000000000003' $$,
  'the subject''s delete of a vouch about her runs but touches nothing (Req 14.14)');
select throws_ok($$ select public.set_item_audience('08f00000-0000-4000-8000-000000000003', 'connections') $$,
  'PT404', 'content.not_found', 'the subject cannot change a vouch''s audience');
select is_empty($$ select * from public.item_audience('08f00000-0000-4000-8000-000000000003') $$,
  'item_audience returns nothing to the subject');

-- Top 8 (Req 14.16 to 14.18).
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000001',
                                           array(select gen_random_uuid() from generate_series(1, 9))) $$,
  'PT422', 'vouch.top8_full', 'a Top 8 of nine is rejected (Req 14.16)');
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000001',
                                           array['08f00000-0000-4000-8000-000000000001'::uuid,
                                                 '08f00000-0000-4000-8000-000000000001'::uuid]) $$,
  'PT422', 'vouch.top8_duplicate', 'the same vouch twice is rejected (Req 14.17)');
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000001',
                                           array['08f00000-0000-4000-8000-000000000003'::uuid]) $$,
  'PT422', 'vouch.top8_not_author', 'a vouch Ada did not write cannot be in her Top 8');
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000002',
                                           array['08f00000-0000-4000-8000-000000000003'::uuid]) $$,
  'PT403', 'acting.not_allowed', 'Ada cannot set Ben''s Top 8');
select lives_ok($$ do $d$ begin
                     perform public.set_top8('08b00000-0000-4000-8000-000000000001',
                                             array['08f00000-0000-4000-8000-000000000001'::uuid,
                                                   '08f00000-0000-4000-8000-000000000002'::uuid]);
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'Ada features two vouches');
select results_eq($$ select id, top8_position::int from public.vouches
                     where author_profile_id = '08b00000-0000-4000-8000-000000000001' order by id $$,
  $$ values ('08f00000-0000-4000-8000-000000000001'::uuid, 1), ('08f00000-0000-4000-8000-000000000002'::uuid, 2) $$,
  'positions follow the order of the list');
select lives_ok($$ do $d$ begin
                     perform public.set_top8('08b00000-0000-4000-8000-000000000001',
                                             array['08f00000-0000-4000-8000-000000000002'::uuid,
                                                   '08f00000-0000-4000-8000-000000000001'::uuid]);
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'swapping two featured vouches in one call passes at commit (Req 14.18)');
select results_eq($$ select id, top8_position::int from public.vouches
                     where author_profile_id = '08b00000-0000-4000-8000-000000000001' order by id $$,
  $$ values ('08f00000-0000-4000-8000-000000000001'::uuid, 2), ('08f00000-0000-4000-8000-000000000002'::uuid, 1) $$,
  'the swap took effect');
select lives_ok($$ do $d$ begin
                     perform public.set_top8('08b00000-0000-4000-8000-000000000001',
                                             array['08f00000-0000-4000-8000-000000000001'::uuid]);
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'replacing the Top 8 with a shorter list passes');
select results_eq($$ select id, top8_position::int from public.vouches
                     where author_profile_id = '08b00000-0000-4000-8000-000000000001' order by id $$,
  $$ values ('08f00000-0000-4000-8000-000000000001'::uuid, 1), ('08f00000-0000-4000-8000-000000000002'::uuid, null) $$,
  'a vouch left out of the list is unfeatured');
select throws_ok($$ do $d$ begin
                      update public.vouches set top8_position = 1
                      where id = '08f00000-0000-4000-8000-000000000002';
                      set constraints all immediate;
                    end $d$ $$,
  '23505', null, 'two featured vouches at one position are rejected at commit (Req 14.17)');
set constraints all deferred;
select throws_ok($$ update public.vouches set top8_position = 9 where id = '08f00000-0000-4000-8000-000000000002' $$,
  '23514', null, 'a Top 8 position above 8 is rejected (Req 14.17)');

-- my_received_vouches needs acts_as on the subject (Req 14.21).
select results_eq($$ select vouch_id, author_profile_id, hidden_by_subject
                     from public.my_received_vouches('08b00000-0000-4000-8000-000000000001') $$,
  $$ values ('08f00000-0000-4000-8000-000000000003'::uuid, '08b00000-0000-4000-8000-000000000002'::uuid, false) $$,
  'Ada reads the vouches she received');
select throws_ok($$ select * from public.my_received_vouches('08b00000-0000-4000-8000-000000000002') $$,
  'PT403', 'acting.not_allowed', 'Ada cannot read Ben''s received vouches');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Cal, the subject of vouch 02: hides it, cannot edit or delete it (Req 14.13, 14.14).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '08080808-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Cal claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '08080808-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Cal');

select lives_ok($$ update public.vouches set hidden_by_subject = true
                   where id = '08f00000-0000-4000-8000-000000000002' $$,
  'the subject can hide a vouch about him (Req 14.13)');
select results_eq($$ select vouch_id, body, hidden_by_subject
                     from public.my_received_vouches('08b00000-0000-4000-8000-000000000003') $$,
  $$ values ('08f00000-0000-4000-8000-000000000002'::uuid, 'Cal tells the truth'::text, true) $$,
  'the hidden vouch is still readable by its subject (Req 14.21)');
select throws_ok($$ update public.vouches set body = 'Cal is a legend'
                    where id = '08f00000-0000-4000-8000-000000000002' $$,
  'PT403', 'vouch.author_only', 'the subject cannot edit the text (Req 14.14)');
select throws_ok($$ update public.vouches set top8_position = 3
                    where id = '08f00000-0000-4000-8000-000000000002' $$,
  'PT403', 'vouch.author_only', 'the subject cannot feature the vouch (Req 14.14)');
select throws_ok($$ update public.vouches set audience = 'public'
                    where id = '08f00000-0000-4000-8000-000000000002' $$,
  'PT403', 'vouch.author_only', 'the subject cannot change the audience (Req 14.14)');
select lives_ok($$ delete from public.vouches where id = '08f00000-0000-4000-8000-000000000002' $$,
  'the subject''s delete runs but touches nothing (Req 14.14)');
select throws_ok($$ select public.set_item_audience('08f00000-0000-4000-8000-000000000002', 'public') $$,
  'PT404', 'content.not_found', 'the subject cannot use set_item_audience on the vouch');
select is_empty($$ select * from public.item_audience('08f00000-0000-4000-8000-000000000002') $$,
  'item_audience returns nothing to the subject, so the author''s circle stays silent (D-3)');
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000003',
                                           array['08f00000-0000-4000-8000-000000000002'::uuid]) $$,
  'PT422', 'vouch.top8_not_author', 'the subject cannot feature a vouch about him in his own Top 8');

-- Cal vouches for Ben with no audience: public by default (NQ-2, Req 14.10).
select lives_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000003',
                                              '08b00000-0000-4000-8000-000000000002',
                                              'Ben fixes everything quietly') $$,
  'Cal vouches for Ben, a connection of the same type (Req 14.7)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ben: circle links must be the author's own (Req 14.12, 11.7).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '08080808-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ben claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '08080808-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Ben');

select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000002',
                                               '08b00000-0000-4000-8000-000000000003', 'Cal is steady',
                                               'circles', array['08c00000-0000-4000-8000-000000000001'::uuid]) $$,
  'PT422', 'audience.circle_not_owned', 'Ben cannot share a vouch with Ada''s circle (Req 14.12)');
select throws_ok($$ do $d$ begin
                      perform public.create_vouch('08b00000-0000-4000-8000-000000000002',
                                                  '08b00000-0000-4000-8000-000000000003', 'Cal is steady',
                                                  'circles', null);
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'a circles vouch with no circle is rejected at commit (Req 11.7)');
set constraints all deferred;
select is_empty($$ select 1 from public.vouches
                   where author_profile_id = '08b00000-0000-4000-8000-000000000002'
                     and subject_profile_id = '08b00000-0000-4000-8000-000000000003' $$,
  'the rejected calls left no vouch behind');
select lives_ok($$ do $d$ begin
                     perform public.create_vouch('08b00000-0000-4000-8000-000000000002',
                                                 '08b00000-0000-4000-8000-000000000003', 'Cal is steady',
                                                 'circles', array['08c00000-0000-4000-8000-000000000002'::uuid,
                                                                  '08c00000-0000-4000-8000-000000000002'::uuid]);
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'Ben shares a vouch with his own circle; a repeated circle id is linked once');
select results_eq($$ select audience::text, circle_ids from public.item_audience(
                       (select id from public.vouches
                        where author_profile_id = '08b00000-0000-4000-8000-000000000002'
                          and subject_profile_id = '08b00000-0000-4000-8000-000000000003')) $$,
  $$ values ('circles'::text, array['08c00000-0000-4000-8000-000000000002'::uuid]) $$,
  'the vouch and its link were created in one call');
select ok(public.can_view((select id from public.vouches
                           where author_profile_id = '08b00000-0000-4000-8000-000000000002'
                             and subject_profile_id = '08b00000-0000-4000-8000-000000000003'),
                          '08b00000-0000-4000-8000-000000000002'),
  'Ben sees his circle vouch');
select results_eq($$ select author_profile_id, body, hidden_by_subject
                     from public.my_received_vouches('08b00000-0000-4000-8000-000000000002') order by body $$,
  $$ values ('08b00000-0000-4000-8000-000000000001'::uuid, 'Ben builds things that last, and fixes them'::text, false),
            ('08b00000-0000-4000-8000-000000000003'::uuid, 'Ben fixes everything quietly'::text, false) $$,
  'Ben reads both vouches he received');
-- Third party rights: Ben is neither author nor subject of vouch 02.
select lives_ok($$ update public.vouches set body = 'taken over' where id = '08f00000-0000-4000-8000-000000000002' $$,
  'a third party''s update runs but touches nothing');
select lives_ok($$ delete from public.vouches where id = '08f00000-0000-4000-8000-000000000002' $$,
  'a third party''s delete runs but touches nothing');
-- The author deletes his circle vouch; its link goes with it and the last link check passes.
select lives_ok($$ do $d$ begin
                     delete from public.vouches
                     where author_profile_id = '08b00000-0000-4000-8000-000000000002'
                       and subject_profile_id = '08b00000-0000-4000-8000-000000000003';
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'the author can delete his vouch (Req 14.11)');
select is_empty($$ select 1 from public.vouches
                   where author_profile_id = '08b00000-0000-4000-8000-000000000002'
                     and subject_profile_id = '08b00000-0000-4000-8000-000000000003' $$,
  'the deleted vouch is gone');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Fin, a follower of Cafe, and as Eve, who owns Cafe (Req 14.6 to 14.8).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '08080808-0000-4000-8000-000000000006', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fin claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '08080808-0000-4000-8000-000000000006'::uuid, 'auth.uid() is Fin');

select lives_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000006',
                                              '08b00000-0000-4000-8000-000000000011', 'best coffee in town') $$,
  'a person who follows a business can vouch for it (Req 14.7)');

set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '08080808-0000-4000-8000-000000000005', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Eve claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '08080808-0000-4000-8000-000000000005'::uuid, 'auth.uid() is Eve');

select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000005',
                                               '08b00000-0000-4000-8000-000000000011', 'my own cafe') $$,
  'PT422', 'vouch.managed_page', 'Eve cannot vouch for the business she manages (Req 14.6)');
select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000011',
                                               '08b00000-0000-4000-8000-000000000006', 'loyal customer') $$,
  'PT422', 'vouch.business_to_person', 'a business cannot vouch for a person (Req 14.8)');
select lives_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000011',
                                              '08b00000-0000-4000-8000-000000000012', 'reliable flour supplier') $$,
  'a business can vouch for a connected business (Req 14.7)');
select results_eq($$ select author_profile_id from public.my_received_vouches('08b00000-0000-4000-8000-000000000011') $$,
  $$ values ('08b00000-0000-4000-8000-000000000006'::uuid) $$,
  'Eve reads the vouches Cafe received, acting as Cafe');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no vouch RPC is callable (DR-4).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select public.create_vouch('08b00000-0000-4000-8000-000000000001',
                                               '08b00000-0000-4000-8000-000000000003', 'x') $$,
  '42501', null, 'anon cannot execute create_vouch');
select throws_ok($$ select public.set_top8('08b00000-0000-4000-8000-000000000001', '{}') $$,
  '42501', null, 'anon cannot execute set_top8');
select throws_ok($$ select * from public.my_received_vouches('08b00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot execute my_received_vouches');

-- ---------------------------------------------------------------------------------------------
-- Back to the test owner: final state and the vouch_received notifications (Req 14.23, 15.10).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);
select results_eq($$ select body, hidden_by_subject, top8_position from public.vouches
                     where id = '08f00000-0000-4000-8000-000000000002' $$,
  $$ values ('Cal tells the truth'::text, true, null::smallint) $$,
  'the subject and the third party changed nothing but the hidden flag');
select ok(exists (select 1 from public.vouches where id = '08f00000-0000-4000-8000-000000000003'),
  'the subject''s delete removed nothing');
select is((select audience::text from public.vouches
           where author_profile_id = '08b00000-0000-4000-8000-000000000003'
             and subject_profile_id = '08b00000-0000-4000-8000-000000000002'),
  'public', 'create_vouch without an audience gives public (NQ-2, Req 14.10)');
select is((select audience::text from public.vouches
           where author_profile_id = '08b00000-0000-4000-8000-000000000006'),
  'public', 'the follower''s vouch is public too');

select results_eq(
  $$ select n.type::text, n.actor_profile_id, n.reference_id
     from public.notifications n
     where n.recipient_profile_id = '08b00000-0000-4000-8000-000000000002' and n.type = 'vouch_received'
     order by n.created_at, n.reference_id $$,
  $$ select 'vouch_received'::text, v.author_profile_id, v.id from public.vouches v
     where v.subject_profile_id = '08b00000-0000-4000-8000-000000000002'
     order by v.created_at, v.id $$,
  'every vouch about Ben gave him one vouch_received notice, with the author and vouch id (Req 14.23)');
select is((select count(*)::int from public.notifications n
           where n.type = 'vouch_received'
             and n.reference_id in (select v.id from public.vouches v
                                    where v.author_profile_id::text like '08b%')),
  (select count(*)::int from public.vouches v where v.author_profile_id::text like '08b%'),
  'one notice per vouch, and none for the rejected calls');
select is_empty(
  $$ select n.id from public.notifications n
     where n.type = 'vouch_received' and n.recipient_profile_id::text like '08b%'
       and exists (select 1 from pg_catalog.jsonb_object_keys(n.data) k
                   where k not in ('actor_handle', 'actor_display_name', 'actor_type')) $$,
  'vouch_received data holds only the actor handle, display name and type (Req 15.10)');
select is_empty(
  $$ select n.id from public.notifications n
     join public.vouches v on v.id = n.reference_id
     where n.type = 'vouch_received' and n.recipient_profile_id::text like '08b%'
       and (n.data::text like '%' || v.body || '%' or n.data::text like '%mates%') $$,
  'no vouch_received notice holds the vouch body or a circle name (privacy rule 5)');
select is((select n.data ->> 'actor_handle' from public.notifications n
           where n.type = 'vouch_received'
             and n.recipient_profile_id = '08b00000-0000-4000-8000-000000000012'),
  'cafe_vt', 'a business author is named by its own handle');

-- =============================================================================================
-- Hidden vouches on page listings (task 20) and Search_Trust (task 22) are added below.
-- =============================================================================================

select * from finish();
rollback;
