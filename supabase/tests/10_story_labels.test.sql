-- Story labels: private.story_label and its public wrapper. No label for the owner, an invisible
-- story or a non-circle audience (NQ-3); member_label only while the switch is on and only to
-- members, from the first circle in Circle_Label_Order; only_for_you when no linked circle holds
-- anyone but the viewer, including an empty linked circle (D-2); shared_with_you otherwise; all
-- followers counted live; switch and membership changes seen at the next call; an untrusted
-- viewer id evaluated as null; and no circle private name in any returned value.
-- Spec 00 Req 13.1 to 13.14, 25.3, 25.7; D-2, NQ-3, DR-1.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(89);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims (a trusted caller, so a story can be back-dated).
-- People: Oli (owner of the stories), Pam, Quin, Rex, Sam (Oli's connections), Tia (a stranger),
-- Uma (owns the business Hub), Vic and Wen. Pam and Vic follow Hub.
-- Oli's circles have distinctive private names (zqx_..._private_77NN) so a leak is detectable,
-- and explicit created_at values so Circle_Label_Order is decided by created_at before id:
--   c00 zqx_golf     on,  "Tie winner",    t+1, Pam          (same created_at as c02, lower id)
--   c01 zqx_alpha    on,  "Close friends", t+3, Pam, Quin
--   c02 zqx_bravo    on,  "Book people",   t+1, Pam
--   c03 zqx_charlie  off, no label,        t+4, Rex
--   c04 zqx_delta    off, no label,        t+5, Pam
--   c05 zqx_echo     off, no label,        t+6, nobody
--   c06 zqx_foxtrot  off, "Kept label",    t+7, Quin        (label kept while the switch is off)
-- Hub's all followers circle is created by the profiles trigger.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('10101010-0000-4000-8000-000000000001', 'oli.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000002', 'pam.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000003', 'quin.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000004', 'rex.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000005', 'sam.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000006', 'tia.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000007', 'uma.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000008', 'vic.sl@example.invalid'),
  ('10101010-0000-4000-8000-000000000009', 'wen.sl@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('10b00000-0000-4000-8000-000000000001', 'person', '10101010-0000-4000-8000-000000000001', 'oli_sl', 'Oli'),
  ('10b00000-0000-4000-8000-000000000002', 'person', '10101010-0000-4000-8000-000000000002', 'pam_sl', 'Pam'),
  ('10b00000-0000-4000-8000-000000000003', 'person', '10101010-0000-4000-8000-000000000003', 'quin_sl', 'Quin'),
  ('10b00000-0000-4000-8000-000000000004', 'person', '10101010-0000-4000-8000-000000000004', 'rex_sl', 'Rex'),
  ('10b00000-0000-4000-8000-000000000005', 'person', '10101010-0000-4000-8000-000000000005', 'sam_sl', 'Sam'),
  ('10b00000-0000-4000-8000-000000000006', 'person', '10101010-0000-4000-8000-000000000006', 'tia_sl', 'Tia'),
  ('10b00000-0000-4000-8000-000000000007', 'person', '10101010-0000-4000-8000-000000000007', 'uma_sl', 'Uma'),
  ('10b00000-0000-4000-8000-000000000008', 'person', '10101010-0000-4000-8000-000000000008', 'vic_sl', 'Vic'),
  ('10b00000-0000-4000-8000-000000000009', 'person', '10101010-0000-4000-8000-000000000009', 'wen_sl', 'Wen');
insert into public.profiles (id, type, handle, display_name) values
  ('10b00000-0000-4000-8000-000000000011', 'business', 'hub_sl', 'Uma''s Hub');
insert into public.profile_managers (profile_id, user_id, role) values
  ('10b00000-0000-4000-8000-000000000011', '10101010-0000-4000-8000-000000000007', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('10b00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002', 'connection'),
  ('10b00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000003', 'connection'),
  ('10b00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000001', 'connection'),
  ('10b00000-0000-4000-8000-000000000005', '10b00000-0000-4000-8000-000000000001', 'connection'),
  ('10b00000-0000-4000-8000-000000000002', '10b00000-0000-4000-8000-000000000011', 'follow'),
  ('10b00000-0000-4000-8000-000000000008', '10b00000-0000-4000-8000-000000000011', 'follow');
update public.relationships set status = 'accepted'
where type = 'connection'
  and '10b00000-0000-4000-8000-000000000001' in (requester_profile_id, target_profile_id);
insert into public.circles (id, owner_profile_id, private_name, show_member_label, member_label, created_at) values
  ('10c00000-0000-4000-8000-000000000000', '10b00000-0000-4000-8000-000000000001', 'zqx_golf_private_7737',
   true, 'Tie winner', '2026-01-01 00:00:01+00'),
  ('10c00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000001', 'zqx_alpha_private_7731',
   true, 'Close friends', '2026-01-01 00:00:03+00'),
  ('10c00000-0000-4000-8000-000000000002', '10b00000-0000-4000-8000-000000000001', 'zqx_bravo_private_7732',
   true, 'Book people', '2026-01-01 00:00:01+00'),
  ('10c00000-0000-4000-8000-000000000003', '10b00000-0000-4000-8000-000000000001', 'zqx_charlie_private_7733',
   false, null, '2026-01-01 00:00:04+00'),
  ('10c00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000001', 'zqx_delta_private_7734',
   false, null, '2026-01-01 00:00:05+00'),
  ('10c00000-0000-4000-8000-000000000005', '10b00000-0000-4000-8000-000000000001', 'zqx_echo_private_7735',
   false, null, '2026-01-01 00:00:06+00'),
  ('10c00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000001', 'zqx_foxtrot_private_7736',
   false, 'Kept label', '2026-01-01 00:00:07+00');
insert into public.circle_members (circle_id, member_profile_id) values
  ('10c00000-0000-4000-8000-000000000000', '10b00000-0000-4000-8000-000000000002'),
  ('10c00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002'),
  ('10c00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000003'),
  ('10c00000-0000-4000-8000-000000000002', '10b00000-0000-4000-8000-000000000002'),
  ('10c00000-0000-4000-8000-000000000003', '10b00000-0000-4000-8000-000000000004'),
  ('10c00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000002'),
  ('10c00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000003');
insert into public.groups (id, owner_profile_id, name) values
  ('10e00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000001', 'reading group');
insert into public.group_members (group_id, profile_id) values
  ('10e00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002');

-- Oli's items (stories unless noted) and their linked circles:
--   d01 c01, c02      d02 c03           d03 c03, c05 (empty)   d04 c04, c03
--   d05 c06           d06 c02, c03      d07 c02, c00           d13 c05 only (empty)
--   d08 public        d09 connections   d10 group              d11 c03, expired
--   d12 a gallery photo with circles c01 (not a story)
-- Hub's story h01 is shared to its all followers circle.
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s01"}'),
  ('10d00000-0000-4000-8000-000000000002', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s02"}'),
  ('10d00000-0000-4000-8000-000000000003', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s03"}'),
  ('10d00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s04"}'),
  ('10d00000-0000-4000-8000-000000000005', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s05"}'),
  ('10d00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s06"}'),
  ('10d00000-0000-4000-8000-000000000007', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s07"}'),
  ('10d00000-0000-4000-8000-000000000008', '10b00000-0000-4000-8000-000000000001', 'story', 'public', '{"text": "s08"}'),
  ('10d00000-0000-4000-8000-000000000009', '10b00000-0000-4000-8000-000000000001', 'story', 'connections', '{"text": "s09"}'),
  ('10d00000-0000-4000-8000-000000000013', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s13"}'),
  ('10d00000-0000-4000-8000-000000000012', '10b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "10b00000-0000-4000-8000-000000000001/gallery/g12.jpg"}'),
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000011', 'story', 'circles', '{"text": "h01"}');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, group_id) values
  ('10d00000-0000-4000-8000-000000000010', '10b00000-0000-4000-8000-000000000001', 'story', 'group', '{"text": "s10"}',
   '10e00000-0000-4000-8000-000000000001');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, created_at) values
  ('10d00000-0000-4000-8000-000000000011', '10b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s11"}',
   now() - interval '25 hours');
insert into public.item_circles (content_item_id, circle_id) values
  ('10d00000-0000-4000-8000-000000000001', '10c00000-0000-4000-8000-000000000001'),
  ('10d00000-0000-4000-8000-000000000001', '10c00000-0000-4000-8000-000000000002'),
  ('10d00000-0000-4000-8000-000000000002', '10c00000-0000-4000-8000-000000000003'),
  ('10d00000-0000-4000-8000-000000000003', '10c00000-0000-4000-8000-000000000003'),
  ('10d00000-0000-4000-8000-000000000003', '10c00000-0000-4000-8000-000000000005'),
  ('10d00000-0000-4000-8000-000000000004', '10c00000-0000-4000-8000-000000000004'),
  ('10d00000-0000-4000-8000-000000000004', '10c00000-0000-4000-8000-000000000003'),
  ('10d00000-0000-4000-8000-000000000005', '10c00000-0000-4000-8000-000000000006'),
  ('10d00000-0000-4000-8000-000000000006', '10c00000-0000-4000-8000-000000000002'),
  ('10d00000-0000-4000-8000-000000000006', '10c00000-0000-4000-8000-000000000003'),
  ('10d00000-0000-4000-8000-000000000007', '10c00000-0000-4000-8000-000000000002'),
  ('10d00000-0000-4000-8000-000000000007', '10c00000-0000-4000-8000-000000000000'),
  ('10d00000-0000-4000-8000-000000000011', '10c00000-0000-4000-8000-000000000003'),
  ('10d00000-0000-4000-8000-000000000012', '10c00000-0000-4000-8000-000000000001'),
  ('10d00000-0000-4000-8000-000000000013', '10c00000-0000-4000-8000-000000000005');
insert into public.item_circles (content_item_id, circle_id)
select '10d00000-0000-4000-8000-000000000021', c.id from public.circles c
where c.owner_profile_id = '10b00000-0000-4000-8000-000000000011' and c.is_all_followers;

select lives_ok($$ set constraints all immediate $$, 'the fixtures pass every deferred check');
set constraints all deferred;

-- ---------------------------------------------------------------------------------------------
-- Catalog (Req 13.1, 13.10, 13.13, 22.3; DR-4).
-- ---------------------------------------------------------------------------------------------
select volatility_is('private', 'story_label', array['uuid', 'uuid'], 'stable', 'private.story_label is stable');
select volatility_is('public', 'story_label', array['uuid', 'uuid'], 'stable', 'public.story_label is stable');
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array['private.story_label(uuid, uuid)', 'public.story_label(uuid, uuid)']) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array['private.story_label(uuid, uuid)', 'public.story_label(uuid, uuid)']) as f;
-- Only a kind and a label come back: no circle id, name, count or member column (Req 13.1, 13.10).
select is(pg_catalog.pg_get_function_result(f::regprocedure), 'TABLE(kind story_label_kind, label text)',
  f || ' returns only kind and label')
from unnest(array['private.story_label(uuid, uuid)', 'public.story_label(uuid, uuid)']) as f;
select ok((select prosrc from pg_catalog.pg_proc where oid = 'private.story_label(uuid, uuid)'::regprocedure)
          like '%private.can_view(p_story_id, p_viewer)%',
  'private.story_label decides visibility through can_view (Req 13.13)');
select ok(has_function_privilege(r, 'public.story_label(uuid, uuid)', 'execute'),
  r || ' can execute public.story_label (D-1)')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public', 'public.story_label(uuid, uuid)', 'execute'),
  'public cannot execute public.story_label');
select ok(not has_function_privilege(r, 'private.story_label(uuid, uuid)', 'execute'),
  r || ' cannot execute private.story_label')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- ---------------------------------------------------------------------------------------------
-- Every case as a trusted caller (Req 13.2 to 13.9; D-2, NQ-3).
-- Each result is one comparable string: null for no row, kind or kind:label for one row, and a
-- comma separated list if more than one row ever came back (which fails the comparison).
-- ---------------------------------------------------------------------------------------------
create temporary table sl_cases (story uuid, viewer uuid, expected text, description text) on commit drop;
insert into sl_cases values
  -- No label for the owner, an invisible story, a missing id or a null viewer (13.2, 13.3).
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000001', null,
   'no label for the owner of a circle story (13.3)'),
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000004', null,
   'no label for a connection outside the linked circles (13.2)'),
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000005', null,
   'no label for a connection in none of the owner''s circles'),
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000006', null,
   'no label for a stranger'),
  ('10d00000-0000-4000-8000-000000000001', null, null, 'no label for a null viewer'),
  ('10d00000-0000-4000-8000-000000000011', '10b00000-0000-4000-8000-000000000004', null,
   'no label on an expired story, even for a member of its circle'),
  ('10d00000-0000-4000-8000-000000000011', '10b00000-0000-4000-8000-000000000001', null,
   'no label for the owner of an expired story'),
  ('10d00000-0000-4000-8000-000000000013', '10b00000-0000-4000-8000-000000000002', null,
   'no label on a story shared only to an empty circle (nobody but the owner sees it)'),
  ('10d00000-0000-4000-8000-0000000000ff', '10b00000-0000-4000-8000-000000000002', null,
   'no label for an id that does not exist'),
  ('10d00000-0000-4000-8000-000000000012', '10b00000-0000-4000-8000-000000000002', null,
   'no label on an item that is not a story, even one shared to circles'),
  -- No label for a non-circle audience (13.7, NQ-3).
  ('10d00000-0000-4000-8000-000000000008', '10b00000-0000-4000-8000-000000000002', null,
   'no label on a public story (NQ-3)'),
  ('10d00000-0000-4000-8000-000000000008', '10b00000-0000-4000-8000-000000000006', null,
   'no label on a public story for a stranger'),
  ('10d00000-0000-4000-8000-000000000008', null, null, 'no label on a public story for a null viewer'),
  ('10d00000-0000-4000-8000-000000000009', '10b00000-0000-4000-8000-000000000002', null,
   'no label on a connections story (NQ-3)'),
  ('10d00000-0000-4000-8000-000000000010', '10b00000-0000-4000-8000-000000000002', null,
   'no label on a group story (NQ-3)'),
  -- member_label from the first switched-on circle holding the viewer, Circle_Label_Order (13.4, 13.9).
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002', 'member_label:Book people',
   'Pam gets the label of the earlier created circle, though the other circle has the lower id (13.4)'),
  ('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000003', 'member_label:Close friends',
   'Quin gets the label of the only switched-on circle that holds her'),
  ('10d00000-0000-4000-8000-000000000007', '10b00000-0000-4000-8000-000000000002', 'member_label:Tie winner',
   'equal created_at falls back to the lower circle id (Circle_Label_Order)'),
  ('10d00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000002', 'member_label:Book people',
   'a member of the switched-on circle gets its label'),
  ('10d00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000004', 'shared_with_you',
   'a viewer outside the switched-on circle never gets its label (13.9)'),
  ('10d00000-0000-4000-8000-000000000005', '10b00000-0000-4000-8000-000000000003', 'only_for_you',
   'a kept member label is not shown while the switch is off (13.9)'),
  -- only_for_you when no linked circle holds anyone but the viewer (13.5, D-2).
  ('10d00000-0000-4000-8000-000000000002', '10b00000-0000-4000-8000-000000000004', 'only_for_you',
   'the only member of the only linked circle gets only_for_you (13.5)'),
  ('10d00000-0000-4000-8000-000000000003', '10b00000-0000-4000-8000-000000000004', 'only_for_you',
   'an empty linked circle does not change only_for_you (D-2)'),
  -- shared_with_you otherwise (13.6).
  ('10d00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000002', 'shared_with_you',
   'another linked circle holds someone else: shared_with_you (13.6)'),
  ('10d00000-0000-4000-8000-000000000004', '10b00000-0000-4000-8000-000000000004', 'shared_with_you',
   'the same story reads shared_with_you for the member of the other circle'),
  -- All followers, counted as the current followers (13.8).
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000002', 'shared_with_you',
   'a follower of a story for all followers, with another follower, gets shared_with_you (13.8)'),
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000008', 'shared_with_you',
   'the other follower also gets shared_with_you'),
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000006', null,
   'a non follower gets no label on a story for all followers'),
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000007', null,
   'the manager''s person profile is not a follower and gets no label'),
  ('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000011', null,
   'the business gets no label on its own story');
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label(c.story, c.viewer) sl),
  c.expected, c.description)
from sl_cases c;
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from private.story_label('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002') sl),
  'member_label:Book people', 'the public wrapper returns the private result for a trusted caller');

-- ---------------------------------------------------------------------------------------------
-- The sweep (Req 13.1, 13.9, 13.10): every fixture item for every fixture viewer and the null
-- viewer. No returned value contains any circle's private name; at most one row per pair; text
-- only on member_label; every label is the member label of a switched-on linked circle holding
-- the viewer. Repeated after the live changes below.
-- ---------------------------------------------------------------------------------------------
create temporary view sl_sweep as
  select ci.id as story, v.id as viewer, sl.kind, sl.label
  from public.content_items ci
  cross join (select p.id from public.profiles p where p.id::text like '10b00000-%' union all select null::uuid) v
  cross join lateral public.story_label(ci.id, v.id) sl
  where ci.owner_profile_id in ('10b00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000011');

select ok((select count(*) from sl_sweep where kind = 'member_label') >= 4
          and (select count(*) from sl_sweep where kind = 'only_for_you') >= 3
          and (select count(*) from sl_sweep where kind = 'shared_with_you') >= 4,
  'the sweep returns labels of every kind, so the checks below are not vacuous');
select is_empty(
  $$ select s.story, s.viewer, c.id
     from sl_sweep s
     cross join public.circles c
     where c.owner_profile_id in ('10b00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000011')
       and pg_catalog.strpos(pg_catalog.lower(s.kind::text || ' ' || coalesce(s.label, '')),
                             pg_catalog.lower(c.private_name)) > 0 $$,
  'no returned kind or label contains any circle private name (Req 13.10)');
select is_empty(
  $$ select story, viewer from sl_sweep group by story, viewer having count(*) > 1 $$,
  'at most one label per story and viewer (Req 13.1)');
select is_empty(
  $$ select 1 from sl_sweep where (kind = 'member_label') <> (label is not null) $$,
  'label text comes back with member_label only, and member_label always has text (Req 13.1, 13.14)');
select is_empty(
  $$ select 1 from sl_sweep s
     where s.kind = 'member_label'
       and not exists (select 1 from public.item_circles ic join public.circles c on c.id = ic.circle_id
                       where ic.content_item_id = s.story and c.show_member_label
                         and c.member_label = s.label and private.in_circle(c.id, s.viewer)) $$,
  'every label is the member label of a switched-on linked circle holding the viewer (Req 13.9)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Tia, a stranger, in the canary order (DR-1): untrusted viewer ids are null (13.12).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '10101010-0000-4000-8000-000000000006', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Tia claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '10101010-0000-4000-8000-000000000006'::uuid, 'auth.uid() is Tia');

select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000002',
                                                    '10b00000-0000-4000-8000-000000000004') $$,
  'Tia asking as Rex gets no label: evaluated as a null viewer (Req 13.12)');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                    '10b00000-0000-4000-8000-000000000002') $$,
  'Tia asking as Pam cannot read Pam''s member label');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                    '10b00000-0000-4000-8000-000000000001') $$,
  'Tia asking as the owner gets nothing');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                    '10b00000-0000-4000-8000-000000000006') $$,
  'Tia as herself gets no label on a story she cannot see');
select throws_ok($$ select * from private.story_label('10d00000-0000-4000-8000-000000000002',
                                                      '10b00000-0000-4000-8000-000000000004') $$,
  '42501', null, 'authenticated cannot call private.story_label');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Pam: her own id is trusted, anyone else's is null.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '10101010-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Pam claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '10101010-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Pam');

select results_eq(
  $$ select kind::text, label from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                      '10b00000-0000-4000-8000-000000000002') $$,
  $$ values ('member_label', 'Book people') $$,
  'Pam as herself gets her member label through the API');
select results_eq(
  $$ select kind::text, label from public.story_label('10d00000-0000-4000-8000-000000000004',
                                                      '10b00000-0000-4000-8000-000000000002') $$,
  $$ values ('shared_with_you', null::text) $$,
  'Pam as herself gets shared_with_you through the API');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000002',
                                                    '10b00000-0000-4000-8000-000000000004') $$,
  'Pam asking as Rex gets no label (Req 13.12)');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                    '10b00000-0000-4000-8000-000000000003') $$,
  'Pam asking as Quin cannot read Quin''s member label');

-- ---------------------------------------------------------------------------------------------
-- Signed out (anon).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000002',
                                                    '10b00000-0000-4000-8000-000000000004') $$,
  'anon asking as Rex gets no label (Req 13.12)');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001', null) $$,
  'anon gets no label on a circle story');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000008', null) $$,
  'anon gets no label on a public story (NQ-3)');
select throws_ok($$ select * from private.story_label('10d00000-0000-4000-8000-000000000002', null) $$,
  '42501', null, 'anon cannot call private.story_label');

-- Back to a trusted caller for the live changes.
set local role postgres;
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------------------------
-- All followers are the current followers at every call (Req 13.8).
-- ---------------------------------------------------------------------------------------------
delete from public.relationships
where requester_profile_id = '10b00000-0000-4000-8000-000000000008'
  and target_profile_id = '10b00000-0000-4000-8000-000000000011';
select is(
  (select string_agg(sl.kind::text, ',') from public.story_label('10d00000-0000-4000-8000-000000000021',
                                                                 '10b00000-0000-4000-8000-000000000002') sl),
  'only_for_you', 'after the other follower unfollows, Pam is the only follower: only_for_you');
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000021',
                                                    '10b00000-0000-4000-8000-000000000008') $$,
  'the former follower gets no label');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('10b00000-0000-4000-8000-000000000009', '10b00000-0000-4000-8000-000000000011', 'follow');
select is(
  (select string_agg(sl.kind::text, ',') from public.story_label('10d00000-0000-4000-8000-000000000021',
                                                                 '10b00000-0000-4000-8000-000000000002') sl),
  'shared_with_you', 'a new follower turns Pam''s label back to shared_with_you');
select is(
  (select string_agg(sl.kind::text, ',') from public.story_label('10d00000-0000-4000-8000-000000000021',
                                                                 '10b00000-0000-4000-8000-000000000009') sl),
  'shared_with_you', 'the new follower gets shared_with_you at once');
update public.circles set show_member_label = true, member_label = 'Regulars'
where owner_profile_id = '10b00000-0000-4000-8000-000000000011' and is_all_followers;
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000021', '10b00000-0000-4000-8000-000000000002') sl),
  'member_label:Regulars', 'a switched-on all followers circle gives its member label to a follower');
delete from public.relationships
where requester_profile_id = '10b00000-0000-4000-8000-000000000002'
  and target_profile_id = '10b00000-0000-4000-8000-000000000011';
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000021',
                                                    '10b00000-0000-4000-8000-000000000002') $$,
  'after unfollowing, Pam no longer gets the all followers member label');

-- ---------------------------------------------------------------------------------------------
-- Switching a label off or removing a member takes effect at the next call (Req 13.11).
-- ---------------------------------------------------------------------------------------------
update public.circles set show_member_label = false where id = '10c00000-0000-4000-8000-000000000002';
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002') sl),
  'member_label:Close friends', 'with Book people switched off, Pam gets the next circle''s label at once');
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000006', '10b00000-0000-4000-8000-000000000002') sl),
  'shared_with_you', 'with its only switched-on circle off, Pam''s label falls back to shared_with_you');
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000007', '10b00000-0000-4000-8000-000000000002') sl),
  'member_label:Tie winner', 'switching one circle off leaves another switched-on circle''s label');
delete from public.circle_members
where circle_id = '10c00000-0000-4000-8000-000000000001' and member_profile_id = '10b00000-0000-4000-8000-000000000002';
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002') sl),
  'shared_with_you', 'removed from Close friends, Pam no longer gets its label at the next call');
delete from public.circle_members
where circle_id = '10c00000-0000-4000-8000-000000000001' and member_profile_id = '10b00000-0000-4000-8000-000000000003';
select is_empty($$ select * from public.story_label('10d00000-0000-4000-8000-000000000001',
                                                    '10b00000-0000-4000-8000-000000000003') $$,
  'a member removed from the only circle that showed her the story gets no label');
select is(
  (select string_agg(sl.kind::text || coalesce(':' || sl.label, ''), ',')
   from public.story_label('10d00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000002') sl),
  'only_for_you', 'with the other circle now empty, Pam is the only one left: only_for_you (D-2)');

-- The sweep again, after every live change (Req 13.9, 13.10).
select is_empty(
  $$ select s.story, s.viewer, c.id
     from sl_sweep s
     cross join public.circles c
     where c.owner_profile_id in ('10b00000-0000-4000-8000-000000000001', '10b00000-0000-4000-8000-000000000011')
       and pg_catalog.strpos(pg_catalog.lower(s.kind::text || ' ' || coalesce(s.label, '')),
                             pg_catalog.lower(c.private_name)) > 0 $$,
  'after the changes, no returned kind or label contains any circle private name');
select is_empty(
  $$ select story, viewer from sl_sweep group by story, viewer having count(*) > 1 $$,
  'after the changes, at most one label per story and viewer');
select is_empty(
  $$ select 1 from sl_sweep s
     where s.kind = 'member_label'
       and not exists (select 1 from public.item_circles ic join public.circles c on c.id = ic.circle_id
                       where ic.content_item_id = s.story and c.show_member_label
                         and c.member_label = s.label and private.in_circle(c.id, s.viewer)) $$,
  'after the changes, every label is from a switched-on linked circle holding the viewer');

select * from finish();
rollback;
