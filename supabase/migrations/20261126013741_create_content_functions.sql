-- Migration 13: the content and vouch RPCs and the vouch_received notification.
-- Spec 00 Req 11.7, 11.16, 14.5 to 14.18, 14.21, 14.23, 15.10, 22.3; design "Content and vouch
-- guards and RPCs", "Signals", "Function execute grants", "Error Handling", NQ-2, D-3, DR-4.
-- Structural rules stay in the table triggers of migration 12; these functions add the acting
-- checks and make an item and its circle links one request (Req 11.7: PostgREST runs one
-- statement per request, so two requests would briefly expose a circles item).
-- Every function revokes execute from public, anon and authenticated before its grant.
-- None of them reads circles.private_name or circles.member_label.
-- ---------------------------------------------------------------------------------------------
-- create_content_item: the acting profile creates an item and, for audience circles, its links.
-- A null audience gets the table default (connections, or public for writing). Circle ownership
-- is checked by item_circles_guard and the at-least-one-link rule by the deferred
-- content_items_circles_present, both within this same request.
-- ---------------------------------------------------------------------------------------------
create or replace function public.create_content_item(
  p_owner uuid,
  p_type public.content_type,
  p_details jsonb,
  p_audience public.audience default null,
  p_circle_ids uuid[] default null,
  p_parent_id uuid default null,
  p_group_id uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.acts_as(p_owner) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';             -- 11.16
  end if;
  insert into public.content_items (owner_profile_id, content_type, details, audience, parent_id, group_id)
  values (p_owner, p_type, coalesce(p_details, '{}'::jsonb), p_audience, p_parent_id, p_group_id)
  returning id into v_id;
  if p_audience = 'circles' then
    insert into public.item_circles (content_item_id, circle_id)
    select distinct v_id, c.circle_id from pg_catalog.unnest(p_circle_ids) as c(circle_id);
  end if;
  return v_id;
end;
$$;
revoke execute on function public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid) from public;
revoke execute on function public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid) from anon, authenticated;
grant execute on function public.create_content_item(uuid, public.content_type, jsonb, public.audience, uuid[], uuid, uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- create_vouch: the acting profile vouches for a subject (14.7, 14.10). Default audience public
-- (NQ-2); an explicit null also becomes public. Eligibility, self, managed page and business to
-- person are decided by vouches_guard_insert; one vouch per pair by vouches_author_subject_key.
-- ---------------------------------------------------------------------------------------------
create or replace function public.create_vouch(
  p_author uuid,
  p_subject uuid,
  p_body text,
  p_audience public.audience default 'public',
  p_circle_ids uuid[] default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_audience public.audience := coalesce(p_audience, 'public'::public.audience);
begin
  if not public.acts_as(p_author) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';             -- 14.7
  end if;
  insert into public.vouches (author_profile_id, subject_profile_id, body, audience)
  values (p_author, p_subject, p_body, v_audience)
  returning id into v_id;
  if v_audience = 'circles' then
    insert into public.item_circles (vouch_id, circle_id)
    select distinct v_id, c.circle_id from pg_catalog.unnest(p_circle_ids) as c(circle_id);
  end if;
  return v_id;
end;
$$;
revoke execute on function public.create_vouch(uuid, uuid, text, public.audience, uuid[]) from public;
revoke execute on function public.create_vouch(uuid, uuid, text, public.audience, uuid[]) from anon, authenticated;
grant execute on function public.create_vouch(uuid, uuid, text, public.audience, uuid[]) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- set_item_audience: the owner of a content item, or the author of a vouch, sets its audience
-- and replaces its circle links in one request (11.7, 14.11, 14.12). A missing item and an item
-- the caller does not own give the same not_found, so probing an id reveals nothing.
-- Writing stays public (content_items_writing_public); a vouch never takes group (D-5).
-- ---------------------------------------------------------------------------------------------
create or replace function public.set_item_audience(
  p_item_id uuid,
  p_audience public.audience,
  p_circle_ids uuid[] default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_kind text;
begin
  select ci.owner_profile_id, 'content' into v_owner, v_kind
  from public.content_items ci where ci.id = p_item_id;
  if not found then
    select v.author_profile_id, 'vouch' into v_owner, v_kind
    from public.vouches v where v.id = p_item_id;
  end if;
  if v_owner is null or not public.acts_as(v_owner) then
    raise exception using errcode = 'PT404', message = 'content.not_found';
  end if;
  if v_kind = 'content' then
    update public.content_items ci set audience = p_audience where ci.id = p_item_id;
    delete from public.item_circles ic where ic.content_item_id = p_item_id;
    if p_audience = 'circles' then
      insert into public.item_circles (content_item_id, circle_id)
      select distinct p_item_id, c.circle_id from pg_catalog.unnest(p_circle_ids) as c(circle_id);
    end if;
  else
    update public.vouches v set audience = p_audience where v.id = p_item_id;
    delete from public.item_circles ic where ic.vouch_id = p_item_id;
    if p_audience = 'circles' then
      insert into public.item_circles (vouch_id, circle_id)
      select distinct p_item_id, c.circle_id from pg_catalog.unnest(p_circle_ids) as c(circle_id);
    end if;
  end if;
  -- item_circles_last_link and the circles_present checks run at commit of this request.
end;
$$;
revoke execute on function public.set_item_audience(uuid, public.audience, uuid[]) from public;
revoke execute on function public.set_item_audience(uuid, public.audience, uuid[]) from anon, authenticated;
grant execute on function public.set_item_audience(uuid, public.audience, uuid[]) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- item_audience: the owner's read path for an item's audience and linked circle ids (D-3).
-- Returns no row unless the caller acts as the owner (the vouch author); never raises.
-- Circle ids only, never names.
-- ---------------------------------------------------------------------------------------------
create or replace function public.item_audience(p_item_id uuid)
returns table (audience public.audience, circle_ids uuid[])
language sql
stable
security definer
set search_path = ''
as $$
  select it.audience,
         coalesce((select pg_catalog.array_agg(l.circle_id order by l.created_at, l.circle_id)
                   from (select ic.circle_id, ic.created_at from public.item_circles ic
                         where ic.content_item_id = p_item_id
                         union all
                         select ic.circle_id, ic.created_at from public.item_circles ic
                         where ic.vouch_id = p_item_id) as l),
                  '{}'::uuid[])
  from (select ci.audience, ci.owner_profile_id as owner from public.content_items ci
        where ci.id = p_item_id
        union all
        select v.audience, v.author_profile_id from public.vouches v
        where v.id = p_item_id) as it
  where public.acts_as(it.owner);
$$;
revoke execute on function public.item_audience(uuid) from public;
revoke execute on function public.item_audience(uuid) from anon, authenticated;
grant execute on function public.item_audience(uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- set_top8: the author's whole Top 8 in one call, in order (14.16 to 14.18). A null or empty
-- list clears it. vouches_top8_uq is deferred, so swaps and replacements pass at commit.
-- ---------------------------------------------------------------------------------------------
create or replace function public.set_top8(p_author uuid, p_vouch_ids uuid[])
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := coalesce(p_vouch_ids, '{}'::uuid[]);
begin
  if not public.acts_as(p_author) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';
  end if;
  if pg_catalog.cardinality(v_ids) > 8 then
    raise exception using errcode = 'PT422', message = 'vouch.top8_full';                -- 14.16
  end if;
  if pg_catalog.cardinality(v_ids)
     <> (select count(distinct x) from pg_catalog.unnest(v_ids) as x) then
    raise exception using errcode = 'PT422', message = 'vouch.top8_duplicate';           -- 14.17
  end if;
  if exists (select 1 from pg_catalog.unnest(v_ids) as x
             where not exists (select 1 from public.vouches v
                               where v.id = x and v.author_profile_id = p_author)) then
    raise exception using errcode = 'PT422', message = 'vouch.top8_not_author';
  end if;
  update public.vouches v set top8_position = null
  where v.author_profile_id = p_author and v.top8_position is not null;
  update public.vouches v set top8_position = o.pos::smallint
  from pg_catalog.unnest(v_ids) with ordinality as o(id, pos)
  where v.id = o.id;
end;
$$;
revoke execute on function public.set_top8(uuid, uuid[]) from public;
revoke execute on function public.set_top8(uuid, uuid[]) from anon, authenticated;
grant execute on function public.set_top8(uuid, uuid[]) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- my_received_vouches: the subject's read path, hidden vouches included, so the subject can
-- unhide them (14.21; D-3). Needs acts_as on the subject.
-- ---------------------------------------------------------------------------------------------
create or replace function public.my_received_vouches(p_subject uuid)
returns table (
  vouch_id uuid,
  author_profile_id uuid,
  body text,
  hidden_by_subject boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.acts_as(p_subject) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';             -- 14.21
  end if;
  return query
  select v.id, v.author_profile_id, v.body, v.hidden_by_subject, v.created_at
  from public.vouches v
  where v.subject_profile_id = p_subject
  order by v.created_at desc, v.id;
end;
$$;
revoke execute on function public.my_received_vouches(uuid) from public;
revoke execute on function public.my_received_vouches(uuid) from anon, authenticated;
grant execute on function public.my_received_vouches(uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- vouch_received notification (14.23). reference_id is the vouch id. data holds only what
-- private.notify adds (actor handle, display name, type): never the vouch body (15.10).
-- ---------------------------------------------------------------------------------------------
create or replace function private.vouches_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify(new.subject_profile_id, 'vouch_received', new.author_profile_id, new.id, null);
  return null;
end;
$$;
revoke execute on function private.vouches_after_insert() from public;
revoke execute on function private.vouches_after_insert() from anon, authenticated;
create trigger vouches_after_insert
  after insert on public.vouches
  for each row execute function private.vouches_after_insert();
;
