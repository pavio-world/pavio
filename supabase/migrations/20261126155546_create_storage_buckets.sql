-- Migration 23: storage buckets and policies. public-media (public, 5 MB) holds avatars, covers and
-- images inside writing; private-media (private, 10 MB) holds every gallery and story file, read
-- through signed URLs only when can_view lets the caller see a referencing item (NQ-5).
-- Spec 00 Req 23.1 to 23.7, 25.2; design "Storage buckets and policies", "Storage helper", D-1.

-- ---------------------------------------------------------------------------------------------
-- Buckets. on conflict do nothing keeps the migration safe if a bucket was made by hand.
-- ---------------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('public-media', 'public-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('private-media', 'private-media', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- public.try_uuid: turns a path folder into a uuid, or null when it is not one, so a bad first
-- folder fails the policy instead of raising an error. Pure, so anon may execute it (D-1).
-- ---------------------------------------------------------------------------------------------

create or replace function public.try_uuid(p text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

revoke execute on function public.try_uuid(text) from public;
revoke execute on function public.try_uuid(text) from anon, authenticated;
grant execute on function public.try_uuid(text) to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- private.media_kind_allowed: object names have exactly three parts, <profile_id>/<kind>/<file>,
-- and the kind decides the bucket (NQ-5). Used by the upload, update and delete policies only.
-- ---------------------------------------------------------------------------------------------

create or replace function private.media_kind_allowed(p_bucket text, p_name text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    array_length(string_to_array(p_name, '/'), 1) = 3
    and case p_bucket
          when 'public-media' then split_part(p_name, '/', 2) in ('avatar', 'cover', 'writing')
          when 'private-media' then split_part(p_name, '/', 2) in ('gallery', 'story')
          else false
        end,
    false);
$$;

revoke execute on function private.media_kind_allowed(text, text) from public;
revoke execute on function private.media_kind_allowed(text, text) from anon, authenticated;
grant execute on function private.media_kind_allowed(text, text) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Policies on storage.objects (RLS is already enabled there by Supabase).
-- ---------------------------------------------------------------------------------------------

-- Owners list their own public files. Public reads use the public URL and need no policy, so
-- the bucket cannot be listed by anyone else.
create policy storage_public_media_authenticated_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'public-media'
    and (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
  );

-- Uploads, updates and deletes: right bucket for the kind, and the first folder is a profile the
-- login acts as (Req 23.4, 23.7). anon gets no write policy at all (Req 23.5).
create policy storage_media_authenticated_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('public-media', 'private-media')
    and private.media_kind_allowed(bucket_id, name)
    and (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
  );

create policy storage_media_authenticated_update on storage.objects
  for update to authenticated
  using (
    bucket_id in ('public-media', 'private-media')
    and private.media_kind_allowed(bucket_id, name)
    and (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
  )
  with check (
    bucket_id in ('public-media', 'private-media')
    and private.media_kind_allowed(bucket_id, name)
    and (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
  );

create policy storage_media_authenticated_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id in ('public-media', 'private-media')
    and private.media_kind_allowed(bucket_id, name)
    and (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
  );

-- Private reads: only through a content item that references the path. The subquery runs under
-- the caller's RLS on content_items, which is filtered by can_view, so the one visibility check
-- decides (Req 23.3). A signed URL needs select permission, so it can be made only for a file
-- the caller may see.
create policy storage_private_media_anon_select on storage.objects
  for select to anon
  using (
    bucket_id = 'private-media'
    and exists (
      select 1 from public.content_items ci
      where ci.details ->> 'image_path' = storage.objects.name
    )
  );

create policy storage_private_media_authenticated_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'private-media'
    and (
      (select public.acts_as(public.try_uuid((storage.foldername(name))[1])))
      or exists (
        select 1 from public.content_items ci
        where ci.details ->> 'image_path' = storage.objects.name
      )
    )
  );
;
