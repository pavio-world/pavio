-- Circle privacy: a circle's private name never reaches anyone but its owner (Property 10).
-- A circle member, a connection outside the circle and anon read every surface granted to them
-- (circles, circle_members, item_circles, groups, notifications, content_items, vouches,
-- can_view, page_items, story_label, relationship_counts, my_relationships, my_received_vouches,
-- item_audience, group_linked_circle), and the owner previews the page through view_as. Every
-- returned row is swept with row_to_json(...)::text for the private names and circle ids. The
-- member label may appear only to members, and only through story_label, page_items and view_as;
-- a switched off label never appears. A member cannot learn who else is in the circle.
-- Spec 00 Req 9.10, 9.11, 9.17, 13.10, 22.8, 25.6; design "Circle private name guarantee", DR-1.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(165);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- People: Amy (owner of the circles), Ben and Eve (members of c01), Cal (Amy's connection in no
-- circle). Ben is not connected to Eve. Circles carry distinctive strings so a leak is detectable:
--   c01 zqx_hush_private_0901,  switch on,  member label "Warm lantern 0911", holds Ben, Eve
--   c02 zqx_quiet_private_0902, switch off, stored label "Dormant label 0912", holds Ben
-- Amy's items:
--   d01 story c01        d02 gallery c01, c02    d03 story c02    d04 status public
--   d05 story to the group g01 (linked to c01; Ben and Cal are group members)
--   f01 Amy about Ben, circles c01, Top 8 position 1 (notifies Ben)
--   f02 Amy about Cal, circles c01, unfeatured (notifies Cal)
-- Ben's item d11 is a public gallery photo, used to probe the item_circles guard.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('09090909-0000-4000-8000-000000000001', 'amy.cp@example.invalid'),
  ('09090909-0000-4000-8000-000000000002', 'ben.cp@example.invalid'),
  ('09090909-0000-4000-8000-000000000003', 'eve.cp@example.invalid'),
  ('09090909-0000-4000-8000-000000000004', 'cal.cp@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('09b00000-0000-4000-8000-000000000001', 'person', '09090909-0000-4000-8000-000000000001', 'amy_cp', 'Amy'),
  ('09b00000-0000-4000-8000-000000000002', 'person', '09090909-0000-4000-8000-000000000002', 'ben_cp', 'Ben'),
  ('09b00000-0000-4000-8000-000000000003', 'person', '09090909-0000-4000-8000-000000000003', 'eve_cp', 'Eve'),
  ('09b00000-0000-4000-8000-000000000004', 'person', '09090909-0000-4000-8000-000000000004', 'cal_cp', 'Cal');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('09b00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000002', 'connection'),
  ('09b00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000003', 'connection'),
  ('09b00000-0000-4000-8000-000000000004', '09b00000-0000-4000-8000-000000000001', 'connection');
update public.relationships set status = 'accepted'
where type = 'connection'
  and '09b00000-0000-4000-8000-000000000001' in (requester_profile_id, target_profile_id);
insert into public.circles (id, owner_profile_id, private_name, show_member_label, member_label) values
  ('09c00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000001', 'zqx_hush_private_0901',
   true, 'Warm lantern 0911'),
  ('09c00000-0000-4000-8000-000000000002', '09b00000-0000-4000-8000-000000000001', 'zqx_quiet_private_0902',
   false, 'Dormant label 0912');
insert into public.circle_members (circle_id, member_profile_id) values
  ('09c00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000002'),
  ('09c00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000003'),
  ('09c00000-0000-4000-8000-000000000002', '09b00000-0000-4000-8000-000000000002');
insert into public.groups (id, owner_profile_id, name, circle_id) values
  ('09e00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000001', 'Amy book club',
   '09c00000-0000-4000-8000-000000000001');
insert into public.group_members (group_id, profile_id) values
  ('09e00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000002'),
  ('09e00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000004');
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('09d00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s01"}'),
  ('09d00000-0000-4000-8000-000000000002', '09b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "09b00000-0000-4000-8000-000000000001/gallery/g02.jpg"}'),
  ('09d00000-0000-4000-8000-000000000003', '09b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s03"}'),
  ('09d00000-0000-4000-8000-000000000004', '09b00000-0000-4000-8000-000000000001', 'status', 'public',
   '{"text": "around today"}'),
  ('09d00000-0000-4000-8000-000000000011', '09b00000-0000-4000-8000-000000000002', 'gallery', 'public',
   '{"image_path": "09b00000-0000-4000-8000-000000000002/gallery/g11.jpg"}');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, group_id) values
  ('09d00000-0000-4000-8000-000000000005', '09b00000-0000-4000-8000-000000000001', 'story', 'group', '{"text": "s05"}',
   '09e00000-0000-4000-8000-000000000001');
insert into public.vouches (id, author_profile_id, subject_profile_id, body, audience, top8_position) values
  ('09f00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000001',
   '09b00000-0000-4000-8000-000000000002', 'Ben keeps his word', 'circles', 1),
  ('09f00000-0000-4000-8000-000000000002', '09b00000-0000-4000-8000-000000000001',
   '09b00000-0000-4000-8000-000000000004', 'Cal cooks well', 'circles', null);
insert into public.item_circles (content_item_id, circle_id) values
  ('09d00000-0000-4000-8000-000000000001', '09c00000-0000-4000-8000-000000000001'),
  ('09d00000-0000-4000-8000-000000000002', '09c00000-0000-4000-8000-000000000001'),
  ('09d00000-0000-4000-8000-000000000002', '09c00000-0000-4000-8000-000000000002'),
  ('09d00000-0000-4000-8000-000000000003', '09c00000-0000-4000-8000-000000000002');
insert into public.item_circles (vouch_id, circle_id) values
  ('09f00000-0000-4000-8000-000000000001', '09c00000-0000-4000-8000-000000000001'),
  ('09f00000-0000-4000-8000-000000000002', '09c00000-0000-4000-8000-000000000001');

select lives_ok($$ set constraints all immediate $$, 'the fixtures pass every deferred check');
set constraints all deferred;
select is((select count(*)::int from public.circles
           where id = '09c00000-0000-4000-8000-000000000001' and show_member_label
             and member_label is not null and member_label <> private_name), 1,
  'c01 has its member label switched on, and the label differs from its private name');

-- Needles to sweep for. private and circle_id must never reach a non-owner; label_on only members
-- through story_label, page_items and view_as; label_off nobody; member_identity is Eve, whom Ben
-- must not learn about.
create temporary table cp_needles (kind text not null, needle text not null) on commit drop;
insert into cp_needles values
  ('private', 'zqx_hush_private_0901'),
  ('private', 'zqx_quiet_private_0902'),
  ('private', 'zqx_'),
  ('circle_id', '09c00000-0000-4000-8000-000000000001'),
  ('circle_id', '09c00000-0000-4000-8000-000000000002'),
  ('label_on', 'Warm lantern 0911'),
  ('label_off', 'Dormant label 0912'),
  ('member_identity', '09b00000-0000-4000-8000-000000000003'),
  ('member_identity', '09090909-0000-4000-8000-000000000003'),
  ('member_identity', 'eve_cp');
-- The items and profiles each caller probes the functions with.
create temporary table cp_items (id uuid primary key) on commit drop;
insert into cp_items values
  ('09d00000-0000-4000-8000-000000000001'), ('09d00000-0000-4000-8000-000000000002'),
  ('09d00000-0000-4000-8000-000000000003'), ('09d00000-0000-4000-8000-000000000004'),
  ('09d00000-0000-4000-8000-000000000005'), ('09d00000-0000-4000-8000-000000000011'),
  ('09f00000-0000-4000-8000-000000000001'), ('09f00000-0000-4000-8000-000000000002');
create temporary table cp_people (id uuid primary key) on commit drop;
insert into cp_people values
  ('09b00000-0000-4000-8000-000000000001'), ('09b00000-0000-4000-8000-000000000002'),
  ('09b00000-0000-4000-8000-000000000003'), ('09b00000-0000-4000-8000-000000000004');
-- Every row a caller got back, one json text per row.
create temporary table cp_rows (caller text not null, surface text not null, j text) on commit drop;
-- What each captured surface may hold: label_allowed lets label_on through; rows is some, none
-- or any (no expectation).
create temporary table cp_expect (caller text, surface text, label_allowed boolean, rows text,
                                  primary key (caller, surface)) on commit drop;
insert into cp_expect
select c.caller, s.surface,
       c.caller = 'Ben' and s.surface in ('story_label', 'page_items'),
       case when s.surface in ('circles', 'circle_members', 'item_circles', 'item_audience') then 'none'
            when c.caller = 'Cal' and s.surface = 'story_label' then 'none'
            else 'some' end
from (values ('Ben'), ('Cal')) as c(caller)
cross join (values ('circles'), ('circle_members'), ('item_circles'), ('groups'), ('notifications'),
                   ('content_items'), ('vouches'), ('can_view'), ('page_items'), ('story_label'),
                   ('relationship_counts'), ('my_relationships'), ('my_received_vouches'),
                   ('item_audience'), ('group_linked_circle')) as s(surface);
insert into cp_expect values
  ('anon', 'content_items', false, 'some'),
  ('anon', 'vouches', false, 'any'),
  ('anon', 'can_view', false, 'some'),
  ('anon', 'page_items', false, 'some'),
  ('anon', 'story_label', false, 'none'),
  ('anon', 'relationship_counts', false, 'some'),
  ('Amy as Ben', 'view_as', true, 'some'),
  ('Amy as Eve', 'view_as', true, 'some'),
  ('Amy as Cal', 'view_as', false, 'some'),
  ('Amy as signed out', 'view_as', false, 'some');
grant select on cp_needles, cp_items, cp_people to anon, authenticated;
grant insert on cp_rows to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Signed in as Amy, the owner: the sweep's control, and view_as previews (Req 21.8).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '09090909-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Amy claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '09090909-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Amy');

select lives_ok(
  $$ insert into cp_rows
     select 'Amy', 'circles', pg_catalog.row_to_json(c)::text from public.circles c
     union all
     select 'Amy as ' || v.vname, 'view_as', pg_catalog.row_to_json(x)::text
     from (values ('Ben', '09b00000-0000-4000-8000-000000000002'::uuid),
                  ('Eve', '09b00000-0000-4000-8000-000000000003'::uuid),
                  ('Cal', '09b00000-0000-4000-8000-000000000004'::uuid),
                  ('signed out', null::uuid)) as v(vname, viewer)
     cross join lateral public.view_as('09b00000-0000-4000-8000-000000000001', v.viewer) x $$,
  'Amy''s circles and her view_as previews are captured');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ben, a member of both circles.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '09090909-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ben claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '09090909-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Ben');

select lives_ok(
  $$ with me(caller, pid) as (values ('Ben', '09b00000-0000-4000-8000-000000000002'::uuid))
     insert into cp_rows
     select me.caller, 'circles', pg_catalog.row_to_json(x)::text from me, public.circles x
     union all
     select me.caller, 'circle_members', pg_catalog.row_to_json(x)::text from me, public.circle_members x
     union all
     select me.caller, 'item_circles', pg_catalog.row_to_json(x)::text from me, public.item_circles x
     union all
     select me.caller, 'groups', pg_catalog.row_to_json(x)::text
     from me, (select id, owner_profile_id, name, created_at, updated_at from public.groups) x
     union all
     select me.caller, 'notifications', pg_catalog.row_to_json(x)::text from me, public.notifications x
     union all
     select me.caller, 'content_items', pg_catalog.row_to_json(x)::text
     from me, (select id, owner_profile_id, content_type, details, expires_at, parent_id, group_id,
                      created_at, updated_at from public.content_items) x
     union all
     select me.caller, 'vouches', pg_catalog.row_to_json(x)::text
     from me, (select id, author_profile_id, subject_profile_id, body, top8_position, created_at, updated_at
               from public.vouches) x
     union all
     select me.caller, 'can_view',
            pg_catalog.json_build_object('item', i.id, 'can_view', public.can_view(i.id, me.pid))::text
     from me, cp_items i
     union all
     select me.caller, 'page_items', pg_catalog.row_to_json(x)::text
     from me, public.page_items('09b00000-0000-4000-8000-000000000001', me.pid) x
     union all
     select me.caller, 'story_label',
            pg_catalog.json_build_object('item', i.id, 'label', pg_catalog.row_to_json(s))::text
     from me, cp_items i cross join lateral public.story_label(i.id, me.pid) s
     union all
     select me.caller, 'relationship_counts', pg_catalog.row_to_json(x)::text
     from me, cp_people p cross join lateral public.relationship_counts(p.id) x
     union all
     select me.caller, 'my_relationships', pg_catalog.row_to_json(x)::text from me, public.my_relationships(me.pid) x
     union all
     select me.caller, 'my_received_vouches', pg_catalog.row_to_json(x)::text
     from me, public.my_received_vouches(me.pid) x
     union all
     select me.caller, 'item_audience', pg_catalog.row_to_json(x)::text
     from me, cp_items i cross join lateral public.item_audience(i.id) x
     where i.id <> '09d00000-0000-4000-8000-000000000011'          -- Ben's own item, Amy's only
     union all
     select me.caller, 'group_linked_circle',
            pg_catalog.json_build_object('circle', public.group_linked_circle('09e00000-0000-4000-8000-000000000001'))::text
     from me $$,
  'every surface Ben can read is captured');

-- Writes that return rows reach no circle (Req 9.10, 22.8).
select is_empty(
  $$ with u as (update public.circles set member_label = member_label returning private_name, member_label)
     select * from u $$,
  'an update on circles returns no row to Ben');
select is_empty(
  $$ with d as (delete from public.circles returning private_name) select * from d $$,
  'a delete on circles returns no row to Ben');
-- Only the owner previews; the functions that need acts_as refuse another profile.
select throws_ok($$ select * from public.view_as('09b00000-0000-4000-8000-000000000001',
                                                 '09b00000-0000-4000-8000-000000000002') $$,
  'PT403', 'view_as.not_owner', 'Ben cannot preview Amy''s page');
select throws_ok($$ select * from public.my_relationships('09b00000-0000-4000-8000-000000000001') $$,
  'PT403', 'acting.not_allowed', 'Ben cannot list Amy''s relationships');
select throws_ok($$ select * from public.my_received_vouches('09b00000-0000-4000-8000-000000000001') $$,
  'PT403', 'acting.not_allowed', 'Ben cannot list Amy''s received vouches');
-- Silence (Req 9.17): a member cannot confirm his own membership or test for anyone else's. An
-- existing and a missing membership give the same refusal, before any unique key is checked.
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('09c00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000002') $$,
  '42501', null, 're-adding Ben''s own existing membership is refused like any other insert');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('09c00000-0000-4000-8000-000000000002', '09b00000-0000-4000-8000-000000000003') $$,
  '42501', null, 'adding Eve to a circle she is not in gives the same refusal');
-- Guard errors are fixed keys and never carry a circle name.
select throws_ok($$ insert into public.item_circles (content_item_id, circle_id)
                    values ('09d00000-0000-4000-8000-000000000011', '09c00000-0000-4000-8000-000000000001') $$,
  'PT422', 'audience.circle_not_owned', 'linking Ben''s item to Amy''s circle fails with a fixed key');
-- groups.circle_id is never readable by a group member (Req 19.2).
select throws_ok($$ select circle_id from public.groups $$, '42501', null,
  'Ben cannot select groups.circle_id');
select is(public.group_linked_circle('09e00000-0000-4000-8000-000000000001'), null::uuid,
  'group_linked_circle gives Ben no circle');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Cal, Amy's connection in none of her circles (and a member of her group).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '09090909-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Cal claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '09090909-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Cal');

select lives_ok(
  $$ with me(caller, pid) as (values ('Cal', '09b00000-0000-4000-8000-000000000004'::uuid))
     insert into cp_rows
     select me.caller, 'circles', pg_catalog.row_to_json(x)::text from me, public.circles x
     union all
     select me.caller, 'circle_members', pg_catalog.row_to_json(x)::text from me, public.circle_members x
     union all
     select me.caller, 'item_circles', pg_catalog.row_to_json(x)::text from me, public.item_circles x
     union all
     select me.caller, 'groups', pg_catalog.row_to_json(x)::text
     from me, (select id, owner_profile_id, name, created_at, updated_at from public.groups) x
     union all
     select me.caller, 'notifications', pg_catalog.row_to_json(x)::text from me, public.notifications x
     union all
     select me.caller, 'content_items', pg_catalog.row_to_json(x)::text
     from me, (select id, owner_profile_id, content_type, details, expires_at, parent_id, group_id,
                      created_at, updated_at from public.content_items) x
     union all
     select me.caller, 'vouches', pg_catalog.row_to_json(x)::text
     from me, (select id, author_profile_id, subject_profile_id, body, top8_position, created_at, updated_at
               from public.vouches) x
     union all
     select me.caller, 'can_view',
            pg_catalog.json_build_object('item', i.id, 'can_view', public.can_view(i.id, me.pid))::text
     from me, cp_items i
     union all
     select me.caller, 'page_items', pg_catalog.row_to_json(x)::text
     from me, public.page_items('09b00000-0000-4000-8000-000000000001', me.pid) x
     union all
     select me.caller, 'story_label',
            pg_catalog.json_build_object('item', i.id, 'label', pg_catalog.row_to_json(s))::text
     from me, cp_items i cross join lateral public.story_label(i.id, me.pid) s
     union all
     select me.caller, 'relationship_counts', pg_catalog.row_to_json(x)::text
     from me, cp_people p cross join lateral public.relationship_counts(p.id) x
     union all
     select me.caller, 'my_relationships', pg_catalog.row_to_json(x)::text from me, public.my_relationships(me.pid) x
     union all
     select me.caller, 'my_received_vouches', pg_catalog.row_to_json(x)::text
     from me, public.my_received_vouches(me.pid) x
     union all
     select me.caller, 'item_audience', pg_catalog.row_to_json(x)::text
     from me, cp_items i cross join lateral public.item_audience(i.id) x
     union all
     select me.caller, 'group_linked_circle',
            pg_catalog.json_build_object('circle', public.group_linked_circle('09e00000-0000-4000-8000-000000000001'))::text
     from me $$,
  'every surface Cal can read is captured');
select throws_ok($$ insert into public.circle_members (circle_id, member_profile_id)
                    values ('09c00000-0000-4000-8000-000000000001', '09b00000-0000-4000-8000-000000000004') $$,
  '42501', null, 'Cal adding himself to Amy''s circle gives the same refusal as a member gets');
select is(public.group_linked_circle('09e00000-0000-4000-8000-000000000001'), null::uuid,
  'group_linked_circle gives Cal no circle');

-- ---------------------------------------------------------------------------------------------
-- Signed out (anon).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select lives_ok(
  $$ insert into cp_rows
     select 'anon', 'content_items', pg_catalog.row_to_json(x)::text
     from (select id, owner_profile_id, content_type, details, expires_at, parent_id, group_id,
                  created_at, updated_at from public.content_items) x
     union all
     select 'anon', 'vouches', pg_catalog.row_to_json(x)::text
     from (select id, author_profile_id, subject_profile_id, body, top8_position, created_at, updated_at
           from public.vouches) x
     union all
     select 'anon', 'can_view',
            pg_catalog.json_build_object('item', i.id, 'can_view', public.can_view(i.id, null))::text
     from cp_items i
     union all
     select 'anon', 'page_items', pg_catalog.row_to_json(x)::text
     from public.page_items('09b00000-0000-4000-8000-000000000001', null) x
     union all
     select 'anon', 'story_label',
            pg_catalog.json_build_object('item', i.id, 'label', pg_catalog.row_to_json(s))::text
     from cp_items i cross join lateral public.story_label(i.id, null) s
     union all
     select 'anon', 'relationship_counts', pg_catalog.row_to_json(x)::text
     from cp_people p cross join lateral public.relationship_counts(p.id) x $$,
  'every surface anon can read is captured');
select throws_ok(pg_catalog.format('select * from public.%I', t), '42501', null,
  'anon cannot read ' || t)
from unnest(array['circles', 'circle_members', 'item_circles', 'groups', 'notifications']) as t;
select throws_ok($$ select * from public.my_relationships('09b00000-0000-4000-8000-000000000002') $$,
  '42501', null, 'anon cannot execute my_relationships');
select throws_ok($$ select * from public.view_as('09b00000-0000-4000-8000-000000000001', null) $$,
  '42501', null, 'anon cannot execute view_as');
select throws_ok($$ select * from public.item_audience('09d00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot execute item_audience');
select throws_ok($$ select public.group_linked_circle('09e00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot execute group_linked_circle');

-- ---------------------------------------------------------------------------------------------
-- Search (search_directory) is added in task 22.3. Its sweep for anon, the member and the
-- non-member goes here, using the same cp_needles and cp_expect rows.
-- ---------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------
-- Back to the test owner: sweep every captured row.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);

select is_empty(
  $$ select distinct r.caller, r.surface from cp_rows r
     where r.caller <> 'Amy'
       and not exists (select 1 from cp_expect e where e.caller = r.caller and e.surface = r.surface) $$,
  'every captured non-owner surface has an expectation');
-- The control: the sweep finds a private name where one is allowed, in Amy's own circles.
select isnt_empty(
  $$ select 1 from cp_rows r join cp_needles n on n.kind = 'private'
       and pg_catalog.strpos(pg_catalog.lower(r.j), pg_catalog.lower(n.needle)) > 0
     where r.caller = 'Amy' and r.surface = 'circles' $$,
  'the sweep detects the private names in the owner''s own circles rows');
-- No private name and no circle id in any row a non-owner got back (Req 9.10, 13.10, 22.8, 25.6).
select is_empty(
  pg_catalog.format(
    $$ select r.j, n.needle from cp_rows r join cp_needles n on n.kind in ('private', 'circle_id')
         and pg_catalog.strpos(pg_catalog.lower(r.j), pg_catalog.lower(n.needle)) > 0
       where r.caller = %L and r.surface = %L $$, e.caller, e.surface),
  e.caller || ' gets no circle private name or circle id from ' || e.surface)
from cp_expect e order by e.caller, e.surface;
-- Member labels only where the design allows (Req 9.11): never a switched off label, and the
-- switched on label only to members through story_label, page_items and view_as.
select is_empty(
  pg_catalog.format(
    $$ select r.j, n.needle from cp_rows r join cp_needles n
         on (n.kind = 'label_off' or (n.kind = 'label_on' and not %L::boolean))
         and pg_catalog.strpos(pg_catalog.lower(r.j), pg_catalog.lower(n.needle)) > 0
       where r.caller = %L and r.surface = %L $$, e.label_allowed, e.caller, e.surface),
  e.caller || ' gets ' || case when e.label_allowed then 'no switched off member label'
                               else 'no member label' end || ' from ' || e.surface)
from cp_expect e order by e.caller, e.surface;
-- The sweeps are not vacuous, and the circle tables stay closed (Req 9.10, 9.17).
select case e.rows
         when 'some' then isnt_empty(
           pg_catalog.format('select 1 from cp_rows where caller = %L and surface = %L', e.caller, e.surface),
           e.caller || ' got rows from ' || e.surface)
         else is_empty(
           pg_catalog.format('select j from cp_rows where caller = %L and surface = %L', e.caller, e.surface),
           e.caller || ' got no rows from ' || e.surface)
       end
from cp_expect e where e.rows <> 'any' order by e.caller, e.surface;
-- Members do get the switched on label through the allowed paths.
select isnt_empty(
  pg_catalog.format(
    $$ select 1 from cp_rows r where r.caller = %L and r.surface = %L
         and pg_catalog.strpos(r.j, 'Warm lantern 0911') > 0 $$, x.caller, x.surface),
  x.caller || ' gets the member label from ' || x.surface)
from (values ('Ben', 'story_label'), ('Ben', 'page_items'), ('Amy as Ben', 'view_as'),
             ('Amy as Eve', 'view_as')) as x(caller, surface);
-- Ben never learns who else is in his circles (Req 9.17, 13.10).
select is_empty(
  $$ select r.surface, r.j from cp_rows r join cp_needles n on n.kind = 'member_identity'
       and pg_catalog.strpos(pg_catalog.lower(r.j), pg_catalog.lower(n.needle)) > 0
     where r.caller = 'Ben' $$,
  'no row Ben got back names or identifies Eve, the other member of c01');

select * from finish();
rollback;
