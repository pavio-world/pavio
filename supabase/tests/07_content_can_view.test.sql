-- Content items, vouches, item circle links and can_view: every can_view branch, the content and
-- vouch guards, the deferred circles checks (D-7), the details and path kind checks (NQ-5 and the
-- fix_content_image_path_kind rule), RLS reads filtered by can_view and column silence (D-3).
-- Spec 00 Req 11.4 to 11.13, 11.15, 20.2 to 20.8, 20.10 to 20.13, 20.15, 25.1 to 25.4; D-3, D-7.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(254);

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims (a trusted caller, so stories can be back-dated).
-- People: Ann (owner of most items), Bo, Cy, Di (a stranger to Ann), Eli (owns the business Shop)
-- and Fay (follows Shop).
-- Accepted connections: Ann and Bo, Cy and Ann. Fay follows Shop.
-- Ann's circles: inner (Bo), work (Cy). Bo's circle: mates (Ann). Ann's group: book club (Di).
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('07070707-0000-4000-8000-000000000001', 'ann.cv@example.invalid'),
  ('07070707-0000-4000-8000-000000000002', 'bo.cv@example.invalid'),
  ('07070707-0000-4000-8000-000000000003', 'cy.cv@example.invalid'),
  ('07070707-0000-4000-8000-000000000004', 'di.cv@example.invalid'),
  ('07070707-0000-4000-8000-000000000005', 'eli.cv@example.invalid'),
  ('07070707-0000-4000-8000-000000000006', 'fay.cv@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('07b00000-0000-4000-8000-000000000001', 'person', '07070707-0000-4000-8000-000000000001', 'ann_cv', 'Ann'),
  ('07b00000-0000-4000-8000-000000000002', 'person', '07070707-0000-4000-8000-000000000002', 'bo_cv', 'Bo'),
  ('07b00000-0000-4000-8000-000000000003', 'person', '07070707-0000-4000-8000-000000000003', 'cy_cv', 'Cy'),
  ('07b00000-0000-4000-8000-000000000004', 'person', '07070707-0000-4000-8000-000000000004', 'di_cv', 'Di'),
  ('07b00000-0000-4000-8000-000000000005', 'person', '07070707-0000-4000-8000-000000000005', 'eli_cv', 'Eli'),
  ('07b00000-0000-4000-8000-000000000006', 'person', '07070707-0000-4000-8000-000000000006', 'fay_cv', 'Fay');
insert into public.profiles (id, type, handle, display_name) values
  ('07b00000-0000-4000-8000-000000000011', 'business', 'shop_cv', 'Eli''s Shop');
insert into public.profile_managers (profile_id, user_id, role) values
  ('07b00000-0000-4000-8000-000000000011', '07070707-0000-4000-8000-000000000005', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('07b00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000002', 'connection'),
  ('07b00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001', 'connection'),
  ('07b00000-0000-4000-8000-000000000006', '07b00000-0000-4000-8000-000000000011', 'follow');
update public.relationships set status = 'accepted'
where type = 'connection'
  and requester_profile_id in ('07b00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000003');
insert into public.circles (id, owner_profile_id, private_name) values
  ('07c00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000001', 'inner'),
  ('07c00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000001', 'work'),
  ('07c00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000002', 'mates');
insert into public.circle_members (circle_id, member_profile_id) values
  ('07c00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000002'),
  ('07c00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000003'),
  ('07c00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000001');
insert into public.groups (id, owner_profile_id, name) values
  ('07e00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000001', 'book club');
insert into public.group_members (group_id, profile_id) values
  ('07e00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000004');

-- Ann's items (audience omitted where the default is under test).
--   01 writing, default audience          02 status, default audience
--   03 gallery, circles (inner)           04 gallery, group (book club)
--   05 story, public, live                06 story, connections, live
--   07 story, public, expired             08 gallery, public, child of 03
-- Shop's items: 11 status, default audience; 12 gallery, circles (all followers).
insert into public.content_items (id, owner_profile_id, content_type, details) values
  ('07d00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000001', 'writing',
   '{"title": "Hello", "body": "First post"}'),
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000001', 'status',
   '{"text": "on leave"}'),
  ('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000011', 'status',
   '{"text": "open today"}');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, group_id) values
  ('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/inner.jpg"}', null),
  ('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000001', 'gallery', 'group',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/club.jpg"}',
   '07e00000-0000-4000-8000-000000000001'),
  ('07d00000-0000-4000-8000-000000000005', '07b00000-0000-4000-8000-000000000001', 'story', 'public',
   '{"text": "live story"}', null),
  ('07d00000-0000-4000-8000-000000000006', '07b00000-0000-4000-8000-000000000001', 'story', 'connections',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/story/s1.jpg"}', null),
  ('07d00000-0000-4000-8000-000000000012', '07b00000-0000-4000-8000-000000000011', 'gallery', 'circles',
   '{"image_path": "07b00000-0000-4000-8000-000000000011/gallery/regulars.jpg"}', null);
insert into public.content_items (id, owner_profile_id, content_type, audience, details, created_at) values
  ('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000001', 'story', 'public',
   '{"text": "old story"}', now() - interval '25 hours');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, parent_id) values
  ('07d00000-0000-4000-8000-000000000008', '07b00000-0000-4000-8000-000000000001', 'gallery', 'public',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/child.jpg"}',
   '07d00000-0000-4000-8000-000000000003');
insert into public.item_circles (content_item_id, circle_id) values
  ('07d00000-0000-4000-8000-000000000003', '07c00000-0000-4000-8000-000000000001');
insert into public.item_circles (content_item_id, circle_id)
select '07d00000-0000-4000-8000-000000000012', c.id from public.circles c
where c.owner_profile_id = '07b00000-0000-4000-8000-000000000011' and c.is_all_followers;

-- Vouches: 1 Ann about Bo, circles (work); 2 Cy about Ann, default audience; 3 Bo about Ann,
-- connections (evaluated against Bo's relationships, NQ-1).
insert into public.vouches (id, author_profile_id, subject_profile_id, body, audience) values
  ('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000001',
   '07b00000-0000-4000-8000-000000000002', 'Bo is a great builder', 'circles'),
  ('07f00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002',
   '07b00000-0000-4000-8000-000000000001', 'Ann knows her numbers', 'connections');
insert into public.vouches (id, author_profile_id, subject_profile_id, body) values
  ('07f00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000003',
   '07b00000-0000-4000-8000-000000000001', 'Ann ships on time');
insert into public.item_circles (vouch_id, circle_id) values
  ('07f00000-0000-4000-8000-000000000001', '07c00000-0000-4000-8000-000000000002');

-- Every deferred check passes for the fixtures, and running them now means a later
-- set constraints all immediate only fires the events of the statement under test.
select lives_ok($$ set constraints all immediate $$, 'the fixtures pass every deferred check');
set constraints all deferred;

-- ---------------------------------------------------------------------------------------------
-- Catalog: RLS, policies, grants, triggers and functions (Req 11.15, 20.14, 22.1 to 22.5; D-3, D-7).
-- ---------------------------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = t::regclass), 'RLS is enabled on ' || t)
from unnest(array['public.content_items', 'public.vouches', 'public.item_circles']) as t;
select policies_are('public', 'content_items', array[
  'content_items_anon_select', 'content_items_authenticated_select', 'content_items_authenticated_insert',
  'content_items_authenticated_update', 'content_items_authenticated_delete'
], 'content_items has exactly its five policies');
select policies_are('public', 'vouches', array[
  'vouches_anon_select', 'vouches_authenticated_select', 'vouches_authenticated_insert',
  'vouches_authenticated_update', 'vouches_authenticated_delete'
], 'vouches has exactly its five policies');
select policies_are('public', 'item_circles', array[
  'item_circles_authenticated_select', 'item_circles_authenticated_insert', 'item_circles_authenticated_delete'
], 'item_circles has exactly its three policies');
-- Every read policy is can_view and nothing else (Req 11.15).
select ok((select qual from pg_policies where schemaname = 'public' and policyname = p) like '%can_view(id%',
  p || ' reads through can_view')
from unnest(array['content_items_anon_select', 'content_items_authenticated_select',
                  'vouches_anon_select', 'vouches_authenticated_select']) as p;
select table_privs_are('public', t, 'anon', array[]::text[], 'anon has no table privilege on ' || t)
from unnest(array['content_items', 'vouches', 'item_circles']) as t;
select ok(not has_any_column_privilege('anon', t, p), 'anon has no column ' || p || ' on ' || t)
from unnest(array['public.content_items', 'public.vouches', 'public.item_circles']) as t
cross join unnest(array['INSERT', 'UPDATE']) as p;
-- D-3: audience and hidden_by_subject are never readable by the API roles.
select ok(not has_column_privilege(r, 'public.content_items', 'audience', 'SELECT'),
  r || ' cannot select content_items.audience')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_column_privilege(r, 'public.vouches', c, 'SELECT'), r || ' cannot select vouches.' || c)
from unnest(array['anon', 'authenticated']) as r
cross join unnest(array['audience', 'hidden_by_subject']) as c;
-- The API cannot write the times that decide expiry.
select ok(not has_column_privilege('authenticated', 'public.content_items', c, p),
  'authenticated cannot ' || p || ' content_items.' || c)
from unnest(array['created_at', 'expires_at']) as c
cross join unnest(array['INSERT', 'UPDATE']) as p;
select trigger_is('public', v.t, v.trg, 'private', v.fn, v.trg || ' calls private.' || v.fn)
from (values ('content_items', 'content_items_before_write', 'content_items_before_write'),
             ('content_items', 'content_items_circles_present', 'content_items_circles_present'),
             ('vouches', 'vouches_circles_present', 'vouches_circles_present'),
             ('item_circles', 'item_circles_guard', 'item_circles_guard'),
             ('item_circles', 'item_circles_last_link', 'item_circles_last_link')) as v(t, trg, fn);
select ok((select tgdeferrable and tginitdeferred from pg_catalog.pg_trigger
           where tgname = trg and tgrelid = t::regclass),
  trg || ' is deferrable initially deferred')
from (values ('public.content_items', 'content_items_circles_present'),
             ('public.vouches', 'vouches_circles_present'),
             ('public.item_circles', 'item_circles_last_link')) as v(t, trg);
select volatility_is('private', 'can_view', array['uuid', 'uuid'], 'stable', 'private.can_view is stable');
select volatility_is('public', 'can_view', array['uuid', 'uuid'], 'stable', 'public.can_view is stable');
select ok((select prosecdef from pg_catalog.pg_proc where oid = f::regprocedure), f || ' is security definer')
from unnest(array['private.can_view(uuid, uuid)', 'public.can_view(uuid, uuid)']) as f;
select ok(has_function_privilege(r, 'public.can_view(uuid, uuid)', 'execute'), r || ' can execute public.can_view')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege(r, 'private.can_view(uuid, uuid)', 'execute'),
  r || ' cannot execute private.can_view')
from unnest(array['public', 'anon', 'authenticated']) as r;
-- The details validator after fix_content_image_path_kind: same volatility, search_path and grants.
select volatility_is('private', 'content_details_valid', array['public.content_type', 'jsonb'], 'immutable',
  'content_details_valid is still immutable');
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc
                    where oid = 'private.content_details_valid(public.content_type, jsonb)'::regprocedure)) c
                  where c = 'search_path=""'),
  'content_details_valid still sets an empty search_path');
select ok(has_function_privilege(r, 'private.content_details_valid(public.content_type, jsonb)', 'execute'),
  r || ' can still execute content_details_valid (the check runs as the writer)')
from unnest(array['anon', 'authenticated']) as r;
select ok(not has_function_privilege('public', 'private.content_details_valid(public.content_type, jsonb)', 'execute'),
  'public cannot execute content_details_valid');

-- ---------------------------------------------------------------------------------------------
-- Defaults and write checks (Req 11.4 to 11.6, 11.9, 11.10).
-- ---------------------------------------------------------------------------------------------
select is((select audience::text from public.content_items where id = '07d00000-0000-4000-8000-000000000001'),
  'public', 'writing created without an audience is public (Req 11.6)');
select is((select audience::text from public.content_items where id = '07d00000-0000-4000-8000-000000000002'),
  'connections', 'a status created without an audience gets connections (Req 11.4)');
select is((select audience::text from public.content_items where id = '07d00000-0000-4000-8000-000000000011'),
  'connections', 'a business item created without an audience gets connections');
select is((select audience::text from public.vouches where id = '07f00000-0000-4000-8000-000000000002'),
  'public', 'a vouch created without an audience is public (NQ-2)');
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, audience, details)
                    values ('07b00000-0000-4000-8000-000000000001', 'writing', 'connections',
                            '{"title": "t", "body": "b"}') $$,
  '23514', null, 'writing with a connections audience is rejected (Req 11.5)');
select throws_ok($$ update public.content_items set audience = 'circles'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  '23514', null, 'writing cannot be moved off public (Req 11.5)');
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, audience, details)
                    values ('07b00000-0000-4000-8000-000000000001', 'gallery', 'group',
                            '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/g.jpg"}') $$,
  '23514', null, 'a group audience without a group is rejected (Req 11.9)');
select results_eq(
  $$ select expires_at = created_at + interval '24 hours' from public.content_items
     where id in ('07d00000-0000-4000-8000-000000000005', '07d00000-0000-4000-8000-000000000007') order by id $$,
  $$ values (true), (true) $$,
  'every story expires 24 hours after it was created (Req 11.10)');
select is_empty($$ select 1 from public.content_items where content_type <> 'story' and expires_at is not null
                   and owner_profile_id = '07b00000-0000-4000-8000-000000000001' $$,
  'no other type gets an expiry (Req 11.14)');
select ok((select expires_at < now() from public.content_items where id = '07d00000-0000-4000-8000-000000000007'),
  'the back-dated story is expired');
select throws_ok($$ update public.content_items set owner_profile_id = '07b00000-0000-4000-8000-000000000002'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  'PT422', 'content.immutable', 'an item cannot move to another owner');
select throws_ok($$ update public.content_items set content_type = 'status', details = '{"text": "x"}'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  'PT422', 'content.immutable', 'an item cannot change its type');

-- ---------------------------------------------------------------------------------------------
-- can_view, every branch, as a trusted caller (Req 20.2 to 20.8, 20.11 to 20.13).
-- ---------------------------------------------------------------------------------------------
select is(public.can_view(v.item, v.viewer), v.expected, v.label)
from (values
  -- Writing (public): everyone, signed out included.
  ('07d00000-0000-4000-8000-000000000001'::uuid, '07b00000-0000-4000-8000-000000000001'::uuid, true,
   'owner sees her writing'),
  ('07d00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000004', true,
   'a stranger sees public writing (Req 20.5)'),
  ('07d00000-0000-4000-8000-000000000001', null, true, 'a null viewer sees public writing (Req 20.5)'),
  -- Connections.
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000001', true,
   'owner sees her connections status (Req 20.2)'),
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000002', true,
   'a connection (requester side) sees a connections item (Req 20.6)'),
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000003', true,
   'a connection (target side) sees a connections item'),
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000004', false,
   'a stranger does not see a connections item'),
  ('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000006', false,
   'a follower of another page does not see a person''s connections item'),
  ('07d00000-0000-4000-8000-000000000002', null, false, 'a null viewer does not see a connections item (Req 20.11)'),
  -- Business connections audience includes followers.
  ('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000011', true,
   'the business sees its own connections item'),
  ('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000006', true,
   'a follower sees a business connections item (Req 20.6)'),
  ('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000005', false,
   'the manager''s person profile is not the business viewer'),
  ('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000004', false,
   'a non follower does not see a business connections item'),
  -- Circles.
  ('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001', true,
   'owner sees her circle item'),
  ('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002', true,
   'a member of the linked circle sees the item (Req 20.7)'),
  ('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000003', false,
   'a connection outside the linked circle does not see the item'),
  ('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000004', false,
   'a stranger does not see a circle item'),
  ('07d00000-0000-4000-8000-000000000003', null, false, 'a null viewer does not see a circle item'),
  ('07d00000-0000-4000-8000-000000000012', '07b00000-0000-4000-8000-000000000006', true,
   'a follower is in the all followers audience without a membership row (Req 20.7)'),
  ('07d00000-0000-4000-8000-000000000012', '07b00000-0000-4000-8000-000000000004', false,
   'a non follower is not in the all followers audience'),
  -- Group.
  ('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000001', true,
   'owner sees her group item'),
  ('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000004', true,
   'a group member sees the group item (Req 20.8)'),
  ('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000002', false,
   'a connection outside the group does not see the group item'),
  ('07d00000-0000-4000-8000-000000000004', null, false, 'a null viewer does not see a group item'),
  -- Stories and expiry.
  ('07d00000-0000-4000-8000-000000000005', null, true, 'a null viewer sees a live public story'),
  ('07d00000-0000-4000-8000-000000000006', '07b00000-0000-4000-8000-000000000002', true,
   'a connection sees a live connections story'),
  ('07d00000-0000-4000-8000-000000000006', '07b00000-0000-4000-8000-000000000004', false,
   'a stranger does not see a live connections story'),
  ('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000001', true,
   'the owner still sees her expired story (Req 20.2)'),
  ('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000002', false,
   'a connection does not see an expired public story (Req 20.4)'),
  ('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000004', false,
   'a stranger does not see an expired public story'),
  ('07d00000-0000-4000-8000-000000000007', null, false, 'a null viewer does not see an expired story (Req 20.11)'),
  -- Parent (Req 20.13): a public child of a circle item is seen only by those who see the parent.
  ('07d00000-0000-4000-8000-000000000008', '07b00000-0000-4000-8000-000000000001', true,
   'owner sees the child item'),
  ('07d00000-0000-4000-8000-000000000008', '07b00000-0000-4000-8000-000000000002', true,
   'a viewer of the parent sees the public child'),
  ('07d00000-0000-4000-8000-000000000008', '07b00000-0000-4000-8000-000000000003', false,
   'a viewer who cannot see the parent does not see the public child'),
  ('07d00000-0000-4000-8000-000000000008', null, false, 'a null viewer does not see a public child of a hidden parent'),
  -- Vouches: the author is the owner, the subject always sees (Req 20.3, 20.9).
  ('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000001', true,
   'the author sees her circle vouch'),
  ('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000002', true,
   'the subject sees a vouch even outside its circle (Req 20.3)'),
  ('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000003', true,
   'a member of the author''s linked circle sees the vouch'),
  ('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000004', false,
   'a stranger does not see a circle vouch'),
  ('07f00000-0000-4000-8000-000000000001', null, false, 'a null viewer does not see a circle vouch'),
  ('07f00000-0000-4000-8000-000000000002', null, true, 'a null viewer sees a public vouch'),
  ('07f00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000003', false,
   'a connections vouch is checked against the author''s connections, not the subject''s (Req 20.9)'),
  ('07f00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001', true,
   'the subject of a connections vouch sees it'),
  -- Non-existent ids (Req 20.12).
  ('07d00000-0000-4000-8000-0000000000ff', '07b00000-0000-4000-8000-000000000001', false,
   'a non-existent id is false even for a real profile'),
  ('07d00000-0000-4000-8000-0000000000ff', null, false, 'a non-existent id is false for a null viewer')
) as v(item, viewer, expected, label);
select is(private.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002'),
  public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002'),
  'the public wrapper returns the private decision for a trusted caller');
select lives_ok($$ select public.can_view(null, null) $$, 'can_view never raises, even on a null id');
select is(public.can_view(null, '07b00000-0000-4000-8000-000000000001'), false, 'a null id is never visible');

-- Hiding changes nothing for can_view (Req 20.10).
update public.vouches set hidden_by_subject = true where id = '07f00000-0000-4000-8000-000000000001';
select ok(public.can_view('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000002'),
  'the subject still sees a vouch she hid (Req 20.10)');
select ok(public.can_view('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000003'),
  'a circle member still sees a hidden vouch (Req 20.10)');
select ok(not public.can_view('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000004'),
  'hiding does not widen a vouch to a stranger');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Bo, in the canary order (DR-1): RLS reads are can_view (Req 11.15, 22.4; D-3).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '07070707-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Bo claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '07070707-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Bo');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000002'),
            ('07d00000-0000-4000-8000-000000000003'), ('07d00000-0000-4000-8000-000000000005'),
            ('07d00000-0000-4000-8000-000000000006'), ('07d00000-0000-4000-8000-000000000008') $$,
  'Bo reads exactly the content items can_view allows him');
select set_eq($$ select id from public.vouches $$,
  $$ values ('07f00000-0000-4000-8000-000000000001'::uuid), ('07f00000-0000-4000-8000-000000000002'),
            ('07f00000-0000-4000-8000-000000000003') $$,
  'Bo reads the vouch about him (hidden), the public vouch and his own');
select throws_ok($$ select audience from public.content_items $$, '42501', null,
  'Bo cannot read content_items.audience (D-3)');
select throws_ok($$ select * from public.content_items $$, '42501', null,
  'select * on content_items is refused because audience is not granted');
select throws_ok($$ select audience from public.vouches $$, '42501', null, 'Bo cannot read vouches.audience (D-3)');
select throws_ok($$ select hidden_by_subject from public.vouches $$, '42501', null,
  'Bo cannot read vouches.hidden_by_subject, even on a vouch about him (D-3)');
select is_empty($$ select 1 from public.item_circles $$, 'Bo reads no item circle links of Ann''s items');
-- Untrusted viewer ids (Req 20.15): Bo may evaluate only as himself or as signed out.
select ok(public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002'),
  'Bo evaluating as himself gets his own access');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001'),
  'Bo asking as Ann is treated as a null viewer, not as the owner');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000004'),
  'Bo cannot learn that Di sees the group item');
select ok(public.can_view('07d00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000004'),
  'asking as another profile still sees what a null viewer sees');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Di, a stranger to Ann who is in Ann's group.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '07070707-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Di claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '07070707-0000-4000-8000-000000000004'::uuid, 'auth.uid() is Di');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000004'),
            ('07d00000-0000-4000-8000-000000000005') $$,
  'Di reads the public writing, the live public story and the group item only');
select set_eq($$ select id from public.vouches $$,
  $$ values ('07f00000-0000-4000-8000-000000000002'::uuid) $$, 'Di reads only the public vouch');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000002'),
  'Di asking as Bo is treated as a null viewer (Req 20.15)');
select ok(public.can_view('07d00000-0000-4000-8000-000000000004', '07b00000-0000-4000-8000-000000000004'),
  'Di evaluating as herself sees the group item');
-- Writes need acts_as on the owner (Req 11.16, 25.1).
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, details)
                    values ('07b00000-0000-4000-8000-000000000001', 'writing', '{"title": "x", "body": "y"}') $$,
  '42501', null, 'Di cannot create an item on Ann''s page');
select lives_ok($$ update public.content_items set details = '{"title": "Taken", "body": "over"}'
                   where id = '07d00000-0000-4000-8000-000000000001' $$,
  'Di''s update of Ann''s writing runs but touches nothing');
select lives_ok($$ delete from public.content_items where id = '07d00000-0000-4000-8000-000000000004' $$,
  'Di''s delete of Ann''s group item runs but touches nothing');
select throws_ok($$ insert into public.item_circles (content_item_id, circle_id)
                    values ('07d00000-0000-4000-8000-000000000004', '07c00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'Di cannot link Ann''s item to a circle');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Eli, acting as himself and as Shop: RLS unions every profile he controls.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '07070707-0000-4000-8000-000000000005', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Eli claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '07070707-0000-4000-8000-000000000005'::uuid, 'auth.uid() is Eli');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000005'),
            ('07d00000-0000-4000-8000-000000000011'), ('07d00000-0000-4000-8000-000000000012') $$,
  'Eli reads Shop''s items as its manager plus the public items');
select ok(public.can_view('07d00000-0000-4000-8000-000000000011', '07b00000-0000-4000-8000-000000000011'),
  'Eli may evaluate as the business he manages');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Fay, a follower of Shop.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '07070707-0000-4000-8000-000000000006', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '07070707-0000-4000-8000-000000000006'::uuid, 'auth.uid() is Fay');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000005'),
            ('07d00000-0000-4000-8000-000000000011'), ('07d00000-0000-4000-8000-000000000012') $$,
  'Fay reads Shop''s connections and all followers items plus the public items');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: reads only what can_view allows a null viewer, and never writes (Req 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000005') $$,
  'anon reads only the live public items whose parents are visible');
select set_eq($$ select id from public.vouches $$,
  $$ values ('07f00000-0000-4000-8000-000000000002'::uuid) $$, 'anon reads only the public vouch');
select throws_ok($$ select audience from public.content_items $$, '42501', null,
  'anon cannot read content_items.audience (D-3)');
select throws_ok($$ select hidden_by_subject from public.vouches $$, '42501', null,
  'anon cannot read vouches.hidden_by_subject (D-3)');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000002'),
  'anon asking as Bo is treated as a null viewer (Req 20.15)');
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, details)
                    values ('07b00000-0000-4000-8000-000000000001', 'writing', '{"title": "x", "body": "y"}') $$,
  '42501', null, 'anon cannot insert content items');
select throws_ok($$ update public.content_items set details = '{"title": "x", "body": "y"}'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'anon cannot update content items');
select throws_ok($$ delete from public.content_items where id = '07d00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'anon cannot delete content items');
select throws_ok($$ insert into public.vouches (author_profile_id, subject_profile_id, body)
                    values ('07b00000-0000-4000-8000-000000000002', '07b00000-0000-4000-8000-000000000003', 'x') $$,
  '42501', null, 'anon cannot insert vouches');
select throws_ok($$ update public.vouches set body = 'x' where id = '07f00000-0000-4000-8000-000000000002' $$,
  '42501', null, 'anon cannot update vouches');
select throws_ok($$ delete from public.vouches where id = '07f00000-0000-4000-8000-000000000002' $$,
  '42501', null, 'anon cannot delete vouches');
select throws_ok($$ select 1 from public.item_circles $$, '42501', null, 'anon cannot read item circle links');
select throws_ok($$ insert into public.item_circles (content_item_id, circle_id)
                    values ('07d00000-0000-4000-8000-000000000001', '07c00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'anon cannot insert item circle links');
select throws_ok($$ delete from public.item_circles where circle_id = '07c00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'anon cannot delete item circle links');

-- ---------------------------------------------------------------------------------------------
-- Signed in as Ann, the owner: she reads all her items, expired included, and cannot extend a
-- story or back-date an item (Req 11.10, 20.2).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '07070707-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ann claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '07070707-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ann');

select set_eq($$ select id from public.content_items $$,
  $$ values ('07d00000-0000-4000-8000-000000000001'::uuid), ('07d00000-0000-4000-8000-000000000002'),
            ('07d00000-0000-4000-8000-000000000003'), ('07d00000-0000-4000-8000-000000000004'),
            ('07d00000-0000-4000-8000-000000000005'), ('07d00000-0000-4000-8000-000000000006'),
            ('07d00000-0000-4000-8000-000000000007'), ('07d00000-0000-4000-8000-000000000008') $$,
  'Ann reads every item she owns, the expired story included, and no circle item of Shop');
select set_eq($$ select id from public.vouches $$,
  $$ values ('07f00000-0000-4000-8000-000000000001'::uuid), ('07f00000-0000-4000-8000-000000000002'),
            ('07f00000-0000-4000-8000-000000000003') $$,
  'Ann reads the vouch she wrote and both vouches about her');
select ok(public.can_view('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000001'),
  'Ann evaluating as herself sees her expired story');
select is((select count(*)::int from public.item_circles), 2, 'Ann reads the links of her own item and vouch');

select throws_ok($$ update public.content_items set expires_at = now() + interval '1 day'
                    where id = '07d00000-0000-4000-8000-000000000007' $$,
  '42501', null, 'Ann cannot set expires_at through the API');
select throws_ok($$ update public.content_items set created_at = now()
                    where id = '07d00000-0000-4000-8000-000000000007' $$,
  '42501', null, 'Ann cannot set created_at through the API');
select lives_ok($$ update public.content_items set details = '{"text": "edited old story"}'
                   where id = '07d00000-0000-4000-8000-000000000007' $$,
  'Ann can edit her expired story');
select ok((select expires_at < now() and expires_at = created_at + interval '24 hours'
           from public.content_items where id = '07d00000-0000-4000-8000-000000000007'),
  'editing a story through the API does not extend it');
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, details, created_at)
                    values ('07b00000-0000-4000-8000-000000000001', 'story', '{"text": "x"}', now() - interval '2 days') $$,
  '42501', null, 'Ann cannot back-date an item through the API');
select lives_ok($$ insert into public.content_items (owner_profile_id, content_type, details)
                   values ('07b00000-0000-4000-8000-000000000001', 'story', '{"text": "api story"}') $$,
  'Ann can create a story through the API');
select ok((select created_at = now() and expires_at = now() + interval '24 hours'
           from public.content_items where details ->> 'text' = 'api story'),
  'an API story gets the server time and expires 24 hours later');
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, details)
                    values ('07b00000-0000-4000-8000-000000000002', 'writing', '{"title": "x", "body": "y"}') $$,
  '42501', null, 'Ann cannot create an item for Bo');
select throws_ok($$ insert into public.item_circles (content_item_id, circle_id)
                    values ('07d00000-0000-4000-8000-000000000003', '07c00000-0000-4000-8000-000000000004') $$,
  'PT422', 'audience.circle_not_owned', 'Ann cannot link her item to Bo''s circle (Req 11.8)');

-- ---------------------------------------------------------------------------------------------
-- Back to the test owner. What the API calls did and did not change.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', '', true);
select is((select details ->> 'title' from public.content_items where id = '07d00000-0000-4000-8000-000000000001'),
  'Hello', 'Di''s update changed nothing');
select ok(exists (select 1 from public.content_items where id = '07d00000-0000-4000-8000-000000000004'),
  'Di''s delete removed nothing');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000007', '07b00000-0000-4000-8000-000000000002'),
  'the edited expired story is still hidden from a connection');
select is((select audience::text from public.content_items where details ->> 'text' = 'api story'),
  'connections', 'a story created through the API without an audience gets connections');

-- ---------------------------------------------------------------------------------------------
-- Circles are required at commit (Req 11.7). The checks are deferred, so each case runs them
-- with set constraints all immediate inside the statement under test.
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ set constraints all immediate $$, 'every deferred check passes before the circles cases');
set constraints all deferred;
select throws_ok($$ do $d$ begin
                      insert into public.content_items (owner_profile_id, content_type, audience, details)
                      values ('07b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
                              '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/none.jpg"}');
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'a circles item with no link is rejected at commit');
set constraints all deferred;
select throws_ok($$ do $d$ begin
                      update public.content_items set audience = 'circles'
                      where id = '07d00000-0000-4000-8000-000000000002';
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'moving an item to circles without a link is rejected at commit');
set constraints all deferred;
select throws_ok($$ do $d$ begin
                      insert into public.vouches (author_profile_id, subject_profile_id, body, audience)
                      values ('07b00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000003',
                              'Cy is kind', 'circles');
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'a circles vouch with no link is rejected at commit');
set constraints all deferred;
select lives_ok($$ do $d$ begin
                     insert into public.content_items (id, owner_profile_id, content_type, audience, details)
                     values ('07d00000-0000-4000-8000-000000000024', '07b00000-0000-4000-8000-000000000001',
                             'gallery', 'circles',
                             '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/linked.jpg"}');
                     insert into public.item_circles (content_item_id, circle_id)
                     values ('07d00000-0000-4000-8000-000000000024', '07c00000-0000-4000-8000-000000000002');
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'a circles item linked later in the same transaction passes');
select throws_ok($$ insert into public.item_circles (content_item_id, circle_id)
                    values ('07d00000-0000-4000-8000-000000000004', '07c00000-0000-4000-8000-000000000004') $$,
  'PT422', 'audience.circle_not_owned', 'a link to a circle the owner does not own is rejected for every writer');
select throws_ok($$ insert into public.item_circles (vouch_id, circle_id)
                    values ('07f00000-0000-4000-8000-000000000001', '07c00000-0000-4000-8000-000000000004') $$,
  'PT422', 'audience.circle_not_owned', 'a vouch link to a circle the author does not own is rejected');

-- ---------------------------------------------------------------------------------------------
-- item_circles_last_link (D-7).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ do $d$ begin
                      delete from public.item_circles where content_item_id = '07d00000-0000-4000-8000-000000000003';
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'deleting the last link of a circles item is rejected at commit');
set constraints all deferred;
select throws_ok($$ do $d$ begin
                      delete from public.item_circles where vouch_id = '07f00000-0000-4000-8000-000000000001';
                      set constraints all immediate;
                    end $d$ $$,
  'PT422', 'content.circles_required', 'deleting the last link of a circles vouch is rejected at commit');
set constraints all deferred;
select lives_ok($$ do $d$ begin
                     delete from public.item_circles where content_item_id = '07d00000-0000-4000-8000-000000000003';
                     insert into public.item_circles (content_item_id, circle_id)
                     values ('07d00000-0000-4000-8000-000000000003', '07c00000-0000-4000-8000-000000000002');
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'replacing the links of an item in one transaction passes');
select ok(public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000003'),
  'after the replacement the new circle''s member sees the item');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002'),
  'and the old circle''s member no longer does');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000008', '07b00000-0000-4000-8000-000000000002'),
  'nor does he see its child any more');

-- Removing a person from a circle removes access at once.
delete from public.circle_members
where circle_id = '07c00000-0000-4000-8000-000000000002' and member_profile_id = '07b00000-0000-4000-8000-000000000003';
select ok(not public.can_view('07d00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000003'),
  'a person removed from the circle loses the circle item');
select ok(not public.can_view('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000003'),
  'and loses the circle vouch');
select ok(public.can_view('07f00000-0000-4000-8000-000000000001', '07b00000-0000-4000-8000-000000000002'),
  'the subject still sees the vouch');

-- Deleting the circle passes and leaves the item visible to its owner only.
insert into public.circles (id, owner_profile_id, private_name) values
  ('07c00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000001', 'temporary');
insert into public.circle_members (circle_id, member_profile_id) values
  ('07c00000-0000-4000-8000-000000000003', '07b00000-0000-4000-8000-000000000002');
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('07d00000-0000-4000-8000-000000000021', '07b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/temp.jpg"}'),
  ('07d00000-0000-4000-8000-000000000022', '07b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/gone.jpg"}');
insert into public.item_circles (content_item_id, circle_id) values
  ('07d00000-0000-4000-8000-000000000021', '07c00000-0000-4000-8000-000000000003'),
  ('07d00000-0000-4000-8000-000000000022', '07c00000-0000-4000-8000-000000000001');
select lives_ok($$ set constraints all immediate $$, 'the two new circles items pass the deferred checks');
set constraints all deferred;
select ok(public.can_view('07d00000-0000-4000-8000-000000000021', '07b00000-0000-4000-8000-000000000002'),
  'before the circle is deleted its member sees the item');
select lives_ok($$ do $d$ begin
                     delete from public.circles where id = '07c00000-0000-4000-8000-000000000003';
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'deleting the circle of an item''s last link passes');
select results_eq(
  $$ select audience::text, (select count(*)::int from public.item_circles ic where ic.content_item_id = ci.id)
     from public.content_items ci where ci.id = '07d00000-0000-4000-8000-000000000021' $$,
  $$ values ('circles'::text, 0) $$,
  'the item stays, with audience circles and no link');
select ok(public.can_view('07d00000-0000-4000-8000-000000000021', '07b00000-0000-4000-8000-000000000001'),
  'the owner still sees the item left without a circle');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000021', '07b00000-0000-4000-8000-000000000002'),
  'the former member no longer sees it (fails closed)');
select ok(not public.can_view('07d00000-0000-4000-8000-000000000021', null),
  'a null viewer does not see it');

-- Deleting the item itself passes.
select lives_ok($$ do $d$ begin
                     delete from public.content_items where id = '07d00000-0000-4000-8000-000000000022';
                     set constraints all immediate;
                     set constraints all deferred;
                   end $d$ $$,
  'deleting a circles item, and with it its last link, passes');
select is_empty($$ select 1 from public.item_circles where content_item_id = '07d00000-0000-4000-8000-000000000022' $$,
  'the deleted item''s links went with it');

-- ---------------------------------------------------------------------------------------------
-- One status per owner (Req 11.13, 11.14).
-- ---------------------------------------------------------------------------------------------
select lives_ok($$ insert into public.content_items (id, owner_profile_id, content_type, details)
                   values ('07d00000-0000-4000-8000-000000000023', '07b00000-0000-4000-8000-000000000001',
                           'status', '{"text": "back at work"}') $$,
  'Ann can set a new status');
select set_eq($$ select id from public.content_items
                 where owner_profile_id = '07b00000-0000-4000-8000-000000000001' and content_type = 'status' $$,
  $$ values ('07d00000-0000-4000-8000-000000000023'::uuid) $$,
  'the new status replaced the old one');
select lives_ok($$ insert into public.content_items (id, owner_profile_id, content_type, details)
                   values ('07d00000-0000-4000-8000-000000000023', '07b00000-0000-4000-8000-000000000001',
                           'status', '{"text": "in meetings", "emoji": "x"}')
                   on conflict (id) do update set details = excluded.details $$,
  'an upsert of the same status row runs');
select results_eq(
  $$ select id, details ->> 'text', expires_at is null from public.content_items
     where owner_profile_id = '07b00000-0000-4000-8000-000000000001' and content_type = 'status' $$,
  $$ values ('07d00000-0000-4000-8000-000000000023'::uuid, 'in meetings'::text, true) $$,
  'the upsert kept its own row, updated, with no expiry');
select ok(exists (select 1 from public.content_items where id = '07d00000-0000-4000-8000-000000000011'),
  'another owner''s status is untouched');

-- ---------------------------------------------------------------------------------------------
-- Details shapes and path kinds (Req 11.12, 23.7; NQ-5 and fix_content_image_path_kind).
-- ---------------------------------------------------------------------------------------------
select throws_ok(format($$ insert into public.content_items (owner_profile_id, content_type, audience, details)
                           values ('07b00000-0000-4000-8000-000000000001', %L, 'public', %L) $$, v.t, v.d),
  '23514', null, v.label)
from (values
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000001/story/x.jpg"}',
   'a gallery item pointing at the story folder is rejected'),
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000001/avatar/x.jpg"}',
   'a gallery item pointing at a public-media folder is rejected'),
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/a/x.jpg"}',
   'a gallery path with four parts is rejected'),
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/"}',
   'a gallery path with an empty file part is rejected'),
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000002/gallery/x.jpg"}',
   'a gallery item pointing at another profile''s folder is rejected'),
  ('gallery', '{"caption": "no image"}', 'a gallery item without an image path is rejected'),
  ('gallery', '{"image_path": 42}', 'a non string image path is rejected'),
  ('story', '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/x.jpg"}',
   'a story pointing at the gallery folder is rejected'),
  ('story', '{"image_path": "07b00000-0000-4000-8000-000000000001/writing/x.jpg"}',
   'a story pointing at a public-media folder is rejected'),
  ('story', '{"image_path": "07b00000-0000-4000-8000-000000000002/story/x.jpg"}',
   'a story pointing at another profile''s folder is rejected'),
  ('story', '{"background": "blue"}', 'a story with neither image nor text is rejected'),
  ('writing', '{"title": "t", "body": "b", "image_path": "07b00000-0000-4000-8000-000000000001/gallery/x.jpg"}',
   'a public writing item cannot reference a private gallery file'),
  ('writing', '{"title": "t", "body": "b", "image_path": "07b00000-0000-4000-8000-000000000001/story/x.jpg"}',
   'a public writing item cannot reference a private story file'),
  ('writing', '{"title": "t", "body": "b", "image_path": "07b00000-0000-4000-8000-000000000001/writing/x.jpg"}',
   'a writing item may not carry an image path at all'),
  ('writing', '{"title": "t", "body": "b", "cover_image_path": "07b00000-0000-4000-8000-000000000001/gallery/x.jpg"}',
   'a writing cover pointing at the gallery folder is rejected'),
  ('writing', '{"title": "t", "body": "b", "cover_image_path": "07b00000-0000-4000-8000-000000000002/writing/x.jpg"}',
   'a writing cover in another profile''s folder is rejected'),
  ('writing', '{"title": "t"}', 'writing without a body is rejected'),
  ('status', '{"text": "hi", "image_path": "07b00000-0000-4000-8000-000000000001/gallery/x.jpg"}',
   'a public status cannot reference a private gallery file'),
  ('status', '{"text": "hi", "image_path": "07b00000-0000-4000-8000-000000000001/story/x.jpg"}',
   'a public status cannot reference a private story file'),
  ('status', '{"text": ""}', 'an empty status is rejected')
) as v(t, d, label);
select throws_ok($$ update public.content_items
                    set details = '{"image_path": "07b00000-0000-4000-8000-000000000001/story/x.jpg"}'
                    where id = '07d00000-0000-4000-8000-000000000008' $$,
  '23514', null, 'an update cannot move a gallery item''s path to another kind');
select throws_ok($$ update public.content_items
                    set details = '{"title": "Hello", "body": "First post", "image_path": "07b00000-0000-4000-8000-000000000001/gallery/inner.jpg"}'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  '23514', null, 'an update cannot attach a private gallery file to public writing');
select lives_ok(format($$ insert into public.content_items (owner_profile_id, content_type, audience, details)
                          values ('07b00000-0000-4000-8000-000000000001', %L, 'public', %L) $$, v.t, v.d),
  v.label)
from (values
  ('gallery', '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/ok.jpg", "caption": "fine"}',
   'a gallery item in its own gallery folder is accepted'),
  ('story', '{"image_path": "07b00000-0000-4000-8000-000000000001/story/ok.jpg"}',
   'a story in its own story folder is accepted'),
  ('story', '{"text": "words only"}', 'a text story is accepted'),
  ('writing', '{"title": "t", "body": "b", "cover_image_path": "07b00000-0000-4000-8000-000000000001/writing/c.jpg"}',
   'a writing cover in its own writing folder is accepted')
) as v(t, d, label);
select ok(not private.content_details_valid('writing', '{"title": "t", "body": "b", "image_path": "a/gallery/x.jpg"}'),
  'the validator rejects an image path on writing');
select ok(not private.content_details_valid('status', '{"text": "t", "image_path": "a/story/x.jpg"}'),
  'the validator rejects an image path on status');
select ok(private.content_details_valid('gallery', '{"image_path": "a/gallery/x.jpg"}'),
  'the validator accepts a three part gallery path');
select ok(not private.content_details_valid('gallery', '[]'), 'the validator rejects details that are not an object');

-- ---------------------------------------------------------------------------------------------
-- Parents (Req 11.11) and parent cycles (content.parent_cycle).
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.content_items (owner_profile_id, content_type, audience, details, parent_id)
                    values ('07b00000-0000-4000-8000-000000000002', 'gallery', 'public',
                            '{"image_path": "07b00000-0000-4000-8000-000000000002/gallery/x.jpg"}',
                            '07d00000-0000-4000-8000-000000000001') $$,
  'PT422', 'content.parent_owner', 'a parent owned by someone else is rejected on insert');
select throws_ok($$ update public.content_items set parent_id = '07d00000-0000-4000-8000-000000000011'
                    where id = '07d00000-0000-4000-8000-000000000008' $$,
  'PT422', 'content.parent_owner', 'a parent owned by someone else is rejected on update');
select throws_ok($$ update public.content_items set parent_id = '07d00000-0000-4000-8000-000000000001'
                    where id = '07d00000-0000-4000-8000-000000000001' $$,
  'PT422', 'content.parent_cycle', 'an item cannot be its own parent');
select throws_ok($$ update public.content_items set parent_id = '07d00000-0000-4000-8000-000000000008'
                    where id = '07d00000-0000-4000-8000-000000000003' $$,
  'PT422', 'content.parent_cycle', 'a parent chain cannot loop back to the item');
select lives_ok($$ insert into public.content_items (owner_profile_id, content_type, audience, details, parent_id)
                   values ('07b00000-0000-4000-8000-000000000001', 'gallery', 'public',
                           '{"image_path": "07b00000-0000-4000-8000-000000000001/gallery/grandchild.jpg"}',
                           '07d00000-0000-4000-8000-000000000008') $$,
  'a parent owned by the same owner is accepted, at any depth');
select ok(not public.can_view(
            (select id from public.content_items where details ->> 'image_path' like '%/grandchild.jpg'),
            '07b00000-0000-4000-8000-000000000002'),
  'a grandchild is hidden when the grandparent is hidden');
select ok(public.can_view(
            (select id from public.content_items where details ->> 'image_path' like '%/grandchild.jpg'),
            '07b00000-0000-4000-8000-000000000001'),
  'the owner sees the grandchild');

select lives_ok($$ set constraints all immediate $$, 'everything left in the transaction passes the deferred checks');

select * from finish();
rollback;
