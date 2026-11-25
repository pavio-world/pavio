-- Migration 10: circles, circle members, their guards, private.in_circle, the all followers
-- circle for every business and the circle cleanup when a relationship is deleted.
-- Spec 00 Req 8.22, 9.1 to 9.10, 9.12 to 9.16, 9.18, 10.1, 10.2, 10.6 to 10.8, 22.1 to 22.3, 22.8;
-- design "circles", "circle_members", "Circle guards", "Helper functions", "Profile and business
-- guards" (profiles_after_insert), "Relationship functions" (relationships_after_delete),
-- "Row Level Security policies", "Circle private name guarantee", "Error Handling".
-- Item_Circle_Links (item_circles) and their cascade arrive with content in migration 12.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.circles (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles (id) on delete cascade,
  private_name text not null,
  show_member_label boolean not null default false,                                  -- 9.4
  member_label text,
  is_all_followers boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circles_private_name_length check (char_length(private_name) between 1 and 50),   -- 9.1
  constraint circles_member_label_length check (
    member_label is null or char_length(member_label) between 1 and 50
  ),                                                                                   -- 9.1
  constraint circles_label_when_shown check (not show_member_label or member_label is not null) -- 9.6
);

-- One private name per owner, compared case insensitively (Req 9.3). Also the owner FK index.
create unique index circles_owner_name_uq on public.circles (owner_profile_id, lower(private_name));
-- Exactly one all followers circle per business (Req 10.1).
create unique index circles_all_followers_uq on public.circles (owner_profile_id) where is_all_followers;
-- Circle_Label_Order: ascending created_at, then id, per owner.
create index circles_owner_label_order_idx on public.circles (owner_profile_id, created_at, id);

create table public.circle_members (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles (id) on delete cascade,             -- 9.18
  member_profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint circle_members_circle_member_key unique (circle_id, member_profile_id)  -- 9.15
);

-- Every foreign key has a leading index (circle_id leads the unique key).
create index circle_members_member_profile_id_idx on public.circle_members (member_profile_id);

-- ---------------------------------------------------------------------------------------------
-- Circle guards. They bind every writer, including the seed and tests run as postgres.
-- Error messages are fixed keys and never carry a circle name.
-- ---------------------------------------------------------------------------------------------

create or replace function private.circles_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_all_followers
     and (select p.type from public.profiles p where p.id = new.owner_profile_id) <> 'business' then
    raise exception using errcode = 'PT422', message = 'circle.all_followers_business_only'; -- 10.8
  end if;
  if tg_op = 'UPDATE' then
    if new.owner_profile_id <> old.owner_profile_id or new.is_all_followers <> old.is_all_followers then
      raise exception using errcode = 'PT422', message = 'circle.immutable';
    end if;
    if old.is_all_followers and new.private_name <> old.private_name then
      raise exception using errcode = 'PT422', message = 'circle.all_followers_fixed';      -- 10.6
    end if;
  end if;
  -- Pre-fill the member label from the private name when the switch is on without a label (9.5).
  -- Nothing else touches member_label (9.7, 9.8); circles_label_when_shown enforces 9.6.
  if new.show_member_label and new.member_label is null then
    new.member_label := new.private_name;
  end if;
  return new;
end;
$$;
revoke execute on function private.circles_before_write() from public;
revoke execute on function private.circles_before_write() from anon, authenticated;

create trigger circles_before_write
  before insert or update on public.circles
  for each row execute function private.circles_before_write();

create trigger circles_set_updated_at
  before update on public.circles
  for each row execute function private.set_updated_at();

-- An all followers circle goes only with its business (profile cascade), never on its own (10.6).
create or replace function private.circles_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.is_all_followers
     and exists (select 1 from public.profiles p where p.id = old.owner_profile_id) then
    raise exception using errcode = 'PT422', message = 'circle.all_followers_fixed';
  end if;
  return old;
end;
$$;
revoke execute on function private.circles_before_delete() from public;
revoke execute on function private.circles_before_delete() from anon, authenticated;

create trigger circles_before_delete
  before delete on public.circles
  for each row execute function private.circles_before_delete();

-- Members are hand picked from the owner's audience; all followers is maintained live (9.12, 9.13, 10.6).
create or replace function private.circle_members_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_circle record;
begin
  select c.owner_profile_id, c.is_all_followers into v_circle
  from public.circles c where c.id = new.circle_id;
  if not found then
    return new;                          -- the circle_id foreign key rejects the row
  end if;
  if v_circle.is_all_followers then
    raise exception using errcode = 'PT422', message = 'circle.all_followers_fixed';        -- 10.6
  end if;
  if new.member_profile_id = v_circle.owner_profile_id then
    raise exception using errcode = 'PT422', message = 'circle.self';
  end if;
  if not private.in_audience(v_circle.owner_profile_id, new.member_profile_id) then
    raise exception using errcode = 'PT422', message = 'circle.member_not_connected';       -- 9.13
  end if;
  return new;
end;
$$;
revoke execute on function private.circle_members_guard() from public;
revoke execute on function private.circle_members_guard() from anon, authenticated;

create trigger circle_members_guard
  before insert or update on public.circle_members
  for each row execute function private.circle_members_guard();

-- ---------------------------------------------------------------------------------------------
-- Circle membership helper for can_view and story_label. Not callable by the API.
-- The all followers circle counts the current followers at every read (10.3 to 10.5).
-- ---------------------------------------------------------------------------------------------

create or replace function private.in_circle(p_circle uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
             when c.is_all_followers then private.follows(p_viewer, c.owner_profile_id)
             else exists (
               select 1 from public.circle_members cm
               where cm.circle_id = c.id and cm.member_profile_id = p_viewer
             )
           end
    from public.circles c
    where c.id = p_circle
  ), false);
$$;
revoke execute on function private.in_circle(uuid, uuid) from public;
revoke execute on function private.in_circle(uuid, uuid) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- The all followers circle for every business (Req 10.1, 10.2). Replaces the migration 5 body,
-- keeping its owner row insert (Req 6.7).
-- ---------------------------------------------------------------------------------------------

create or replace function private.profiles_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'business' then
    if auth.uid() is not null then
      insert into public.profile_managers (profile_id, user_id, role)
      values (new.id, auth.uid(), 'owner');                                              -- 6.7
    end if;
    insert into public.circles (owner_profile_id, private_name, is_all_followers)
    values (new.id, 'all followers', true);                                              -- 10.1, 10.2
  end if;
  return null;
end;
$$;
revoke execute on function private.profiles_after_insert() from public;
revoke execute on function private.profiles_after_insert() from anon, authenticated;

-- Backfill: any business created before this migration gets its all followers circle.
insert into public.circles (owner_profile_id, private_name, is_all_followers)
select p.id, 'all followers', true
from public.profiles p
where p.type = 'business'
  and not exists (
    select 1 from public.circles c where c.owner_profile_id = p.id and c.is_all_followers
  );

-- ---------------------------------------------------------------------------------------------
-- Relationship delete cleanup (Req 8.22): the other profile leaves every hand picked circle of
-- both profiles. A pair holds at most one relationship (one type per shape), so no other
-- relationship can still justify these memberships.
-- ---------------------------------------------------------------------------------------------

create or replace function private.relationships_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.circle_members cm
  using public.circles c
  where cm.circle_id = c.id
    and (
          (c.owner_profile_id = old.requester_profile_id and cm.member_profile_id = old.target_profile_id)
       or (c.owner_profile_id = old.target_profile_id and cm.member_profile_id = old.requester_profile_id)
    );
  return null;
end;
$$;
revoke execute on function private.relationships_after_delete() from public;
revoke execute on function private.relationships_after_delete() from anon, authenticated;

create trigger relationships_after_delete
  after delete on public.relationships
  for each row execute function private.relationships_after_delete();

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 9.9, 9.10, 9.16, 22.8). Only logins that act as the owner
-- see or write a circle; anon has nothing. is_all_followers is never writable by the API.
-- ---------------------------------------------------------------------------------------------

alter table public.circles enable row level security;
revoke all on table public.circles from anon, authenticated;

grant select, delete on table public.circles to authenticated;
grant insert (owner_profile_id, private_name, show_member_label, member_label)
  on table public.circles to authenticated;
grant update (private_name, show_member_label, member_label)
  on table public.circles to authenticated;

create policy circles_authenticated_select on public.circles
  for select to authenticated using (public.acts_as(owner_profile_id));
create policy circles_authenticated_insert on public.circles
  for insert to authenticated with check (public.acts_as(owner_profile_id));
create policy circles_authenticated_update on public.circles
  for update to authenticated
  using (public.acts_as(owner_profile_id))
  with check (public.acts_as(owner_profile_id));
create policy circles_authenticated_delete on public.circles
  for delete to authenticated using (public.acts_as(owner_profile_id));

alter table public.circle_members enable row level security;
revoke all on table public.circle_members from anon, authenticated;

grant select, insert, delete on table public.circle_members to authenticated;

create policy circle_members_authenticated_select on public.circle_members
  for select to authenticated
  using (exists (
    select 1 from public.circles c
    where c.id = circle_id and public.acts_as(c.owner_profile_id)
  ));
create policy circle_members_authenticated_insert on public.circle_members
  for insert to authenticated
  with check (exists (
    select 1 from public.circles c
    where c.id = circle_id and public.acts_as(c.owner_profile_id)
  ));
create policy circle_members_authenticated_delete on public.circle_members
  for delete to authenticated
  using (exists (
    select 1 from public.circles c
    where c.id = circle_id and public.acts_as(c.owner_profile_id)
  ));
;
