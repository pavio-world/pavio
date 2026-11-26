-- Storage buckets and policies (Spec 00 Req 23.1 to 23.7, 25.2; NQ-5, D-1; migration 23).
-- public-media holds avatars, covers and images in writing; private-media holds every gallery
-- and story file and is read only through a content item that can_view lets the caller see.
-- Object names have three parts: <profile_id>/<kind>/<file>.
-- The Storage API sets storage.allow_delete_query before it deletes objects (a statement level
-- trigger blocks plain SQL deletes), so the delete tests set it too and rely on the policies.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(81);
-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Una (p1) owns the business Una's Kiosk (p4); Vic (p2) is Una's accepted connection; Wes (p3) is
-- a stranger. Una's gallery and story items, each with one file in private-media:
--   pub    gallery, public                 conn   gallery, connections
--   inner  gallery, circles (inner: Vic)   solo   gallery, circles (solo: nobody)
--   live   story, public, live             old    story, public, expired
--   orphan a file with no item
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('15151515-0000-4000-8000-000000000001', 'una.storage@example.invalid'),
  ('15151515-0000-4000-8000-000000000002', 'vic.storage@example.invalid'),
  ('15151515-0000-4000-8000-000000000003', 'wes.storage@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('15b00000-0000-4000-8000-000000000001', 'person', '15151515-0000-4000-8000-000000000001', 'una_st', 'Una'),
  ('15b00000-0000-4000-8000-000000000002', 'person', '15151515-0000-4000-8000-000000000002', 'vic_st', 'Vic'),
  ('15b00000-0000-4000-8000-000000000003', 'person', '15151515-0000-4000-8000-000000000003', 'wes_st', 'Wes');
insert into public.profiles (id, type, handle, display_name) values
  ('15b00000-0000-4000-8000-000000000004', 'business', 'kiosk_st', 'Una''s Kiosk');
insert into public.profile_managers (profile_id, user_id, role) values
  ('15b00000-0000-4000-8000-000000000004', '15151515-0000-4000-8000-000000000001', 'owner');
insert into public.relationships (requester_profile_id, target_profile_id, type) values
  ('15b00000-0000-4000-8000-000000000001', '15b00000-0000-4000-8000-000000000002', 'connection');
update public.relationships set status = 'accepted' where type = 'connection';
insert into public.circles (id, owner_profile_id, private_name) values
  ('15c00000-0000-4000-8000-000000000001', '15b00000-0000-4000-8000-000000000001', 'inner'),
  ('15c00000-0000-4000-8000-000000000002', '15b00000-0000-4000-8000-000000000001', 'solo');
insert into public.circle_members (circle_id, member_profile_id) values
  ('15c00000-0000-4000-8000-000000000001', '15b00000-0000-4000-8000-000000000002');
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('15d00000-0000-4000-8000-000000000001', '15b00000-0000-4000-8000-000000000001', 'gallery', 'public',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/gallery/pub.jpg"}'),
  ('15d00000-0000-4000-8000-000000000002', '15b00000-0000-4000-8000-000000000001', 'gallery', 'connections',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/gallery/conn.jpg"}'),
  ('15d00000-0000-4000-8000-000000000003', '15b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/gallery/inner.jpg"}'),
  ('15d00000-0000-4000-8000-000000000004', '15b00000-0000-4000-8000-000000000001', 'gallery', 'circles',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/gallery/solo.jpg"}'),
  ('15d00000-0000-4000-8000-000000000005', '15b00000-0000-4000-8000-000000000001', 'story', 'public',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/story/live.jpg"}');
insert into public.content_items (id, owner_profile_id, content_type, audience, details, created_at) values
  ('15d00000-0000-4000-8000-000000000006', '15b00000-0000-4000-8000-000000000001', 'story', 'public',
   '{"image_path": "15b00000-0000-4000-8000-000000000001/story/old.jpg"}', now() - interval '25 hours');
insert into public.item_circles (content_item_id, circle_id) values
  ('15d00000-0000-4000-8000-000000000003', '15c00000-0000-4000-8000-000000000001'),
  ('15d00000-0000-4000-8000-000000000004', '15c00000-0000-4000-8000-000000000002');
select lives_ok($$ set constraints all immediate $$, 'the fixtures pass every deferred check');
set constraints all deferred;
insert into storage.objects (bucket_id, name) values
  ('public-media', '15b00000-0000-4000-8000-000000000001/avatar/seed.png'),
  ('public-media', '15b00000-0000-4000-8000-000000000002/avatar/v.png'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/conn.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/inner.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/solo.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/orphan.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/story/live.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000001/story/old.jpg'),
  ('private-media', '15b00000-0000-4000-8000-000000000002/gallery/v-orphan.jpg');
-- ---------------------------------------------------------------------------------------------
-- Catalog: buckets, helper functions and policies (Req 23.1, 23.2, 23.6).
-- ---------------------------------------------------------------------------------------------
select is((select public from storage.buckets where id = 'public-media'), true, 'public-media is public');
select is((select file_size_limit from storage.buckets where id = 'public-media'), 5242880::bigint,
  'public-media is limited to 5 MB');
select is((select allowed_mime_types from storage.buckets where id = 'public-media'),
  array['image/jpeg', 'image/png', 'image/webp'], 'public-media accepts jpeg, png and webp');
select is((select public from storage.buckets where id = 'private-media'), false, 'private-media is private');
select is((select file_size_limit from storage.buckets where id = 'private-media'), 10485760::bigint,
  'private-media is limited to 10 MB');
select is((select allowed_mime_types from storage.buckets where id = 'private-media'),
  array['image/jpeg', 'image/png', 'image/webp'], 'private-media accepts jpeg, png and webp');
select ok((select relrowsecurity from pg_class where oid = 'storage.objects'::regclass),
  'RLS is enabled on storage.objects');
select policies_are('storage', 'objects', array[
  'storage_public_media_authenticated_select', 'storage_media_authenticated_insert',
  'storage_media_authenticated_update', 'storage_media_authenticated_delete',
  'storage_private_media_anon_select', 'storage_private_media_authenticated_select'
], 'storage.objects has exactly the six Pavio policies');
select is(public.try_uuid('15b00000-0000-4000-8000-000000000001'), '15b00000-0000-4000-8000-000000000001'::uuid,
  'try_uuid returns a valid uuid');
select is(public.try_uuid('not-a-uuid'), null::uuid, 'try_uuid returns null for text that is not a uuid');
select is(public.try_uuid(null), null::uuid, 'try_uuid returns null for null');
select ok(has_function_privilege('anon', 'public.try_uuid(text)', 'EXECUTE'), 'anon can execute try_uuid (D-1)');
select ok(has_function_privilege('authenticated', 'public.try_uuid(text)', 'EXECUTE'),
  'authenticated can execute try_uuid');
select ok(not has_function_privilege('anon', 'private.media_kind_allowed(text, text)', 'EXECUTE'),
  'anon cannot execute media_kind_allowed');
select ok(has_function_privilege('authenticated', 'private.media_kind_allowed(text, text)', 'EXECUTE'),
  'authenticated can execute media_kind_allowed');
-- ---------------------------------------------------------------------------------------------
-- media_kind_allowed: the NQ-5 path rules (Req 23.7).
-- ---------------------------------------------------------------------------------------------
select is(private.media_kind_allowed(v.b, v.n), v.expected, v.descr)
from (values
  ('public-media', 'p/avatar/a.png', true, 'avatar is allowed in public-media'),
  ('public-media', 'p/cover/a.png', true, 'cover is allowed in public-media'),
  ('public-media', 'p/writing/a.png', true, 'writing is allowed in public-media'),
  ('public-media', 'p/gallery/a.png', false, 'gallery is refused in public-media'),
  ('public-media', 'p/story/a.png', false, 'story is refused in public-media'),
  ('private-media', 'p/gallery/a.jpg', true, 'gallery is allowed in private-media'),
  ('private-media', 'p/story/a.jpg', true, 'story is allowed in private-media'),
  ('private-media', 'p/avatar/a.jpg', false, 'avatar is refused in private-media'),
  ('private-media', 'p/cover/a.jpg', false, 'cover is refused in private-media'),
  ('private-media', 'p/writing/a.jpg', false, 'writing is refused in private-media'),
  ('public-media', 'p/avatar', false, 'a two part name is refused'),
  ('public-media', 'p/avatar/x/a.png', false, 'a four part name is refused'),
  ('other-media', 'p/avatar/a.png', false, 'an unknown bucket is refused'),
  ('public-media', null, false, 'a null name is refused')
) as v(b, n, expected, descr);
-- ---------------------------------------------------------------------------------------------
-- Una, signed in (canary order: claims, role switch, then check).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '15151515-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated (Una)');
select is(auth.uid(), '15151515-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Una');
-- Reads: Una sees every file in her own folder, including the orphan and the expired story.
select is((select array_agg(name order by name collate "C") from storage.objects
           where bucket_id = 'private-media' and name like '15b00000-0000-4000-8000-000000000001/%'),
  array[
    '15b00000-0000-4000-8000-000000000001/gallery/conn.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/inner.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/orphan.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/solo.jpg',
    '15b00000-0000-4000-8000-000000000001/story/live.jpg',
    '15b00000-0000-4000-8000-000000000001/story/old.jpg'],
  'Una lists all seven files in her private-media folder');
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'public-media'
                     and name = '15b00000-0000-4000-8000-000000000001/avatar/seed.png' $$,
  'Una lists her own public-media avatar');
select is_empty($$ select 1 from storage.objects where bucket_id = 'public-media'
                   and name like '15b00000-0000-4000-8000-000000000002/%' $$,
  'Una cannot list Vic''s public-media files');
select is_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                   and name like '15b00000-0000-4000-8000-000000000002/%' $$,
  'Una cannot read Vic''s private-media file that no item references');
-- Uploads: right bucket and kind, in a folder she acts as (herself, or the business she owns).
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('public-media', '15b00000-0000-4000-8000-000000000001/avatar/new.png') $$,
  'Una uploads an avatar to public-media in her folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('public-media', '15b00000-0000-4000-8000-000000000001/cover/new.png') $$,
  'Una uploads a cover to public-media in her folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('public-media', '15b00000-0000-4000-8000-000000000001/writing/new.png') $$,
  'Una uploads a writing image to public-media in her folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/new.jpg') $$,
  'Una uploads a gallery file to private-media in her folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('private-media', '15b00000-0000-4000-8000-000000000001/story/new.jpg') $$,
  'Una uploads a story file to private-media in her folder');
select lives_ok($$ insert into storage.objects (bucket_id, name)
                   values ('public-media', '15b00000-0000-4000-8000-000000000004/avatar/new.png') $$,
  'Una uploads an avatar into the folder of the business she owns');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000002/avatar/x.png') $$,
  '42501', null, 'Una cannot upload to Vic''s public-media folder');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('private-media', '15b00000-0000-4000-8000-000000000002/gallery/x.jpg') $$,
  '42501', null, 'Una cannot upload to Vic''s private-media folder');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', 'junk/avatar/x.png') $$,
  '42501', null, 'a first folder that is not a profile id is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/gallery/x.png') $$,
  '42501', null, 'a gallery path in public-media is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/story/x.png') $$,
  '42501', null, 'a story path in public-media is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('private-media', '15b00000-0000-4000-8000-000000000001/avatar/x.jpg') $$,
  '42501', null, 'an avatar path in private-media is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('private-media', '15b00000-0000-4000-8000-000000000001/writing/x.jpg') $$,
  '42501', null, 'a writing path in private-media is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/avatar/sub/x.png') $$,
  '42501', null, 'a four part path is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/x.png') $$,
  '42501', null, 'a two part path is refused');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('other-media', '15b00000-0000-4000-8000-000000000001/avatar/x.png') $$,
  '42501', null, 'a bucket other than the two Pavio buckets is refused');
-- Updates and deletes follow the same folder and kind rules.
select isnt_empty($$ with u as (
                       update storage.objects set name = '15b00000-0000-4000-8000-000000000001/avatar/renamed.png'
                       where bucket_id = 'public-media'
                         and name = '15b00000-0000-4000-8000-000000000001/avatar/new.png' returning 1)
                     select 1 from u $$,
  'Una renames her own avatar inside her folder');
select throws_ok($$ update storage.objects set name = '15b00000-0000-4000-8000-000000000002/avatar/stolen.png'
                    where bucket_id = 'public-media'
                      and name = '15b00000-0000-4000-8000-000000000001/avatar/renamed.png' $$,
  '42501', null, 'Una cannot move her file into Vic''s folder');
select throws_ok($$ update storage.objects set bucket_id = 'private-media'
                    where bucket_id = 'public-media'
                      and name = '15b00000-0000-4000-8000-000000000001/cover/new.png' $$,
  '42501', null, 'Una cannot move a cover into private-media');
select is_empty($$ with u as (
                     update storage.objects set name = '15b00000-0000-4000-8000-000000000002/avatar/v2.png'
                     where bucket_id = 'public-media'
                       and name = '15b00000-0000-4000-8000-000000000002/avatar/v.png' returning 1)
                   select 1 from u $$,
  'Una''s update of Vic''s file touches nothing');
select set_config('storage.allow_delete_query', 'true', true);
select isnt_empty($$ with d as (
                       delete from storage.objects
                       where bucket_id = 'private-media'
                         and name = '15b00000-0000-4000-8000-000000000001/story/new.jpg' returning 1)
                     select 1 from d $$,
  'Una deletes her own story file');
select is_empty($$ with d as (
                     delete from storage.objects
                     where bucket_id = 'public-media'
                       and name = '15b00000-0000-4000-8000-000000000002/avatar/v.png' returning 1)
                   select 1 from d $$,
  'Una''s delete of Vic''s file touches nothing');
-- ---------------------------------------------------------------------------------------------
-- Vic, Una's connection and a member of her inner circle: private files only through can_view.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '15151515-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated (Vic)');
select is(auth.uid(), '15151515-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Vic');
select is((select array_agg(name order by name collate "C") from storage.objects
           where bucket_id = 'private-media' and name like '15b00000-0000-4000-8000-000000000001/%'),
  array[
    '15b00000-0000-4000-8000-000000000001/gallery/conn.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/inner.jpg',
    '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg',
    '15b00000-0000-4000-8000-000000000001/story/live.jpg'],
  'Vic reads the public, connections and inner circle files and the live story');
select is_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                   and name = '15b00000-0000-4000-8000-000000000001/gallery/solo.jpg' $$,
  'Vic cannot read the file of a circle item he is not in (signed URL path fails)');
select is_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                   and name = '15b00000-0000-4000-8000-000000000001/story/old.jpg' $$,
  'Vic cannot read the file of an expired story');
select is_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                   and name = '15b00000-0000-4000-8000-000000000001/gallery/orphan.jpg' $$,
  'Vic cannot read a file no item references');
select is_empty($$ select 1 from storage.objects where bucket_id = 'public-media'
                   and name like '15b00000-0000-4000-8000-000000000001/%' $$,
  'Vic cannot list Una''s public-media files (public reads use the public URL)');
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'public-media'
                     and name = '15b00000-0000-4000-8000-000000000002/avatar/v.png' $$,
  'Vic lists his own public-media avatar');
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                     and name = '15b00000-0000-4000-8000-000000000002/gallery/v-orphan.jpg' $$,
  'Vic reads his own private-media file');
-- Removing Vic from the inner circle removes his access to its file at once.
set local role postgres;
delete from public.circle_members
where circle_id = '15c00000-0000-4000-8000-000000000001' and member_profile_id = '15b00000-0000-4000-8000-000000000002';
select set_config('request.jwt.claims',
  json_build_object('sub', '15151515-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
set local role authenticated;
select is_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                   and name = '15b00000-0000-4000-8000-000000000001/gallery/inner.jpg' $$,
  'after Vic leaves the inner circle he can no longer read its file');
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                     and name = '15b00000-0000-4000-8000-000000000001/gallery/conn.jpg' $$,
  'Vic still reads the connections file');
-- ---------------------------------------------------------------------------------------------
-- Wes, a stranger: only public items.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '15151515-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(auth.uid(), '15151515-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Wes');
select is((select array_agg(name order by name collate "C") from storage.objects
           where bucket_id = 'private-media' and name like '15b00000-0000-4000-8000-000000000001/%'),
  array[
    '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg',
    '15b00000-0000-4000-8000-000000000001/story/live.jpg'],
  'Wes reads only the files of public items');
select is_empty($$ select 1 from storage.objects where bucket_id = 'public-media' $$,
  'Wes cannot list public-media');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/avatar/wes.png') $$,
  '42501', null, 'Wes cannot upload into Una''s folder');
-- ---------------------------------------------------------------------------------------------
-- anon: reads public items' private files only, and can never write (Req 23.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is((select array_agg(name order by name collate "C") from storage.objects
           where bucket_id = 'private-media'),
  array[
    '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg',
    '15b00000-0000-4000-8000-000000000001/story/live.jpg'],
  'anon reads only the files of public items');
select is_empty($$ select 1 from storage.objects where bucket_id = 'public-media' $$,
  'anon cannot list public-media');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('public-media', '15b00000-0000-4000-8000-000000000001/avatar/anon.png') $$,
  '42501', null, 'anon cannot insert into public-media');
select throws_ok($$ insert into storage.objects (bucket_id, name)
                    values ('private-media', '15b00000-0000-4000-8000-000000000001/gallery/anon.jpg') $$,
  '42501', null, 'anon cannot insert into private-media');
select is_empty($$ with u as (
                     update storage.objects set name = '15b00000-0000-4000-8000-000000000001/gallery/moved.jpg'
                     where bucket_id = 'private-media'
                       and name = '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg' returning 1)
                   select 1 from u $$,
  'anon cannot update a file it can read');
select set_config('storage.allow_delete_query', 'true', true);
select is_empty($$ with d as (
                     delete from storage.objects
                     where bucket_id = 'private-media'
                       and name = '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg' returning 1)
                   select 1 from d $$,
  'anon cannot delete a file it can read');
set local role postgres;
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'private-media'
                     and name = '15b00000-0000-4000-8000-000000000001/gallery/pub.jpg' $$,
  'the file anon tried to change is still there');
select * from finish();
rollback;
