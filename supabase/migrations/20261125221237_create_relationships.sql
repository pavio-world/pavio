-- Migration 8: relationships, their structural guards, notification triggers and the
-- relationship helpers used by can_view.
-- Spec 00 Req 8.1 to 8.3, 8.6 to 8.12, 8.18, 8.20, 8.21, 15.3 to 15.6, 22.1 to 22.3; design
-- "relationships", "Relationship functions", "Helper functions", "Signals", "Error Handling";
-- decision 003. RLS is enabled with no policies and no grants: all access goes through the
-- security definer RPCs of migration 9. The circle cleanup on delete comes with circles (migration 10).
-- ---------------------------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------------------------
create table public.relationships (
  id uuid primary key default gen_random_uuid(),
  requester_profile_id uuid not null references public.profiles (id) on delete cascade,
  target_profile_id uuid not null references public.profiles (id) on delete cascade,
  type public.relationship_type not null,
  status public.relationship_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint relationships_not_self check (requester_profile_id <> target_profile_id),
  -- A follow is always accepted; only a connection can be pending or declined (Req 8.6).
  constraint relationships_follow_accepted check (type = 'connection' or status = 'accepted')
);
-- At most one relationship per unordered pair and type (Req 8.12). Also serves is_connected and follows.
create unique index relationships_pair_uq on public.relationships (
  least(requester_profile_id, target_profile_id),
  greatest(requester_profile_id, target_profile_id),
  type
);
-- Every foreign key has a leading index. The target index also serves counts and all followers.
create index relationships_requester_profile_id_idx on public.relationships (requester_profile_id);
create index relationships_target_type_status_idx on public.relationships (target_profile_id, type, status);
-- ---------------------------------------------------------------------------------------------
-- Guards. They bind every writer, including the seed and tests run as postgres (decision 003).
-- ---------------------------------------------------------------------------------------------
create or replace function private.relationships_guard_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_requester_type public.profile_type;
  v_target_type public.profile_type;
  v_existing record;
begin
  select p.type into v_requester_type from public.profiles p where p.id = new.requester_profile_id;
  select p.type into v_target_type from public.profiles p where p.id = new.target_profile_id;
  if v_requester_type is null or v_target_type is null then
    raise exception using errcode = 'PT404', message = 'relationship.profile_not_found';
  end if;
  if new.requester_profile_id = new.target_profile_id then
    raise exception using errcode = 'PT422', message = 'relationship.self';                  -- 8.10
  end if;
  if private.share_controller(new.requester_profile_id, new.target_profile_id) then
    raise exception using errcode = 'PT422', message = 'relationship.managed_page';          -- 8.11
  end if;
  if v_requester_type = 'business' and v_target_type = 'person' then
    raise exception using errcode = 'PT422', message = 'relationship.business_to_person';    -- 8.7
  end if;
  if new.type = 'follow' then
    if v_requester_type <> 'person' or v_target_type <> 'business' then
      raise exception using errcode = 'PT422', message = 'relationship.follow_shape';        -- 8.8
    end if;
    new.status := 'accepted';                                                                -- 8.6
  else
    if v_requester_type <> v_target_type then
      raise exception using errcode = 'PT422', message = 'relationship.connection_shape';    -- 8.9
    end if;
    new.status := 'pending';                                                                 -- 8.2, 8.3
  end if;
  select r.id, r.status, r.target_profile_id into v_existing
  from public.relationships r
  where least(r.requester_profile_id, r.target_profile_id)
          = least(new.requester_profile_id, new.target_profile_id)
    and greatest(r.requester_profile_id, r.target_profile_id)
          = greatest(new.requester_profile_id, new.target_profile_id)
    and r.type = new.type
  for update;
  if found then
    if new.type = 'connection' and v_existing.status = 'declined'
       and v_existing.target_profile_id = new.requester_profile_id then
      delete from public.relationships r where r.id = v_existing.id;                         -- 8.18
    else
      -- Same message for a pending duplicate and a declined one (Req 8.16, 8.19).
      raise exception using errcode = 'PT409', message = 'relationship.exists';              -- 8.12
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function private.relationships_guard_insert() from public;
revoke execute on function private.relationships_guard_insert() from anon, authenticated;
create trigger relationships_guard_insert
  before insert on public.relationships
  for each row execute function private.relationships_guard_insert();
create or replace function private.relationships_guard_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.requester_profile_id <> old.requester_profile_id
     or new.target_profile_id <> old.target_profile_id
     or new.type <> old.type then
    raise exception using errcode = 'PT422', message = 'relationship.immutable';             -- 8.20
  end if;
  if new.status <> old.status then
    if not (old.type = 'connection' and old.status = 'pending'
            and new.status in ('accepted', 'declined')) then
      raise exception using errcode = 'PT422', message = 'relationship.bad_transition';
    end if;
    if private.is_api_caller() and not public.acts_as(old.target_profile_id) then
      raise exception using errcode = 'PT403', message = 'relationship.only_target_responds'; -- 8.21
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function private.relationships_guard_update() from public;
revoke execute on function private.relationships_guard_update() from anon, authenticated;
create trigger relationships_guard_update
  before update on public.relationships
  for each row execute function private.relationships_guard_update();
create trigger relationships_set_updated_at
  before update on public.relationships
  for each row execute function private.set_updated_at();
-- ---------------------------------------------------------------------------------------------
-- Notification triggers (Req 15.3 to 15.6). reference_id is the relationship id.
-- ---------------------------------------------------------------------------------------------
create or replace function private.relationships_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'connection' then
    perform private.notify(new.target_profile_id, 'connection_request', new.requester_profile_id, new.id, null); -- 15.3
  else
    perform private.notify(new.target_profile_id, 'new_follower', new.requester_profile_id, new.id, null);       -- 15.6
  end if;
  return null;
end;
$$;
revoke execute on function private.relationships_after_insert() from public;
revoke execute on function private.relationships_after_insert() from anon, authenticated;
create trigger relationships_after_insert
  after insert on public.relationships
  for each row execute function private.relationships_after_insert();
-- Only a real pending to accepted change notifies, so a no-op update (seed re-run) adds nothing,
-- and a decline creates nothing (Req 15.4, 15.5).
create or replace function private.relationships_after_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify(new.requester_profile_id, 'connection_accepted', new.target_profile_id, new.id, null);
  return null;
end;
$$;
revoke execute on function private.relationships_after_update() from public;
revoke execute on function private.relationships_after_update() from anon, authenticated;
create trigger relationships_after_update
  after update of status on public.relationships
  for each row
  when (old.status = 'pending' and new.status = 'accepted')
  execute function private.relationships_after_update();
-- ---------------------------------------------------------------------------------------------
-- Relationship helpers for can_view and the all followers audience. Not callable by the API.
-- ---------------------------------------------------------------------------------------------
create or replace function private.is_connected(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.relationships r
    where least(r.requester_profile_id, r.target_profile_id) = least(a, b)
      and greatest(r.requester_profile_id, r.target_profile_id) = greatest(a, b)
      and r.type = 'connection'
      and r.status = 'accepted'
  );
$$;
revoke execute on function private.is_connected(uuid, uuid) from public;
revoke execute on function private.is_connected(uuid, uuid) from anon, authenticated;
create or replace function private.follows(p_person uuid, p_business uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.relationships r
    where least(r.requester_profile_id, r.target_profile_id) = least(p_person, p_business)
      and greatest(r.requester_profile_id, r.target_profile_id) = greatest(p_person, p_business)
      and r.type = 'follow'
      and r.requester_profile_id = p_person
      and r.target_profile_id = p_business
  );
$$;
revoke execute on function private.follows(uuid, uuid) from public;
revoke execute on function private.follows(uuid, uuid) from anon, authenticated;
-- The owner's audience for 'connections': accepted connections and, for a business, followers.
create or replace function private.in_audience(p_owner uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_connected(p_owner, p_viewer)
      or (
        exists (select 1 from public.profiles p where p.id = p_owner and p.type = 'business')
        and private.follows(p_viewer, p_owner)
      );
$$;
revoke execute on function private.in_audience(uuid, uuid) from public;
revoke execute on function private.in_audience(uuid, uuid) from anon, authenticated;
-- ---------------------------------------------------------------------------------------------
-- Row Level Security: enabled with no policies and no grants, so direct access is denied
-- (decision 003).
-- ---------------------------------------------------------------------------------------------
alter table public.relationships enable row level security;
revoke all on table public.relationships from anon, authenticated;
;
