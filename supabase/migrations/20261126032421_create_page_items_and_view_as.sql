-- Migration 16: page listings and view as. private.page_items lists one page for one viewer: the
-- owner's content items, the owner's Top 8 (hidden or not) and the vouches the owner received that
-- are not hidden. Every row passes private.can_view with that viewer; there is no other visibility
-- logic here (Req 21.4). public.page_items nulls an untrusted viewer id exactly as public.can_view.
-- public.view_as lets an owner evaluate their own page as any simulated viewer.
-- Spec 00 Req 14.19, 14.20, 21.1 to 21.8, 22.3; design "page_items and view_as",
-- "Function execute grants", "Circle private name guarantee", D-1, DR-4; decision 002.
-- No function here reads circles, circle_members or item_circles directly, and none returns a
-- circle id, name or link (Req 21.8). Audience is returned only when the viewer is the page owner.
-- ---------------------------------------------------------------------------------------------

create or replace function private.page_items(p_owner uuid, p_viewer uuid)
returns table (
  section text,                                  -- 'content' | 'top8' | 'received'
  item_id uuid,
  content_type public.content_type,
  author_profile_id uuid,
  subject_profile_id uuid,
  audience public.audience,                      -- null unless p_viewer = p_owner
  details jsonb,
  body text,
  top8_position smallint,
  created_at timestamptz,
  expires_at timestamptz,
  story_label_kind public.story_label_kind,
  story_label_text text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.section, p.item_id, p.content_type, p.author_profile_id, p.subject_profile_id,
         p.audience, p.details, p.body, p.top8_position, p.created_at, p.expires_at,
         p.story_label_kind, p.story_label_text
  from (
    -- The owner's content items.                                              21.1, 21.6
    select 'content'::text as section, 1 as section_order,
           ci.id as item_id, ci.content_type,
           ci.owner_profile_id as author_profile_id, null::uuid as subject_profile_id,
           case when p_viewer = p_owner then ci.audience end as audience,
           ci.details, null::text as body, null::smallint as top8_position,
           ci.created_at, ci.expires_at,
           sl.kind as story_label_kind, sl.label as story_label_text
    from public.content_items ci
    left join lateral (
      select s.kind, s.label
      from private.story_label(ci.id, p_viewer) s
      where ci.content_type = 'story'
    ) sl on true
    where ci.owner_profile_id = p_owner
      and private.can_view(ci.id, p_viewer)

    union all

    -- The owner's Top 8, hidden by the subject or not.                       14.19
    select 'top8'::text, 2,
           v.id, null::public.content_type,
           v.author_profile_id, v.subject_profile_id,
           case when p_viewer = p_owner then v.audience end,
           null::jsonb, v.body, v.top8_position,
           v.created_at, null::timestamptz,
           null::public.story_label_kind, null::text
    from public.vouches v
    where v.author_profile_id = p_owner
      and v.top8_position is not null
      and private.can_view(v.id, p_viewer)

    union all

    -- Vouches the owner received and has not hidden. The author owns their audience (NQ-1),
    -- so it is never returned here.                                          14.20
    select 'received'::text, 3,
           v.id, null::public.content_type,
           v.author_profile_id, v.subject_profile_id,
           null::public.audience,
           null::jsonb, v.body, null::smallint,
           v.created_at, null::timestamptz,
           null::public.story_label_kind, null::text
    from public.vouches v
    where v.subject_profile_id = p_owner
      and not v.hidden_by_subject
      and private.can_view(v.id, p_viewer)
  ) p
  order by p.section_order, p.top8_position nulls last, p.created_at desc, p.item_id;
$$;
revoke execute on function private.page_items(uuid, uuid) from public;
revoke execute on function private.page_items(uuid, uuid) from anon, authenticated;

-- No visibility logic: an API caller can list a page only as a profile it acts as, or as
-- signed out, exactly as public.can_view. Callers without API claims are trusted.
create or replace function public.page_items(p_owner uuid, p_viewer uuid)
returns table (
  section text,
  item_id uuid,
  content_type public.content_type,
  author_profile_id uuid,
  subject_profile_id uuid,
  audience public.audience,
  details jsonb,
  body text,
  top8_position smallint,
  created_at timestamptz,
  expires_at timestamptz,
  story_label_kind public.story_label_kind,
  story_label_text text
)
language sql
stable
security definer
set search_path = ''
as $$
  select pi.section, pi.item_id, pi.content_type, pi.author_profile_id, pi.subject_profile_id,
         pi.audience, pi.details, pi.body, pi.top8_position, pi.created_at, pi.expires_at,
         pi.story_label_kind, pi.story_label_text
  from private.page_items(
    p_owner,
    case when p_viewer is not null
              and private.is_api_caller()
              and not public.acts_as(p_viewer)
         then null
         else p_viewer
    end) pi;
$$;
revoke execute on function public.page_items(uuid, uuid) from public;
revoke execute on function public.page_items(uuid, uuid) from anon, authenticated;
grant execute on function public.page_items(uuid, uuid) to anon, authenticated;

-- The one place a caller may evaluate as another profile, and only on a page it acts as (Req 21.2).
-- The simulated viewer is passed unchanged; every row still passes private.can_view (Req 21.4).
create or replace function public.view_as(p_owner_profile_id uuid, p_simulated_viewer uuid)
returns table (
  section text,
  item_id uuid,
  content_type public.content_type,
  author_profile_id uuid,
  subject_profile_id uuid,
  audience public.audience,
  details jsonb,
  body text,
  top8_position smallint,
  created_at timestamptz,
  expires_at timestamptz,
  story_label_kind public.story_label_kind,
  story_label_text text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.acts_as(p_owner_profile_id) then           -- false, never null, for a null id
    raise exception using errcode = 'PT403', message = 'view_as.not_owner';           -- 21.2
  end if;
  return query
    select pi.section, pi.item_id, pi.content_type, pi.author_profile_id, pi.subject_profile_id,
           pi.audience, pi.details, pi.body, pi.top8_position, pi.created_at, pi.expires_at,
           pi.story_label_kind, pi.story_label_text
    from private.page_items(p_owner_profile_id, p_simulated_viewer) pi;
end;
$$;
revoke execute on function public.view_as(uuid, uuid) from public;
revoke execute on function public.view_as(uuid, uuid) from anon, authenticated;
grant execute on function public.view_as(uuid, uuid) to authenticated;
;
