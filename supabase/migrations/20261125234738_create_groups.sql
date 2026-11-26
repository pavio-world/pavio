-- Migration 11: groups and group members (stretch), groups_guard, public.in_group and
-- public.group_linked_circle. The tables stay empty until the groups flag is on (Req 19.8).
-- Spec 00 Req 19.1, 19.2, 19.3, 19.7, 22.1 to 22.3; design "groups and group_members (stretch)",
-- "Stretch helpers", "Row Level Security policies", "Grants and revokes strategy" (DR-4),
-- "Circle private name guarantee" item 4.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  circle_id uuid references public.circles (id) on delete set null,                    -- 19.1
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint groups_name_length check (char_length(name) between 1 and 80)
);

-- Every foreign key has an index.
create index groups_owner_profile_id_idx on public.groups (owner_profile_id);
create index groups_circle_id_idx on public.groups (circle_id);

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint group_members_group_profile_key unique (group_id, profile_id)              -- 19.3
);

-- group_id leads the unique key; profile_id gets its own index.
create index group_members_profile_id_idx on public.group_members (profile_id);

create trigger groups_set_updated_at
  before update on public.groups
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- groups_guard: a linked circle must belong to the group owner (Req 19.1). Binds every writer.
-- A circle_id that does not exist is left to the foreign key.
-- ---------------------------------------------------------------------------------------------

create or replace function private.groups_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.circle_id is not null
     and (select c.owner_profile_id from public.circles c where c.id = new.circle_id)
         <> new.owner_profile_id then
    raise exception using errcode = 'PT422', message = 'group.circle_not_owned';
  end if;
  return new;
end;
$$;
revoke execute on function private.groups_guard() from public;
revoke execute on function private.groups_guard() from anon, authenticated;

create trigger groups_guard
  before insert or update on public.groups
  for each row execute function private.groups_guard();

-- ---------------------------------------------------------------------------------------------
-- Stretch helpers, signed in only (function execute grants table, DR-4).
-- ---------------------------------------------------------------------------------------------

-- True when any profile the signed in login controls is a member of the group.
create or replace function public.in_group(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group
      and gm.profile_id in (select public.my_profile_ids())
  );
$$;
revoke execute on function public.in_group(uuid) from public;
revoke execute on function public.in_group(uuid) from anon;
grant execute on function public.in_group(uuid) to authenticated;

-- The linked circle of a group, or null unless the caller acts as the group owner (Req 19.2).
create or replace function public.group_linked_circle(p_group uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select g.circle_id
  from public.groups g
  where g.id = p_group
    and public.acts_as(g.owner_profile_id);
$$;
revoke execute on function public.group_linked_circle(uuid) from public;
revoke execute on function public.group_linked_circle(uuid) from anon;
grant execute on function public.group_linked_circle(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 19.2, 19.7, 22.1 to 22.3). anon has nothing.
-- groups.circle_id is writable by the owner but never granted for SELECT (Req 19.2).
-- ---------------------------------------------------------------------------------------------

alter table public.groups enable row level security;
revoke all on table public.groups from anon, authenticated;

grant select (id, owner_profile_id, name, created_at, updated_at) on table public.groups to authenticated;
grant insert (owner_profile_id, name, circle_id) on table public.groups to authenticated;
grant update (owner_profile_id, name, circle_id) on table public.groups to authenticated;
grant delete on table public.groups to authenticated;

create policy groups_authenticated_select on public.groups
  for select to authenticated
  using (public.acts_as(owner_profile_id) or public.in_group(id));
create policy groups_authenticated_insert on public.groups
  for insert to authenticated with check (public.acts_as(owner_profile_id));
create policy groups_authenticated_update on public.groups
  for update to authenticated
  using (public.acts_as(owner_profile_id))
  with check (public.acts_as(owner_profile_id));
create policy groups_authenticated_delete on public.groups
  for delete to authenticated using (public.acts_as(owner_profile_id));

alter table public.group_members enable row level security;
revoke all on table public.group_members from anon, authenticated;

grant select, insert, delete on table public.group_members to authenticated;

create policy group_members_authenticated_select on public.group_members
  for select to authenticated
  using (
    public.in_group(group_id)
    or exists (
      select 1 from public.groups g
      where g.id = group_id and public.acts_as(g.owner_profile_id)
    )
  );
create policy group_members_authenticated_insert on public.group_members
  for insert to authenticated
  with check (exists (
    select 1 from public.groups g
    where g.id = group_id and public.acts_as(g.owner_profile_id)
  ));
create policy group_members_authenticated_delete on public.group_members
  for delete to authenticated
  using (exists (
    select 1 from public.groups g
    where g.id = group_id and public.acts_as(g.owner_profile_id)
  ));
;
