-- Migration 15: story labels. The single label a viewer sees on a story shared to circles: the
-- member label of the first switched-on linked circle that contains the viewer (Circle_Label_Order),
-- otherwise only_for_you when no linked circle holds anyone but the viewer (D-2), otherwise
-- shared_with_you. No label for the owner, an invisible story or a non-circle audience (NQ-3).
-- Spec 00 Req 13.1 to 13.14, 22.3; design "story_label", "Function execute grants",
-- "Circle private name guarantee", D-1, D-2, NQ-3, DR-4.
-- Returns only a kind and, for member_label, the member label text: never a private name,
-- circle id, count or member identity (Req 13.10). Every call reads current rows (Req 13.11).
-- ---------------------------------------------------------------------------------------------

create or replace function private.story_label(p_story_id uuid, p_viewer uuid)
returns table (kind public.story_label_kind, label text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s record;
  v_first_label text;
  v_others boolean;
begin
  select ci.id, ci.owner_profile_id, ci.audience
    into s
  from public.content_items ci
  where ci.id = p_story_id and ci.content_type = 'story';
  if not found or p_viewer is null or p_viewer = s.owner_profile_id then
    return;                                                                            -- 13.3
  end if;
  if not private.can_view(p_story_id, p_viewer) then
    return;                                                                            -- 13.2
  end if;
  if s.audience <> 'circles' then
    return;                                                                     -- 13.7, NQ-3
  end if;

  -- The first switched-on linked circle that contains the viewer, in Circle_Label_Order.  13.4, 13.9
  select c.member_label
    into v_first_label
  from public.item_circles ic
  join public.circles c on c.id = ic.circle_id
  where ic.content_item_id = p_story_id
    and c.show_member_label
    and private.in_circle(c.id, p_viewer)
  order by c.created_at, c.id
  limit 1;
  if v_first_label is not null then
    return query select 'member_label'::public.story_label_kind, v_first_label;
    return;
  end if;

  -- Does any linked circle hold someone other than the viewer? All followers counts the
  -- current followers (13.8). An empty linked circle holds nobody else (D-2).       13.5, 13.6
  select exists (
    select 1
    from public.item_circles ic
    join public.circles c on c.id = ic.circle_id
    where ic.content_item_id = p_story_id
      and (
            (not c.is_all_followers and exists (
               select 1 from public.circle_members cm
               where cm.circle_id = c.id and cm.member_profile_id <> p_viewer))
         or (c.is_all_followers and exists (
               select 1 from public.relationships r
               where r.target_profile_id = c.owner_profile_id
                 and r.type = 'follow'
                 and r.requester_profile_id <> p_viewer))
      )
  ) into v_others;
  return query
    select (case when v_others then 'shared_with_you' else 'only_for_you' end)::public.story_label_kind,
           null::text;
end;
$$;
revoke execute on function private.story_label(uuid, uuid) from public;
revoke execute on function private.story_label(uuid, uuid) from anon, authenticated;

-- No label logic: an API caller can evaluate only as a profile it acts as, or as signed out
-- (Req 13.12), exactly as public.can_view. Callers without API claims (tests, seed) are trusted.
create or replace function public.story_label(p_story_id uuid, p_viewer_profile_id uuid)
returns table (kind public.story_label_kind, label text)
language sql
stable
security definer
set search_path = ''
as $$
  select sl.kind, sl.label
  from private.story_label(
    p_story_id,
    case when p_viewer_profile_id is not null
              and private.is_api_caller()
              and not public.acts_as(p_viewer_profile_id)
         then null
         else p_viewer_profile_id
    end) sl;
$$;
revoke execute on function public.story_label(uuid, uuid) from public;
revoke execute on function public.story_label(uuid, uuid) from anon, authenticated;
grant execute on function public.story_label(uuid, uuid) to anon, authenticated;
;
