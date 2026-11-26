-- Fix after Spec 00 task 15.1 (Dominic's decision): restrict details.image_path to gallery and
-- story items, in the folder whose kind matches the item type (NQ-5, Req 11.12, 23.7).
-- Before this, a writing or status item (or any later type) could carry an image_path, and the
-- owner folder check accepts any kind, so a public writing or status item could point at the
-- owner's private gallery or story file and make it readable through the private-media select
-- policies. The validator already receives the item type, so the whole rule fits in it; the
-- owner folder part stays in content_items_image_path_owner. A violation fails the existing
-- check constraint content_items_details_valid (SQLSTATE 23514, see Error Handling).
-- Path format (NQ-5): exactly three parts <profile_id>/<kind>/<file>, with a non empty file part.
-- Signature, volatility, search_path and grants are unchanged.
create or replace function private.content_details_valid(p_type public.content_type, p_details jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select coalesce(
    pg_catalog.jsonb_typeof(p_details) = 'object'
    and case p_type
      when 'writing' then
            p_details -> 'image_path' is null
        and pg_catalog.jsonb_typeof(p_details -> 'title') = 'string'
        and pg_catalog.char_length(p_details ->> 'title') between 1 and 200
        and pg_catalog.jsonb_typeof(p_details -> 'body') = 'string'
        and pg_catalog.char_length(p_details ->> 'body') between 1 and 50000
        and (p_details -> 'cover_image_path' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'cover_image_path') = 'string'
                 and pg_catalog.split_part(p_details ->> 'cover_image_path', '/', 2) = 'writing'))
      when 'gallery' then
            pg_catalog.jsonb_typeof(p_details -> 'image_path') = 'string'
        and pg_catalog.array_length(pg_catalog.string_to_array(p_details ->> 'image_path', '/'), 1) = 3
        and pg_catalog.split_part(p_details ->> 'image_path', '/', 2) = 'gallery'
        and pg_catalog.split_part(p_details ->> 'image_path', '/', 3) <> ''
        and (p_details -> 'caption' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'caption') = 'string'
                 and pg_catalog.char_length(p_details ->> 'caption') <= 500))
      when 'status' then
            p_details -> 'image_path' is null
        and pg_catalog.jsonb_typeof(p_details -> 'text') = 'string'
        and pg_catalog.char_length(p_details ->> 'text') between 1 and 100
        and (p_details -> 'emoji' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'emoji') = 'string'
                 and pg_catalog.char_length(p_details ->> 'emoji') <= 8))
      when 'story' then
            (p_details -> 'image_path' is not null or p_details -> 'text' is not null)
        and (p_details -> 'image_path' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'image_path') = 'string'
                 and pg_catalog.array_length(pg_catalog.string_to_array(p_details ->> 'image_path', '/'), 1) = 3
                 and pg_catalog.split_part(p_details ->> 'image_path', '/', 2) = 'story'
                 and pg_catalog.split_part(p_details ->> 'image_path', '/', 3) <> ''))
        and (p_details -> 'text' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'text') = 'string'
                 and pg_catalog.char_length(p_details ->> 'text') between 1 and 280))
        and (p_details -> 'background' is null
             or pg_catalog.jsonb_typeof(p_details -> 'background') = 'string')
      -- A type added later may not reference media until it gets its own branch (fails closed).
      else p_details -> 'image_path' is null
    end,
    false);
$$;
revoke execute on function private.content_details_valid(public.content_type, jsonb) from public;
grant execute on function private.content_details_valid(public.content_type, jsonb) to anon, authenticated;
;
