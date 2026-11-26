-- Migration 12: content items, vouches, item circle links, their guards and deferred checks, and
-- the single visibility decision private.can_view with its thin public wrapper public.can_view.
-- Spec 00 Req 11.1 to 11.16, 14.1, 14.3 to 14.15, 14.17, 20.1 to 20.15, 22.1 to 22.4, 23.7;
-- design "content_items", "vouches", "item_circles", "Content details shapes" (NQ-5),
-- "Content and vouch guards and RPCs", "can_view (the single visibility decision)",
-- "Row Level Security policies" (seen(id)), "Grants and revokes strategy", D-3, D-5, D-7, DR-4,
-- "Error Handling"; decisions 001 and 002.
-- One migration because the tables' policies need can_view and can_view needs the tables.
-- The content and vouch RPCs and the vouch_received notification come in migration 13.
-- ---------------------------------------------------------------------------------------------
-- Content details validator (pure, immutable). Keeps execute for anon and authenticated because
-- the check constraint runs with the writer's privileges; private is not exposed, so the API
-- cannot call it by name.
-- Path kinds (NQ-5): writing covers live in public-media (kind 'writing'); gallery and story
-- files live in private-media (kinds 'gallery' and 'story').
-- Any content type added later only needs details to be a JSON object until a branch is added.
-- ---------------------------------------------------------------------------------------------
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
            pg_catalog.jsonb_typeof(p_details -> 'title') = 'string'
        and pg_catalog.char_length(p_details ->> 'title') between 1 and 200
        and pg_catalog.jsonb_typeof(p_details -> 'body') = 'string'
        and pg_catalog.char_length(p_details ->> 'body') between 1 and 50000
        and (p_details -> 'cover_image_path' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'cover_image_path') = 'string'
                 and pg_catalog.split_part(p_details ->> 'cover_image_path', '/', 2) = 'writing'))
      when 'gallery' then
            pg_catalog.jsonb_typeof(p_details -> 'image_path') = 'string'
        and pg_catalog.split_part(p_details ->> 'image_path', '/', 2) = 'gallery'
        and (p_details -> 'caption' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'caption') = 'string'
                 and pg_catalog.char_length(p_details ->> 'caption') <= 500))
      when 'status' then
            pg_catalog.jsonb_typeof(p_details -> 'text') = 'string'
        and pg_catalog.char_length(p_details ->> 'text') between 1 and 100
        and (p_details -> 'emoji' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'emoji') = 'string'
                 and pg_catalog.char_length(p_details ->> 'emoji') <= 8))
      when 'story' then
            (p_details -> 'image_path' is not null or p_details -> 'text' is not null)
        and (p_details -> 'image_path' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'image_path') = 'string'
                 and pg_catalog.split_part(p_details ->> 'image_path', '/', 2) = 'story'))
        and (p_details -> 'text' is null
             or (pg_catalog.jsonb_typeof(p_details -> 'text') = 'string'
                 and pg_catalog.char_length(p_details ->> 'text') between 1 and 280))
        and (p_details -> 'background' is null
             or pg_catalog.jsonb_typeof(p_details -> 'background') = 'string')
      else true
    end,
    false);
$$;
revoke execute on function private.content_details_valid(public.content_type, jsonb) from public;
grant execute on function private.content_details_valid(public.content_type, jsonb) to anon, authenticated;
-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------
create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles (id) on delete cascade,
  content_type public.content_type not null,
  audience public.audience not null,                     -- filled by content_items_before_write
  details jsonb not null default '{}'::jsonb,
  expires_at timestamptz,                                -- set by content_items_before_write
  parent_id uuid references public.content_items (id) on delete cascade,
  group_id uuid references public.groups (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint content_items_writing_public check (content_type <> 'writing' or audience = 'public'),   -- 11.5
  constraint content_items_group_audience check (audience <> 'group' or group_id is not null),      -- 11.9
  constraint content_items_story_expiry check ((content_type = 'story') = (expires_at is not null)), -- 11.10, 11.14
  -- An item can reference only files in its owner's folder.
  constraint content_items_image_path_owner check (
    details ->> 'image_path' is null
    or split_part(details ->> 'image_path', '/', 1) = owner_profile_id::text
  ),
  constraint content_items_cover_image_path_owner check (
    details ->> 'cover_image_path' is null
    or split_part(details ->> 'cover_image_path', '/', 1) = owner_profile_id::text
  ),
  constraint content_items_details_valid check (private.content_details_valid(content_type, details)) -- 11.12
);
-- At most one current status per owner (Req 11.13).
create unique index content_items_one_status_uq on public.content_items (owner_profile_id)
  where content_type = 'status';
-- Page listing; also the leading index of the owner foreign key.
create index content_items_owner_type_created_idx on public.content_items
  (owner_profile_id, content_type, created_at desc);
create index content_items_parent_id_idx on public.content_items (parent_id);
create index content_items_group_id_idx on public.content_items (group_id);
create index content_items_expires_at_idx on public.content_items (expires_at) where expires_at is not null;
-- Storage reads match an object name against details ->> 'image_path'.
create index content_items_image_path_idx on public.content_items ((details ->> 'image_path'));
create table public.vouches (
  id uuid primary key default gen_random_uuid(),
  author_profile_id uuid not null references public.profiles (id) on delete cascade,
  subject_profile_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  audience public.audience not null default 'public',                                 -- NQ-2, 14.10
  top8_position smallint,
  hidden_by_subject boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vouches_body_length check (char_length(body) between 1 and 500),           -- 14.1
  constraint vouches_audience_allowed check (audience in ('public', 'connections', 'circles')), -- D-5
  constraint vouches_top8_position_range check (top8_position is null or top8_position between 1 and 8), -- 14.17
  constraint vouches_not_self check (author_profile_id <> subject_profile_id),           -- 14.5
  -- One vouch per author and subject (14.9); also the leading index of the author foreign key.
  constraint vouches_author_subject_key unique (author_profile_id, subject_profile_id),
  -- One featured vouch per position per author, checked at commit so swaps pass (14.16 to 14.18).
  -- Nulls are distinct, so unfeatured vouches never collide.
  constraint vouches_top8_uq unique (author_profile_id, top8_position) deferrable initially deferred
);
create index vouches_subject_profile_id_idx on public.vouches (subject_profile_id);
-- Search_Trust counts featured public vouches about a subject (NQ-2, NQ-4).
create index vouches_trust_idx on public.vouches (subject_profile_id)
  where top8_position is not null and audience = 'public';
create index vouches_author_top8_idx on public.vouches (author_profile_id, top8_position)
  where top8_position is not null;
create table public.item_circles (
  id uuid primary key default gen_random_uuid(),
  content_item_id uuid references public.content_items (id) on delete cascade,
  vouch_id uuid references public.vouches (id) on delete cascade,
  circle_id uuid not null references public.circles (id) on delete cascade,             -- 9.18
  created_at timestamptz not null default now(),
  constraint item_circles_one_item check (num_nonnulls(content_item_id, vouch_id) = 1),
  constraint item_circles_content_item_circle_key unique (content_item_id, circle_id),
  constraint item_circles_vouch_circle_key unique (vouch_id, circle_id)
);
-- The two partial indexes used by the union all branches of private.can_view.
create index item_circles_content_item_idx on public.item_circles (content_item_id)
  where content_item_id is not null;
create index item_circles_vouch_idx on public.item_circles (vouch_id) where vouch_id is not null;
create index item_circles_circle_id_idx on public.item_circles (circle_id);
create trigger content_items_set_updated_at
  before update on public.content_items
  for each row execute function private.set_updated_at();
create trigger vouches_set_updated_at
  before update on public.vouches
  for each row execute function private.set_updated_at();
-- ---------------------------------------------------------------------------------------------
-- Content guards. They bind every writer, including the seed and tests run as postgres.
-- Acting checks for API callers are the RLS write policies (Req 11.16).
-- ---------------------------------------------------------------------------------------------
create or replace function private.content_items_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.audience is null then
      new.audience := case when new.content_type = 'writing' then 'public' else 'connections' end; -- 11.4, 11.6
    end if;
    -- API callers always get the server time; trusted callers (seed, tests) may back-date to
    -- build expired stories.
    if private.is_api_caller() then
      new.created_at := pg_catalog.now();
    end if;
    new.expires_at := case when new.content_type = 'story'
                           then new.created_at + interval '24 hours' end;               -- 11.10
    if new.content_type = 'status' then                                                 -- 11.13
      -- Only the other status rows, so an upsert of this same row survives.
      delete from public.content_items ci
      where ci.owner_profile_id = new.owner_profile_id
        and ci.content_type = 'status'
        and ci.id <> new.id;
    end if;
  else
    if new.owner_profile_id <> old.owner_profile_id or new.content_type <> old.content_type then
      raise exception using errcode = 'PT422', message = 'content.immutable';
    end if;
    if private.is_api_caller() then
      -- The API cannot back-date an item or extend a story.
      new.created_at := old.created_at;
      new.expires_at := old.expires_at;
    elsif new.content_type = 'story' then
      new.expires_at := new.created_at + interval '24 hours';     -- a seed re-run refreshes stories
    end if;
  end if;
  if new.parent_id is not null then
    if (select ci.owner_profile_id from public.content_items ci where ci.id = new.parent_id)
       <> new.owner_profile_id then
      raise exception using errcode = 'PT422', message = 'content.parent_owner';            -- 11.11
    end if;
    -- A parent chain may never loop back to this item, so can_view's parent recursion ends.
    if new.parent_id = new.id or exists (
      with recursive chain(item_id) as (
        select ci.parent_id from public.content_items ci where ci.id = new.parent_id
        union
        select ci.parent_id from public.content_items ci join chain on ci.id = chain.item_id
      )
      select 1 from chain where chain.item_id = new.id
    ) then
      raise exception using errcode = 'PT422', message = 'content.parent_cycle';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function private.content_items_before_write() from public;
revoke execute on function private.content_items_before_write() from anon, authenticated;
create trigger content_items_before_write
  before insert or update on public.content_items
  for each row execute function private.content_items_before_write();
-- Deferred check (Req 11.7): an item with audience circles has at least one link at commit.
-- It reads the row as it is at commit, so an item deleted or moved off circles later in the same
-- transaction passes.
create or replace function private.content_items_circles_present()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.content_items ci where ci.id = new.id and ci.audience = 'circles')
     and not exists (select 1 from public.item_circles ic where ic.content_item_id = new.id) then
    raise exception using errcode = 'PT422', message = 'content.circles_required';
  end if;
  return null;
end;
$$;
revoke execute on function private.content_items_circles_present() from public;
revoke execute on function private.content_items_circles_present() from anon, authenticated;
create constraint trigger content_items_circles_present
  after insert or update of audience on public.content_items
  deferrable initially deferred
  for each row execute function private.content_items_circles_present();
-- ---------------------------------------------------------------------------------------------
-- Vouch guards (Req 14.5 to 14.8, 14.11, 14.13 to 14.15).
-- ---------------------------------------------------------------------------------------------
create or replace function private.vouches_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author_type public.profile_type;
  v_subject_type public.profile_type;
begin
  select p.type into v_author_type from public.profiles p where p.id = new.author_profile_id;
  select p.type into v_subject_type from public.profiles p where p.id = new.subject_profile_id;
  if new.author_profile_id = new.subject_profile_id then
    raise exception using errcode = 'PT422', message = 'vouch.self';                        -- 14.5
  end if;
  if private.share_controller(new.author_profile_id, new.subject_profile_id) then
    raise exception using errcode = 'PT422', message = 'vouch.managed_page';                -- 14.6
  end if;
  if v_author_type = 'business' and v_subject_type = 'person' then
    raise exception using errcode = 'PT422', message = 'vouch.business_to_person';          -- 14.8
  end if;
  if not coalesce(
       (v_author_type = v_subject_type
          and private.is_connected(new.author_profile_id, new.subject_profile_id))
       or (v_author_type = 'person' and v_subject_type = 'business'
          and private.follows(new.author_profile_id, new.subject_profile_id)),
       false) then
    raise exception using errcode = 'PT422', message = 'vouch.not_eligible';                -- 14.7
  end if;
  new.hidden_by_subject := false;
  return new;
end;
$$;
revoke execute on function private.vouches_guard_insert() from public;
revoke execute on function private.vouches_guard_insert() from anon, authenticated;
create trigger vouches_guard_insert
  before insert on public.vouches
  for each row execute function private.vouches_guard_insert();
create or replace function private.vouches_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.author_profile_id <> old.author_profile_id
     or new.subject_profile_id <> old.subject_profile_id then
    raise exception using errcode = 'PT422', message = 'vouch.immutable';
  end if;
  if private.is_api_caller() then
    if (new.body, new.audience, new.top8_position) is distinct from (old.body, old.audience, old.top8_position)
       and not public.acts_as(old.author_profile_id) then
      raise exception using errcode = 'PT403', message = 'vouch.author_only';               -- 14.11, 14.14
    end if;
    if new.hidden_by_subject <> old.hidden_by_subject
       and not public.acts_as(old.subject_profile_id) then
      raise exception using errcode = 'PT403', message = 'vouch.subject_only';              -- 14.13, 14.15
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function private.vouches_guard_update() from public;
revoke execute on function private.vouches_guard_update() from anon, authenticated;
create trigger vouches_guard_update
  before update on public.vouches
  for each row execute function private.vouches_guard_update();
-- Same deferred check as content_items_circles_present, for vouches (Req 11.7, 14.12).
create or replace function private.vouches_circles_present()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.vouches v where v.id = new.id and v.audience = 'circles')
     and not exists (select 1 from public.item_circles ic where ic.vouch_id = new.id) then
    raise exception using errcode = 'PT422', message = 'content.circles_required';
  end if;
  return null;
end;
$$;
revoke execute on function private.vouches_circles_present() from public;
revoke execute on function private.vouches_circles_present() from anon, authenticated;
create constraint trigger vouches_circles_present
  after insert or update of audience on public.vouches
  deferrable initially deferred
  for each row execute function private.vouches_circles_present();
-- ---------------------------------------------------------------------------------------------
-- Item circle link guards (Req 11.7, 11.8, 14.12; D-7).
-- ---------------------------------------------------------------------------------------------
-- A link may point only at a circle owned by the item's owner (the vouch author). A missing item
-- or circle is left to the foreign keys.
create or replace function private.item_circles_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  v_owner := coalesce(
    (select ci.owner_profile_id from public.content_items ci where ci.id = new.content_item_id),
    (select v.author_profile_id from public.vouches v where v.id = new.vouch_id));
  if (select c.owner_profile_id from public.circles c where c.id = new.circle_id) <> v_owner then
    raise exception using errcode = 'PT422', message = 'audience.circle_not_owned';
  end if;
  return new;
end;
$$;
revoke execute on function private.item_circles_guard() from public;
revoke execute on function private.item_circles_guard() from anon, authenticated;
create trigger item_circles_guard
  before insert or update on public.item_circles
  for each row execute function private.item_circles_guard();
-- D-7: at commit, a transaction may not leave a content item or vouch with audience circles and no
-- link. It passes when the link went with its circle (the item then fails closed: only its owner
-- sees it) and when the item itself was deleted. Runs at commit, so replacing links passes.
create or replace function private.item_circles_last_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.circles c where c.id = old.circle_id) then
    return null;
  end if;
  if old.content_item_id is not null
     and exists (select 1 from public.content_items ci
                 where ci.id = old.content_item_id and ci.audience = 'circles')
     and not exists (select 1 from public.item_circles ic where ic.content_item_id = old.content_item_id) then
    raise exception using errcode = 'PT422', message = 'content.circles_required';
  end if;
  if old.vouch_id is not null
     and exists (select 1 from public.vouches v where v.id = old.vouch_id and v.audience = 'circles')
     and not exists (select 1 from public.item_circles ic where ic.vouch_id = old.vouch_id) then
    raise exception using errcode = 'PT422', message = 'content.circles_required';
  end if;
  return null;
end;
$$;
revoke execute on function private.item_circles_last_link() from public;
revoke execute on function private.item_circles_last_link() from anon, authenticated;
create constraint trigger item_circles_last_link
  after delete on public.item_circles
  deferrable initially deferred
  for each row execute function private.item_circles_last_link();
-- ---------------------------------------------------------------------------------------------
-- can_view: the only visibility logic (Req 20.1 to 20.14; decision 002).
-- A vouch's author is its owner on every page (NQ-1); its subject always sees it, hidden or not.
-- Never raises on a missing or invisible item (Req 20.12).
-- ---------------------------------------------------------------------------------------------
create or replace function private.can_view(p_item_id uuid, p_viewer uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  it record;
begin
  -- 1. Resolve the item: content item first, then vouch (shared uuid space, decision 001).
  select 'content'::text as kind, ci.owner_profile_id as owner, null::uuid as subject,
         ci.audience as audience, ci.expires_at as expires_at,
         ci.parent_id as parent_id, ci.group_id as group_id
    into it
  from public.content_items ci where ci.id = p_item_id;
  if not found then
    select 'vouch'::text as kind, v.author_profile_id as owner, v.subject_profile_id as subject,
           v.audience as audience, null::timestamptz as expires_at,
           null::uuid as parent_id, null::uuid as group_id
      into it
    from public.vouches v where v.id = p_item_id;
    if not found then
      return false;                                                                     -- 20.12
    end if;
  end if;
  -- 2. The owner always sees, including expired items.                                    20.2
  if p_viewer is not null and p_viewer = it.owner then
    return true;
  end if;
  -- 3. A vouch subject always sees the vouch, hidden or not.                         20.3, 20.10
  if it.kind = 'vouch' and p_viewer is not null and p_viewer = it.subject then
    return true;
  end if;
  -- 4. Expiry.                                                                            20.4
  if it.expires_at is not null and it.expires_at <= pg_catalog.now() then
    return false;
  end if;
  -- 5. The parent must also be visible.                                                  20.13
  if it.parent_id is not null and not private.can_view(it.parent_id, p_viewer) then
    return false;
  end if;
  -- 6. Audience.                                                           20.5 to 20.9, 20.11
  case it.audience
    when 'public' then
      return true;
    when 'connections' then
      return p_viewer is not null and private.in_audience(it.owner, p_viewer);
    when 'circles' then
      -- Two union all branches so each uses its own partial index; all followers counted live.
      return p_viewer is not null and exists (
        select 1 from public.item_circles ic
        where ic.content_item_id = p_item_id and private.in_circle(ic.circle_id, p_viewer)
        union all
        select 1 from public.item_circles ic
        where ic.vouch_id = p_item_id and private.in_circle(ic.circle_id, p_viewer)
      );
    when 'group' then
      return p_viewer is not null and exists (
        select 1 from public.group_members gm
        where gm.group_id = it.group_id and gm.profile_id = p_viewer
      );
    else
      return false;
  end case;
end;
$$;
revoke execute on function private.can_view(uuid, uuid) from public;
revoke execute on function private.can_view(uuid, uuid) from anon, authenticated;
-- No visibility logic: an API caller can evaluate only as a profile it acts as, or as signed out
-- (Req 20.15). Callers without API claims (tests, seed, pg_cron) are trusted.
create or replace function public.can_view(p_item_id uuid, p_viewer_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.can_view(
    p_item_id,
    case when p_viewer_profile_id is not null
              and private.is_api_caller()
              and not public.acts_as(p_viewer_profile_id)
         then null
         else p_viewer_profile_id
    end);
$$;
revoke execute on function public.can_view(uuid, uuid) from public;
revoke execute on function public.can_view(uuid, uuid) from anon, authenticated;
grant execute on function public.can_view(uuid, uuid) to anon, authenticated;
-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 11.15, 11.16, 14.3, 14.7, 14.11, 14.21, 22.1 to 22.5; D-3).
-- seen(id) = public.can_view(id, null) or can_view for any profile the login controls.
-- audience and hidden_by_subject are never granted for SELECT (D-3).
-- ---------------------------------------------------------------------------------------------
alter table public.content_items enable row level security;
revoke all on table public.content_items from anon, authenticated;
grant select (
  id, owner_profile_id, content_type, details, expires_at, parent_id, group_id, created_at, updated_at
) on table public.content_items to anon, authenticated;
grant insert (owner_profile_id, content_type, audience, details, parent_id, group_id)
  on table public.content_items to authenticated;
grant update (audience, details, parent_id) on table public.content_items to authenticated;
grant delete on table public.content_items to authenticated;
create policy content_items_anon_select on public.content_items
  for select to anon using (public.can_view(id, null));
create policy content_items_authenticated_select on public.content_items
  for select to authenticated
  using (
    public.can_view(id, null)
    or exists (select 1 from public.my_profile_ids() as m(pid) where public.can_view(id, m.pid))
  );
create policy content_items_authenticated_insert on public.content_items
  for insert to authenticated with check (public.acts_as(owner_profile_id));
create policy content_items_authenticated_update on public.content_items
  for update to authenticated
  using (public.acts_as(owner_profile_id))
  with check (public.acts_as(owner_profile_id));
create policy content_items_authenticated_delete on public.content_items
  for delete to authenticated using (public.acts_as(owner_profile_id));
alter table public.vouches enable row level security;
revoke all on table public.vouches from anon, authenticated;
grant select (id, author_profile_id, subject_profile_id, body, top8_position, created_at, updated_at)
  on table public.vouches to anon, authenticated;
grant insert (author_profile_id, subject_profile_id, body, audience) on table public.vouches to authenticated;
grant update (body, audience, top8_position, hidden_by_subject) on table public.vouches to authenticated;
grant delete on table public.vouches to authenticated;
create policy vouches_anon_select on public.vouches
  for select to anon using (public.can_view(id, null));
-- The subject is always included through can_view (Req 14.21).
create policy vouches_authenticated_select on public.vouches
  for select to authenticated
  using (
    public.can_view(id, null)
    or exists (select 1 from public.my_profile_ids() as m(pid) where public.can_view(id, m.pid))
  );
create policy vouches_authenticated_insert on public.vouches
  for insert to authenticated with check (public.acts_as(author_profile_id));
-- Column rules (author fields vs hidden_by_subject) live in vouches_guard_update.
create policy vouches_authenticated_update on public.vouches
  for update to authenticated
  using (public.acts_as(author_profile_id) or public.acts_as(subject_profile_id));
create policy vouches_authenticated_delete on public.vouches
  for delete to authenticated using (public.acts_as(author_profile_id));
alter table public.item_circles enable row level security;
revoke all on table public.item_circles from anon, authenticated;
grant select, insert, delete on table public.item_circles to authenticated;
create policy item_circles_authenticated_select on public.item_circles
  for select to authenticated
  using (
    exists (select 1 from public.content_items ci
            where ci.id = content_item_id and public.acts_as(ci.owner_profile_id))
    or exists (select 1 from public.vouches v
               where v.id = vouch_id and public.acts_as(v.author_profile_id))
  );
create policy item_circles_authenticated_insert on public.item_circles
  for insert to authenticated
  with check (
    exists (select 1 from public.content_items ci
            where ci.id = content_item_id and public.acts_as(ci.owner_profile_id))
    or exists (select 1 from public.vouches v
               where v.id = vouch_id and public.acts_as(v.author_profile_id))
  );
create policy item_circles_authenticated_delete on public.item_circles
  for delete to authenticated
  using (
    exists (select 1 from public.content_items ci
            where ci.id = content_item_id and public.acts_as(ci.owner_profile_id))
    or exists (select 1 from public.vouches v
               where v.id = vouch_id and public.acts_as(v.author_profile_id))
  );
;
