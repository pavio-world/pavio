-- Page listings and view as: private.page_items, its public wrapper and public.view_as. Only a
-- login that acts as the page may call view_as (PT403 view_as.not_owner) and anon cannot execute
-- it; every simulated viewer (the owner, a circle member, a connection, a stranger, a follower and
-- signed out) sees exactly the expected items; the story label is the simulated viewer's; no
-- circle id or name comes back; public.page_items evaluates an untrusted viewer id as signed out;
-- view_as returns exactly private.page_items for the same viewer and never more than can_view
-- allows (Property 6); and a business owner previews the business page while acting as it.
-- Spec 00 Req 14.19 to 14.21, 21.1 to 21.8, 25.3, 25.8; design "page_items and view_as", D-1, DR-1.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(94);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims (a trusted caller, so a story can be back-dated).
-- People: Ola (owner of the person page), Pia, Kai, Ned (Ola's connections), Tom (a stranger
-- with a pending request to Ola), Uma (owns the business Hub), Vic (follows Hub), Zed (owns the
-- business Mill). Pia and Ned are connected; Pia also follows Hub; Hub and Mill are connected.
-- Circles carry distinctive private names (zqx_..._private_11NN) so a leak is detectable:
--   c01 Ola's zqx_inner_private_1101, switch on, "Inner folk", holds Pia
--   c02 Ola's zqx_work_private_1102,  switch off, holds Kai
--   c03 Hub's zqx_suppliers_private_1103, switch off, holds Mill
--   Hub's all followers circle comes from the profiles trigger.
-- Ola's page items:
--   d01 status public      d02 gallery connections   d03 story c01         d04 story c02, c01
--   d05 story c02          d06 writing public        d07 story public      d08 story connections, expired
--   d09 gallery c02
--   f01 Ola about Pia, public, not featured (not on Ola's page)
--   f02 Ola about Kai, connections, Top 8 position 2, hidden by Kai
--   f03 Ola about Ned, circles c01, Top 8 position 1
--   f04 Pia about Ola, public      f05 Kai about Ola, connections, hidden by Ola
--   f06 Ned about Ola, connections (Ned's connections are Ola and Pia, NQ-1)
--   f07 Pia about Ned, public (not on Ola's page)     d21 Pia's status, public (not on Ola's page)
-- Hub's page items:
--   d11 gallery connections   d12 story to all followers   d13 gallery c03   d14 writing public
--   f11 Vic about Hub, public      f12 Mill about Hub, connections
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-0000-4000-8000-000000000001', 'ola.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000002', 'pia.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000003', 'kai.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000004', 'ned.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000005', 'tom.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000006', 'uma.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000007', 'vic.va@example.invalid'),
  ('11111111-0000-4000-8000-000000000008', 'zed.va@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('11b00000-0000-4000-8000-000000000001', 'person', '11111111-0000-4000-8000-000000000001', 'ola_va', 'Ola'),
  ('11b00000-0000-4000-8000-000000000002', 'person', '11111111-0000-4000-8000-000000000002', 'pia_va', 'Pia'),
  ('11b00000-0000-4000-8000-000000000003', 'person', '11111111-0000-4000-8000-000000000003', 'kai_va', 'Kai'),
  ('11b00000-0000-4000-8000-000000000004', 'person', '11111111-0000-4000-8000-000000000004', 'ned_va', 'Ned'),
  ('11b00000-0000-4000-8000-000000000005', 'person', '11111111-0000-4000-8000-000000000005', 'tom_va', 'Tom'),
  ('11b00000-0000-4000-8000-000000000006', 'person', '11111111-0000-4000-8000-000000000006', 'uma_va', 'Uma'),
  ('11b00000-0000-4000-8000-000000000007', 'person', '11111111-0000-4000-8000-000000000007', 'vic_va', 'Vic'),
  ('11b00000-0000-4000-8000-000000000008', 'person', '11111111-0000-4000-8000-000000000008', 'zed_va', 'Zed');
insert into public.profiles (id, type, handle, display_name) values
  ('11b00000-0000-4000-8000-000000000011', 'business', 'hub_va', 'Uma''s Hub'),
  ('11b00000-0000-4000-8000-000000000012', 'business', 'mill_va', 'Zed''s Mill');
insert into public.profile_managers (profile_id, user_id, role) values
  ('11b00000-0000-4000-8000-000000000011', '11111111-0000-4000-8000-000000000006', 'owner'),
  ('11b00000-0000-4000-8000-000000000012', '11111111-0000-4000-8000-000000000008', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000002', 'connection'),
  ('11b00000-0000-4000-8000-000000000003', '11b00000-0000-4000-8000-000000000001', 'connection'),
  ('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000004', 'connection'),
  ('11b00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000004', 'connection'),
  ('11b00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000012', 'connection'),
  ('11b00000-0000-4000-8000-000000000005', '11b00000-0000-4000-8000-000000000001', 'connection'),
  ('11b00000-0000-4000-8000-000000000007', '11b00000-0000-4000-8000-000000000011', 'follow'),
  ('11b00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000011', 'follow');
update public.relationships set status = 'accepted'
where type = 'connection'
  and requester_profile_id::text like '11b%'
  and requester_profile_id <> '11b00000-0000-4000-8000-000000000005';
insert into public.circles (id, owner_profile_id, private_name, show_member_label, member_label) values
  ('11c00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000001', 'zqx_inner_private_1101',
   true, 'Inner folk'),
  ('11c00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000001', 'zqx_work_private_1102',
   false, null),
  ('11c00000-0000-4000-8000-000000000003', '11b00000-0000-4000-8000-000000000011', 'zqx_suppliers_private_1103',
   false, null);
insert into public.circle_members (circle_id, member_profile_id) values
  ('11c00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000002'),
  ('11c00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000003'),
  ('11c00000-0000-4000-8000-000000000003', '11b00000-0000-4000-8000-000000000012');
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('11d00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000001', 'status', 'public',
   '{"text": "on leave"}'),
  ('11d00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000001', 'gallery', 'connections',
   '{"image_path": "11b00000-0000-4000-8000-000000000001/gallery/g02.jpg"}'),
  ('11d00000-0000-4000-8000-000000000003', '11b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s03"}'),
  ('11d00000-0000-4000-8000-000000000004', '11b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s04"}'),
  ('11d00000-0000-4000-8000-000000000005', '11b00000-0000-4000-8000-000000000001', 'story', 'circles', '{"text": "s05"}'),
  ('11d00000-0000-4000-8000-000000000006', '11b00000-0000-4000-8000-000000000001', 'writing', 'public',
   '{"title": "Notes", "body": "A public post"}'),
  ('11d00000-0000-4000-8000-000000000007', '11b00000-0000-4000-8000-000000000001', 'story', 'public', '{"text": "s07"}'),
  ('11d00000-0000-4000-8000-000000000009', '11b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "11b00000-0000-4000-8000-000000000001/gallery/g09.jpg"}'),
  ('11d00000-0000-4000-8000-000000000021', '11b00000-0000-4000-8000-000000000002', 'status', 'public',
   '{"text": "Pia is around"}'),
  ('11d00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000011', 'gallery', 'connections',
   '{"image_path": "11b00000-0000-4000-8000-000000000011/gallery/g11.jpg"}'),
  ('11d00000-0000-4000-8000-000000000012', '11b00000-0000-4000-8000-000000000011', 'story', 'circles', '{"text": "h12"}'),
  ('11d00000-0000-4000-8000-000000000013', '11b00000-0000-4000-8000-000000000011', 'gallery', 'circles',
   '{"image_path": "11b00000-0000-4000-8000-000000000011/gallery/g13.jpg"}'),
  ('11d00000-0000-4000-8000-000000000014', '11b00000-0000-4000-8000-000000000011', 'writing', 'public',
   '{"title": "Menu", "body": "Open every day"}');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, created_at) values
  ('11d00000-0000-4000-8000-000000000008', '11b00000-0000-4000-8000-000000000001', 'story', 'connections',
   '{"text": "s08"}', now() - interval '25 hours');
insert into public.item_circles (content_item_id, circle_id) values
  ('11d00000-0000-4000-8000-000000000003', '11c00000-0000-4000-8000-000000000001'),
  ('11d00000-0000-4000-8000-000000000004', '11c00000-0000-4000-8000-000000000002'),
  ('11d00000-0000-4000-8000-000000000004', '11c00000-0000-4000-8000-000000000001'),
  ('11d00000-0000-4000-8000-000000000005', '11c00000-0000-4000-8000-000000000002'),
  ('11d00000-0000-4000-8000-000000000009', '11c00000-0000-4000-8000-000000000002'),
  ('11d00000-0000-4000-8000-000000000013', '11c00000-0000-4000-8000-000000000003');
insert into public.item_circles (content_item_id, circle_id)
select '11d00000-0000-4000-8000-000000000012', c.id from public.circles c
where c.owner_profile_id = '11b00000-0000-4000-8000-000000000011' and c.is_all_followers;
insert into public.vouches (id, author_profile_id, subject_profile_id, body, audience, top8_position) values
  ('11f00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000002', 'Pia is generous', 'public', null),
  ('11f00000-0000-4000-8000-000000000002', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000003', 'Kai is patient', 'connections', 2),
  ('11f00000-0000-4000-8000-000000000003', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000004', 'Ned is precise', 'circles', 1),
  ('11f00000-0000-4000-8000-000000000004', '11b00000-0000-4000-8000-000000000002',
   '11b00000-0000-4000-8000-000000000001', 'Ola shows up', 'public', null),
  ('11f00000-0000-4000-8000-000000000005', '11b00000-0000-4000-8000-000000000003',
   '11b00000-0000-4000-8000-000000000001', 'Ola is kind', 'connections', null),
  ('11f00000-0000-4000-8000-000000000006', '11b00000-0000-4000-8000-000000000004',
   '11b00000-0000-4000-8000-000000000001', 'Ola plans well', 'connections', null),
  ('11f00000-0000-4000-8000-000000000007', '11b00000-0000-4000-8000-000000000002',
   '11b00000-0000-4000-8000-000000000004', 'Ned is calm', 'public', null),
  ('11f00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000007',
   '11b00000-0000-4000-8000-000000000011', 'Great coffee', 'public', null),
  ('11f00000-0000-4000-8000-000000000012', '11b00000-0000-4000-8000-000000000012',
   '11b00000-0000-4000-8000-000000000011', 'Pays on time', 'connections', null);
insert into public.item_circles (vouch_id, circle_id) values
  ('11f00000-0000-4000-8000-000000000003', '11c00000-0000-4000-8000-000000000001');
-- The insert guard always starts a vouch unhidden; the trusted caller hides two afterwards.
update public.vouches set hidden_by_subject = true
where id in ('11f00000-0000-4000-8000-000000000002', '11f00000-0000-4000-8000-000000000005');

select lives_ok($$ set constraints all immediate $$, 'the fixtures pass every deferred check');
set constraints all deferred;
select is((select count(*)::int from public.vouches
           where author_profile_id::text like '11b%' and hidden_by_subject), 2,
  'two fixture vouches are hidden by their subjects');

-- Expected pages. va_items names each page item; va_viewers lists every simulated viewer of each
-- page with the codes that viewer must see. Readable by the API roles for the checks below.
create temporary table va_items (code text primary key, section text not null, id uuid not null) on commit drop;
insert into va_items values
  ('d01', 'content', '11d00000-0000-4000-8000-000000000001'),
  ('d02', 'content', '11d00000-0000-4000-8000-000000000002'),
  ('d03', 'content', '11d00000-0000-4000-8000-000000000003'),
  ('d04', 'content', '11d00000-0000-4000-8000-000000000004'),
  ('d05', 'content', '11d00000-0000-4000-8000-000000000005'),
  ('d06', 'content', '11d00000-0000-4000-8000-000000000006'),
  ('d07', 'content', '11d00000-0000-4000-8000-000000000007'),
  ('d08', 'content', '11d00000-0000-4000-8000-000000000008'),
  ('d09', 'content', '11d00000-0000-4000-8000-000000000009'),
  ('f02', 'top8', '11f00000-0000-4000-8000-000000000002'),
  ('f03', 'top8', '11f00000-0000-4000-8000-000000000003'),
  ('f04', 'received', '11f00000-0000-4000-8000-000000000004'),
  ('f06', 'received', '11f00000-0000-4000-8000-000000000006'),
  ('d11', 'content', '11d00000-0000-4000-8000-000000000011'),
  ('d12', 'content', '11d00000-0000-4000-8000-000000000012'),
  ('d13', 'content', '11d00000-0000-4000-8000-000000000013'),
  ('d14', 'content', '11d00000-0000-4000-8000-000000000014'),
  ('f11', 'received', '11f00000-0000-4000-8000-000000000011'),
  ('f12', 'received', '11f00000-0000-4000-8000-000000000012');
create temporary table va_viewers (page text, vname text, owner uuid, viewer uuid, codes text[],
                                   primary key (page, vname)) on commit drop;
insert into va_viewers values
  ('Ola', 'Ola (the owner)', '11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000001',
   array['d01','d02','d03','d04','d05','d06','d07','d08','d09','f02','f03','f04','f06']),
  ('Ola', 'Pia (connection in the inner circle)', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000002',
   array['d01','d02','d03','d04','d06','d07','f02','f03','f04','f06']),
  ('Ola', 'Kai (connection in the work circle)', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000003',
   array['d01','d02','d04','d05','d06','d07','d09','f02','f04']),
  ('Ola', 'Ned (connection in no circle)', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000004',
   array['d01','d02','d06','d07','f02','f03','f04','f06']),
  ('Ola', 'Tom (stranger with a pending request)', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000005', array['d01','d06','d07','f04']),
  ('Ola', 'Vic (a follower of another page)', '11b00000-0000-4000-8000-000000000001',
   '11b00000-0000-4000-8000-000000000007', array['d01','d06','d07','f04']),
  ('Ola', 'signed out', '11b00000-0000-4000-8000-000000000001', null, array['d01','d06','d07','f04']),
  ('Hub', 'Hub (the owner)', '11b00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000011',
   array['d11','d12','d13','d14','f11','f12']),
  ('Hub', 'Vic (follower)', '11b00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000007',
   array['d11','d12','d14','f11']),
  ('Hub', 'Mill (connected business in suppliers)', '11b00000-0000-4000-8000-000000000011',
   '11b00000-0000-4000-8000-000000000012', array['d11','d13','d14','f11','f12']),
  ('Hub', 'Uma (manager''s person profile, not a follower)', '11b00000-0000-4000-8000-000000000011',
   '11b00000-0000-4000-8000-000000000006', array['d14','f11']),
  ('Hub', 'signed out', '11b00000-0000-4000-8000-000000000011', null, array['d14','f11']);
-- Every row view_as returned, captured by the signed in owners below.
create temporary table va_rows (
  owner uuid, vname text, viewer uuid,
  section text, item_id uuid, content_type public.content_type, author_profile_id uuid,
  subject_profile_id uuid, audience public.audience, details jsonb, body text, top8_position smallint,
  created_at timestamptz, expires_at timestamptz, story_label_kind public.story_label_kind,
  story_label_text text
) on commit drop;
grant select on va_items, va_viewers to anon, authenticated;
grant select, insert on va_rows to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Catalog (Req 21.4, 21.7, 21.8, 22.3; D-1, DR-4).
-- ---------------------------------------------------------------------------------------------
select volatility_is(s, 'page_items', array['uuid', 'uuid'], 'stable', s || '.page_items is stable')
from unnest(array['private', 'public']) as s;
select volatility_is('public', 'view_as', array['uuid', 'uuid'], 'stable', 'public.view_as is stable');
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array['private.page_items(uuid, uuid)', 'public.page_items(uuid, uuid)',
                  'public.view_as(uuid, uuid)']) as f;
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = f::regprocedure)) c where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array['private.page_items(uuid, uuid)', 'public.page_items(uuid, uuid)',
                  'public.view_as(uuid, uuid)']) as f;
select ok(has_function_privilege('authenticated', 'public.view_as(uuid, uuid)', 'execute'),
  'authenticated can execute public.view_as');
select ok(not has_function_privilege(r, 'public.view_as(uuid, uuid)', 'execute'),
  r || ' cannot execute public.view_as (Req 21.7)')
from unnest(array['public', 'anon']) as r;
select ok(has_function_privilege(r, 'public.page_items(uuid, uuid)', 'execute'),
  r || ' can execute public.page_items (D-1)')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public', 'public.page_items(uuid, uuid)', 'execute'),
  'public cannot execute public.page_items');
select ok(not has_function_privilege(r, 'private.page_items(uuid, uuid)', 'execute'),
  r || ' cannot execute private.page_items')
from unnest(array['public', 'anon', 'authenticated']) as r;
-- The return signature holds no circle id, name or link (Req 21.8).
select is(pg_catalog.pg_get_function_result(f::regprocedure),
  'TABLE(section text, item_id uuid, content_type content_type, author_profile_id uuid, '
  'subject_profile_id uuid, audience audience, details jsonb, body text, top8_position smallint, '
  'created_at timestamp with time zone, expires_at timestamp with time zone, '
  'story_label_kind story_label_kind, story_label_text text)',
  f || ' returns the page columns only')
from unnest(array['private.page_items(uuid, uuid)', 'public.page_items(uuid, uuid)',
                  'public.view_as(uuid, uuid)']) as f;
select is_empty(
  $$ select p.oid::regprocedure, a.name
     from pg_catalog.pg_proc p cross join pg_catalog.unnest(p.proargnames) as a(name)
     where p.oid in ('private.page_items(uuid, uuid)'::regprocedure, 'public.page_items(uuid, uuid)'::regprocedure,
                     'public.view_as(uuid, uuid)'::regprocedure)
       and a.name like '%circle%' $$,
  'no argument or result column of the three functions names a circle (Req 21.8)');
select ok((select prosrc from pg_catalog.pg_proc where oid = 'private.page_items(uuid, uuid)'::regprocedure)
            like '%private.can_view(ci.id, p_viewer)%'
          and (select prosrc from pg_catalog.pg_proc where oid = 'private.page_items(uuid, uuid)'::regprocedure)
            like '%private.can_view(v.id, p_viewer)%'
          and (select prosrc from pg_catalog.pg_proc where oid = 'private.page_items(uuid, uuid)'::regprocedure)
            not similar to '%(public.circles|public.circle_members|public.item_circles)%',
  'private.page_items decides visibility through can_view and reads no circle table (Req 21.4, 21.8)');
select ok((select prosrc from pg_catalog.pg_proc where oid = 'public.view_as(uuid, uuid)'::regprocedure)
            like '%private.page_items(p_owner_profile_id, p_simulated_viewer)%',
  'view_as lists the page through private.page_items with the simulated viewer unchanged (Req 21.4)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ola, the page owner, in the canary order (DR-1).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ola claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ola');

-- Each simulated viewer sees exactly the expected items (Req 21.1, 21.3, 21.5, 14.19, 14.20).
select set_eq(
  pg_catalog.format('select section, item_id from public.view_as(%L, %L)', v.owner, v.viewer),
  pg_catalog.format('select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
                     where v.page = %L and v.vname = %L', v.page, v.vname),
  'view_as of Ola''s page as ' || v.vname || ' returns exactly the expected items')
from va_viewers v where v.page = 'Ola' order by v.vname;

-- The story label is the simulated viewer's (Req 21.6).
select set_eq(
  $$ select item_id, story_label_kind::text, story_label_text
     from public.view_as('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000002')
     where content_type = 'story' $$,
  $$ values ('11d00000-0000-4000-8000-000000000003'::uuid, 'member_label'::text, 'Inner folk'::text),
            ('11d00000-0000-4000-8000-000000000004'::uuid, 'member_label'::text, 'Inner folk'::text),
            ('11d00000-0000-4000-8000-000000000007'::uuid, null::text, null::text) $$,
  'as Pia, the stories carry Pia''s member label, not the owner''s empty one');
select set_eq(
  $$ select item_id, story_label_kind::text, story_label_text
     from public.view_as('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000003')
     where content_type = 'story' $$,
  $$ values ('11d00000-0000-4000-8000-000000000004'::uuid, 'shared_with_you'::text, null::text),
            ('11d00000-0000-4000-8000-000000000005'::uuid, 'only_for_you'::text, null::text),
            ('11d00000-0000-4000-8000-000000000007'::uuid, null::text, null::text) $$,
  'as Kai, the stories carry shared_with_you and only_for_you, and the switched off circle gives no text');
select set_eq(
  $$ select item_id, story_label_kind::text, story_label_text
     from public.view_as('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000001')
     where content_type = 'story' $$,
  $$ values ('11d00000-0000-4000-8000-000000000003'::uuid, null::text, null::text),
            ('11d00000-0000-4000-8000-000000000004'::uuid, null::text, null::text),
            ('11d00000-0000-4000-8000-000000000005'::uuid, null::text, null::text),
            ('11d00000-0000-4000-8000-000000000007'::uuid, null::text, null::text),
            ('11d00000-0000-4000-8000-000000000008'::uuid, null::text, null::text) $$,
  'as the owner, every story is listed, the expired one too, with no label (NQ-3)');
select set_eq(
  $$ select item_id, story_label_kind::text, story_label_text
     from public.view_as('11b00000-0000-4000-8000-000000000001', null)
     where content_type = 'story' $$,
  $$ values ('11d00000-0000-4000-8000-000000000007'::uuid, null::text, null::text) $$,
  'signed out, only the public story is listed, with no label');

-- Capture every view_as row of Ola's page for the checks run as the test owner below.
select lives_ok(
  $$ insert into va_rows
     select v.owner, v.vname, v.viewer, x.*
     from va_viewers v cross join lateral public.view_as(v.owner, v.viewer) x
     where v.page = 'Ola' $$,
  'Ola''s view_as rows are captured for every simulated viewer');

-- Only the owner may call view_as (Req 21.2).
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000002', null) $$,
  'PT403', 'view_as.not_owner', 'Ola cannot preview Pia''s page (Req 21.2)');
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000011',
                                                 '11b00000-0000-4000-8000-000000000007') $$,
  'PT403', 'view_as.not_owner', 'Ola cannot preview a business she does not manage');
select throws_ok($$ select * from public.view_as(null, null) $$,
  'PT403', 'view_as.not_owner', 'a null page id is refused');
-- Even the owner cannot impersonate through page_items: another profile's id is signed out.
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001',
                                                    '11b00000-0000-4000-8000-000000000002') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'signed out' $$,
  'page_items for Ola asking as Pia lists the signed out page (Req 20.15)');
select throws_ok($$ select * from private.page_items('11b00000-0000-4000-8000-000000000001', null) $$,
  '42501', null, 'authenticated cannot call private.page_items');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Uma, who owns Hub: view_as while acting as the business.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-0000-4000-8000-000000000006', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Uma claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-0000-4000-8000-000000000006'::uuid, 'auth.uid() is Uma');

select set_eq(
  pg_catalog.format('select section, item_id from public.view_as(%L, %L)', v.owner, v.viewer),
  pg_catalog.format('select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
                     where v.page = %L and v.vname = %L', v.page, v.vname),
  'Uma, acting as Hub, previews Hub''s page as ' || v.vname)
from va_viewers v where v.page = 'Hub' order by v.vname;
select set_eq(
  $$ select item_id, story_label_kind::text, story_label_text
     from public.view_as('11b00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000007')
     where content_type = 'story' $$,
  $$ values ('11d00000-0000-4000-8000-000000000012'::uuid, 'shared_with_you'::text, null::text) $$,
  'as the follower Vic, the all followers story carries shared_with_you (another follower exists)');
select lives_ok(
  $$ insert into va_rows
     select v.owner, v.vname, v.viewer, x.*
     from va_viewers v cross join lateral public.view_as(v.owner, v.viewer) x
     where v.page = 'Hub' $$,
  'Hub''s view_as rows are captured for every simulated viewer');
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000001', null) $$,
  'PT403', 'view_as.not_owner', 'Uma cannot preview Ola''s page');
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000012', null) $$,
  'PT403', 'view_as.not_owner', 'Uma cannot preview the connected business Mill');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Vic, a follower of Hub: the business page through page_items.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-0000-4000-8000-000000000007', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Vic claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-0000-4000-8000-000000000007'::uuid, 'auth.uid() is Vic');

select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000011',
                                                    '11b00000-0000-4000-8000-000000000007') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Hub' and v.vname = 'Vic (follower)' $$,
  'Vic as himself sees Hub''s page as a follower (Req 20.6)');
select results_eq(
  $$ select story_label_kind::text, story_label_text
     from public.page_items('11b00000-0000-4000-8000-000000000011', '11b00000-0000-4000-8000-000000000007')
     where item_id = '11d00000-0000-4000-8000-000000000012' $$,
  $$ values ('shared_with_you'::text, null::text) $$,
  'page_items gives Vic the same story label as the preview');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000011',
                                                    '11b00000-0000-4000-8000-000000000012') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Hub' and v.vname = 'signed out' $$,
  'Vic asking as Mill gets the signed out page (Req 20.15)');
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000011',
                                                 '11b00000-0000-4000-8000-000000000007') $$,
  'PT403', 'view_as.not_owner', 'a follower cannot preview the business page (Req 21.2)');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Pia: page_items trusts only her own id.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '11111111-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Pia claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '11111111-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Pia');

select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001',
                                                    '11b00000-0000-4000-8000-000000000002') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'Pia (connection in the inner circle)' $$,
  'Pia as herself sees Ola''s page exactly as Ola''s preview of Pia');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001',
                                                    '11b00000-0000-4000-8000-000000000003') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'signed out' $$,
  'Pia asking as Kai gets the signed out page');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001',
                                                    '11b00000-0000-4000-8000-000000000001') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'signed out' $$,
  'Pia asking as the owner gets the signed out page');
select is_empty(
  $$ select 1 from public.page_items('11b00000-0000-4000-8000-000000000001', '11b00000-0000-4000-8000-000000000003')
     where audience is not null or story_label_kind is not null $$,
  'the untrusted id reveals neither audiences nor Kai''s labels');
select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000001',
                                                 '11b00000-0000-4000-8000-000000000002') $$,
  'PT403', 'view_as.not_owner', 'Pia cannot preview Ola''s page, even as herself (Req 21.2)');

-- ---------------------------------------------------------------------------------------------
-- Signed out (anon).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select * from public.view_as('11b00000-0000-4000-8000-000000000001', null) $$,
  '42501', null, 'anon cannot execute view_as (Req 21.7)');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001', null) $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'signed out' $$,
  'anon lists Ola''s signed out page (D-1)');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000001',
                                                    '11b00000-0000-4000-8000-000000000002') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Ola' and v.vname = 'signed out' $$,
  'anon asking as Pia gets the signed out page');
select set_eq(
  $$ select section, item_id from public.page_items('11b00000-0000-4000-8000-000000000011',
                                                    '11b00000-0000-4000-8000-000000000007') $$,
  $$ select i.section, i.id from va_items i join va_viewers v on i.code = any(v.codes)
     where v.page = 'Hub' and v.vname = 'signed out' $$,
  'anon asking as the follower Vic gets Hub''s signed out page');
select throws_ok($$ select * from private.page_items('11b00000-0000-4000-8000-000000000001', null) $$,
  '42501', null, 'anon cannot call private.page_items');

-- ---------------------------------------------------------------------------------------------
-- Back to the test owner: the captured view_as rows against private.page_items and can_view.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);

select is((select count(distinct (owner, vname))::int from va_rows), 12,
  'view_as rows were captured for all twelve simulated viewers');
-- view_as is exactly private.page_items for the same viewer, every column (Req 21.1, 21.4).
select bag_eq(
  $$ select owner, vname, section, item_id, content_type, author_profile_id, subject_profile_id, audience,
            details, body, top8_position, created_at, expires_at, story_label_kind, story_label_text
     from va_rows $$,
  $$ select v.owner, v.vname, p.section, p.item_id, p.content_type, p.author_profile_id, p.subject_profile_id,
            p.audience, p.details, p.body, p.top8_position, p.created_at, p.expires_at, p.story_label_kind,
            p.story_label_text
     from va_viewers v cross join lateral private.page_items(v.owner, v.viewer) p $$,
  'for every simulated viewer, view_as returns the same rows as private.page_items called by the test owner');
-- Property 6: exactly the page items that can_view allows for that viewer, never more.
select bag_eq(
  $$ select owner, vname, item_id from va_rows $$,
  $$ select v.owner, v.vname, x.id
     from va_viewers v
     cross join lateral (
       select ci.id from public.content_items ci where ci.owner_profile_id = v.owner
       union all
       select vo.id from public.vouches vo where vo.author_profile_id = v.owner and vo.top8_position is not null
       union all
       select vo.id from public.vouches vo where vo.subject_profile_id = v.owner and not vo.hidden_by_subject
     ) x
     where private.can_view(x.id, v.viewer) $$,
  'view_as returns exactly the page items can_view allows for each viewer (Property 6, Req 21.1, 21.5)');
select is_empty(
  $$ select vname, item_id from va_rows where not private.can_view(item_id, viewer) $$,
  'no view_as row is an item the simulated viewer could not see');
select is_empty(
  $$ select vname, item_id from va_rows
     where item_id in ('11d00000-0000-4000-8000-000000000021', '11f00000-0000-4000-8000-000000000001',
                       '11f00000-0000-4000-8000-000000000005', '11f00000-0000-4000-8000-000000000007') $$,
  'another person''s status, an unfeatured vouch, a hidden received vouch and a vouch between others never appear');
-- Audience is returned only to the owner (D-3).
select is_empty(
  $$ select vname, item_id from va_rows where viewer is distinct from owner and audience is not null $$,
  'no simulated viewer other than the owner gets an audience');
select isnt_empty(
  $$ select 1 from va_rows where viewer = owner and audience = 'circles' $$,
  'the owner previewing as herself sees her audiences');
-- Labels: the simulated viewer's own label on stories, none on anything else (Req 21.6).
select ok((select count(*) from va_rows where story_label_kind = 'member_label') >= 2
          and (select count(*) from va_rows where story_label_kind = 'only_for_you') >= 1
          and (select count(*) from va_rows where story_label_kind = 'shared_with_you') >= 2,
  'the captured rows hold labels of every kind, so the label checks are not vacuous');
select is_empty(
  $$ select r.vname, r.item_id from va_rows r
     where r.content_type = 'story'
       and (r.story_label_kind::text || ':' || coalesce(r.story_label_text, '')) is distinct from
           (select s.kind::text || ':' || coalesce(s.label, '') from private.story_label(r.item_id, r.viewer) s) $$,
  'every story row carries the label story_label gives the simulated viewer (Req 21.6)');
select is_empty(
  $$ select vname, item_id from va_rows
     where content_type is distinct from 'story' and (story_label_kind is not null or story_label_text is not null) $$,
  'no row other than a story carries a label');
-- The sweep (Req 21.8): no returned value holds a circle private name or a circle id.
select is_empty(
  $$ select r.vname, r.item_id, c.id
     from va_rows r
     cross join public.circles c
     where c.owner_profile_id::text like '11b%'
       and (pg_catalog.strpos(pg_catalog.lower(pg_catalog.row_to_json(r)::text), pg_catalog.lower(c.private_name)) > 0
            or pg_catalog.strpos(pg_catalog.row_to_json(r)::text, c.id::text) > 0) $$,
  'no view_as value contains any circle private name or circle id (Req 21.8)');
select is_empty(
  $$ select v.vname, p.item_id, c.id
     from va_viewers v
     cross join lateral public.page_items(v.owner, v.viewer) p
     cross join public.circles c
     where c.owner_profile_id::text like '11b%'
       and (pg_catalog.strpos(pg_catalog.lower(pg_catalog.row_to_json(p)::text), pg_catalog.lower(c.private_name)) > 0
            or pg_catalog.strpos(pg_catalog.row_to_json(p)::text, c.id::text) > 0) $$,
  'no page_items value contains any circle private name or circle id');

-- Removing a member from a circle removes the item from the next preview at once.
delete from public.circle_members
where circle_id = '11c00000-0000-4000-8000-000000000001'
  and member_profile_id = '11b00000-0000-4000-8000-000000000002';
select set_eq(
  $$ select item_id from private.page_items('11b00000-0000-4000-8000-000000000001',
                                            '11b00000-0000-4000-8000-000000000002') $$,
  $$ select i.id from va_items i where i.code in ('d01','d02','d06','d07','f02','f04','f06') $$,
  'after Pia leaves the inner circle, her preview loses the inner circle story and vouch');

select * from finish();
rollback;
