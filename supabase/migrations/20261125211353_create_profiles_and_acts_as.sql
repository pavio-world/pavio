-- Migration 5: profiles, profile managers and the acting helpers.
-- Spec 00 Req 4.1 to 4.4, 4.8, 4.10 to 4.16, 5.1 to 5.5, 5.7, 6.7, 7.1 to 7.13, 22.6, 22.7; design D-6,
-- "profiles", "profile_managers", "acts_as", "Profile and business guards", "Grants and revokes strategy".
-- The all followers circle for a new business is added by migration 10, not here.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  type public.profile_type not null,
  owner_user_id uuid references auth.users (id) on delete cascade,
  handle text not null,
  display_name text not null,
  bio text,
  avatar_path text,
  cover_path text,
  city text,
  country text,
  preferred_language text not null default 'en'
    references public.languages (code) on update cascade on delete restrict,
  dot_colour public.dot_colour not null default 'terracotta',
  theme jsonb not null default '{}'::jsonb,
  mode_2006 boolean not null default false,
  what_i_do text[] not null default '{}'::text[],
  tags_text text generated always as (private.immutable_array_to_text(what_i_do)) stored,
  -- Computed from what_i_do directly: a generated column cannot reference tags_text.
  search_tsv tsvector generated always as (
    setweight(to_tsvector('simple'::regconfig, private.immutable_array_to_text(what_i_do)), 'A')
    || setweight(to_tsvector('simple'::regconfig, coalesce(bio, '')), 'B')
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Handles are never rewritten (D-6): anything outside the format is rejected (Req 4.3).
  constraint profiles_handle_format check (handle ~ '^[a-z][a-z0-9_]{2,29}$'),
  constraint profiles_display_name_length check (char_length(display_name) between 1 and 80),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 1000),
  constraint profiles_avatar_path_kind check (
    avatar_path is null
    or (split_part(avatar_path, '/', 1) = id::text and split_part(avatar_path, '/', 2) = 'avatar')
  ),
  constraint profiles_cover_path_kind check (
    cover_path is null
    or (split_part(cover_path, '/', 1) = id::text and split_part(cover_path, '/', 2) = 'cover')
  ),
  constraint profiles_city_length check (city is null or char_length(city) <= 80),
  constraint profiles_country_format check (country is null or country ~ '^[A-Z]{2}$'),
  constraint profiles_theme_object check (jsonb_typeof(theme) = 'object'),
  constraint profiles_what_i_do_valid check (private.tags_valid(what_i_do)),
  -- A person always has an owner login; a business never does (its owners are in profile_managers).
  constraint profiles_owner_matches_type check ((type = 'person') = (owner_user_id is not null))
);

-- Case insensitive handle uniqueness (Req 4.2) and one person profile per login (Req 5.2).
create unique index profiles_handle_uq on public.profiles (lower(handle));
create unique index profiles_owner_user_uq on public.profiles (owner_user_id);
-- Directory search (Req 24): trigram and full text indexes.
create index profiles_display_name_trgm_idx on public.profiles
  using gin (lower(display_name) extensions.gin_trgm_ops);
create index profiles_handle_trgm_idx on public.profiles
  using gin (handle extensions.gin_trgm_ops);
create index profiles_tags_text_trgm_idx on public.profiles
  using gin (tags_text extensions.gin_trgm_ops);
create index profiles_bio_trgm_idx on public.profiles
  using gin (lower(coalesce(bio, '')) extensions.gin_trgm_ops);
create index profiles_city_trgm_idx on public.profiles
  using gin (lower(coalesce(city, '')) extensions.gin_trgm_ops);
create index profiles_search_tsv_idx on public.profiles using gin (search_tsv);
create index profiles_city_idx on public.profiles (lower(city));
create index profiles_type_idx on public.profiles (type);
-- Every foreign key has a leading index.
create index profiles_preferred_language_idx on public.profiles (preferred_language);

create table public.profile_managers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.manager_role not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_managers_profile_user_key unique (profile_id, user_id)
);

create index profile_managers_user_id_idx on public.profile_managers (user_id);

-- ---------------------------------------------------------------------------------------------
-- Acting helpers
-- ---------------------------------------------------------------------------------------------

-- Does login p_user control profile p_profile: owns the person, or holds a manager row.
create or replace function private.controls(p_user uuid, p_profile uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
           select 1 from public.profiles p
           where p.id = p_profile and p.owner_user_id = p_user
         )
      or exists (
           select 1 from public.profile_managers m
           where m.profile_id = p_profile and m.user_id = p_user
         );
$$;
revoke execute on function private.controls(uuid, uuid) from public;
revoke execute on function private.controls(uuid, uuid) from anon, authenticated;

-- Is there any login that controls both profiles. Works without auth.uid(), so it binds the seed too.
create or replace function private.share_controller(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select ca.u
    from (
      select p.owner_user_id as u from public.profiles p
      where p.id = a and p.owner_user_id is not null
      union
      select m.user_id from public.profile_managers m where m.profile_id = a
    ) as ca
    intersect
    select cb.u
    from (
      select p.owner_user_id as u from public.profiles p
      where p.id = b and p.owner_user_id is not null
      union
      select m.user_id from public.profile_managers m where m.profile_id = b
    ) as cb
  );
$$;
revoke execute on function private.share_controller(uuid, uuid) from public;
revoke execute on function private.share_controller(uuid, uuid) from anon, authenticated;

-- Does the signed in login control this profile (Req 7.4 to 7.7). False for anon and unknown ids.
create or replace function public.acts_as(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and p_profile_id is not null
     and private.controls(auth.uid(), p_profile_id);
$$;
revoke execute on function public.acts_as(uuid) from public;
grant execute on function public.acts_as(uuid) to anon, authenticated;

-- Every profile the signed in login controls.
create or replace function public.my_profile_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id from public.profiles p where p.owner_user_id = auth.uid()
  union
  select m.profile_id from public.profile_managers m where m.user_id = auth.uid();
$$;
revoke execute on function public.my_profile_ids() from public;
revoke execute on function public.my_profile_ids() from anon;
grant execute on function public.my_profile_ids() to authenticated;

-- The only read path for private profile fields and manager roles (Req 4.16, 22.7).
create or replace function public.my_profiles()
returns table (
  profile_id uuid,
  type public.profile_type,
  handle text,
  display_name text,
  role text,
  preferred_language text,
  mode_2006 boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id,
         p.type,
         p.handle,
         p.display_name,
         case when p.owner_user_id = auth.uid() then 'person' else m.role::text end,
         p.preferred_language,
         p.mode_2006
  from public.profiles p
  left join public.profile_managers m on m.profile_id = p.id and m.user_id = auth.uid()
  where p.owner_user_id = auth.uid() or m.user_id is not null;
$$;
revoke execute on function public.my_profiles() from public;
revoke execute on function public.my_profiles() from anon;
grant execute on function public.my_profiles() to authenticated;

-- Does the signed in login hold the owner role on this business.
create or replace function public.is_profile_owner(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profile_managers m
    where m.profile_id = p_profile_id and m.user_id = auth.uid() and m.role = 'owner'
  );
$$;
revoke execute on function public.is_profile_owner(uuid) from public;
revoke execute on function public.is_profile_owner(uuid) from anon;
grant execute on function public.is_profile_owner(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Profile triggers
-- ---------------------------------------------------------------------------------------------

create or replace function private.profiles_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Tags: distinct, lowercased, trimmed, non empty, in first seen order (Req 4.13).
  if new.what_i_do is not null then
    new.what_i_do := array(
      select x.tag
      from (
        select pg_catalog.lower(pg_catalog.btrim(t.tag)) as tag, pg_catalog.min(t.ord) as first_ord
        from pg_catalog.unnest(new.what_i_do) with ordinality as t(tag, ord)
        where pg_catalog.btrim(t.tag) <> ''
        group by 1
      ) as x
      order by x.first_ord
    );
  end if;

  -- D-6: the handle is never rewritten. Reserved words are compared as given, and only when the
  -- handle is set or changed, so a word reserved later never blocks other updates (Req 4.4).
  if (tg_op = 'INSERT' or new.handle is distinct from old.handle)
     and exists (select 1 from public.reserved_handles r where r.word = new.handle) then
    raise exception using errcode = 'PT422', message = 'profile.handle_reserved';
  end if;

  if tg_op = 'INSERT' then
    if new.type = 'person' and private.is_api_caller() then
      new.owner_user_id := auth.uid();                                        -- Req 5.3
    end if;
    if new.type = 'business' then
      new.owner_user_id := null;
    end if;
  else
    if new.type <> old.type or new.owner_user_id is distinct from old.owner_user_id then
      raise exception using errcode = 'PT422', message = 'profile.immutable';
    end if;
  end if;

  return new;
end;
$$;
revoke execute on function private.profiles_before_write() from public;
revoke execute on function private.profiles_before_write() from anon, authenticated;

create trigger profiles_before_write
  before insert or update on public.profiles
  for each row execute function private.profiles_before_write();

-- The login that creates a business becomes its owner (Req 6.7).
create or replace function private.profiles_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'business' and auth.uid() is not null then
    insert into public.profile_managers (profile_id, user_id, role)
    values (new.id, auth.uid(), 'owner');
  end if;
  return null;
end;
$$;
revoke execute on function private.profiles_after_insert() from public;
revoke execute on function private.profiles_after_insert() from anon, authenticated;

create trigger profiles_after_insert
  after insert on public.profiles
  for each row execute function private.profiles_after_insert();

-- Every business has at least one owner when the transaction commits (Req 7.3).
create or replace function private.profiles_business_has_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'business'
     and exists (select 1 from public.profiles p where p.id = new.id)
     and not exists (
       select 1 from public.profile_managers m where m.profile_id = new.id and m.role = 'owner'
     ) then
    raise exception using errcode = 'PT422', message = 'profile.business_needs_owner';
  end if;
  return null;
end;
$$;
revoke execute on function private.profiles_business_has_owner() from public;
revoke execute on function private.profiles_business_has_owner() from anon, authenticated;

create constraint trigger profiles_business_has_owner
  after insert on public.profiles
  deferrable initially deferred
  for each row execute function private.profiles_business_has_owner();

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Profile manager triggers
-- ---------------------------------------------------------------------------------------------

-- Manager rows exist only for businesses; a person is controlled through owner_user_id.
create or replace function private.profile_managers_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles p where p.id = new.profile_id and p.type = 'business'
  ) then
    raise exception using errcode = 'PT422', message = 'manager.not_a_business';
  end if;
  return new;
end;
$$;
revoke execute on function private.profile_managers_guard() from public;
revoke execute on function private.profile_managers_guard() from anon, authenticated;

create trigger profile_managers_guard
  before insert or update on public.profile_managers
  for each row execute function private.profile_managers_guard();

-- Last owner protection (Req 7.13). When the last owner row goes because its login was deleted,
-- the business is deleted instead (Req 5.7).
create or replace function private.profile_managers_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles p where p.id = old.profile_id)
     and not exists (
       select 1 from public.profile_managers m where m.profile_id = old.profile_id and m.role = 'owner'
     ) then
    if tg_op = 'DELETE' and not exists (select 1 from auth.users u where u.id = old.user_id) then
      delete from public.profiles p where p.id = old.profile_id;
    else
      raise exception using errcode = 'PT422', message = 'profile.last_owner';
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function private.profile_managers_after_change() from public;
revoke execute on function private.profile_managers_after_change() from anon, authenticated;

create trigger profile_managers_after_change
  after update or delete on public.profile_managers
  for each row execute function private.profile_managers_after_change();

create trigger profile_managers_set_updated_at
  before update on public.profile_managers
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Manager RPCs (Req 7.9, 7.10). The only write path to profile_managers for the API.
-- ---------------------------------------------------------------------------------------------

create or replace function public.add_profile_manager(
  p_business uuid,
  p_person_profile uuid,
  p_role public.manager_role
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if not public.is_profile_owner(p_business) then
    raise exception using errcode = 'PT403', message = 'manager.owner_only';
  end if;
  select p.owner_user_id into v_user
  from public.profiles p
  where p.id = p_person_profile and p.type = 'person';
  if v_user is null then
    raise exception using errcode = 'PT404', message = 'manager.person_not_found';
  end if;
  insert into public.profile_managers (profile_id, user_id, role)
  values (p_business, v_user, p_role)
  on conflict (profile_id, user_id) do update set role = excluded.role;
end;
$$;
revoke execute on function public.add_profile_manager(uuid, uuid, public.manager_role) from public;
revoke execute on function public.add_profile_manager(uuid, uuid, public.manager_role) from anon;
grant execute on function public.add_profile_manager(uuid, uuid, public.manager_role) to authenticated;

create or replace function public.remove_profile_manager(p_business uuid, p_person_profile uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if not public.is_profile_owner(p_business) then
    raise exception using errcode = 'PT403', message = 'manager.owner_only';
  end if;
  select p.owner_user_id into v_user
  from public.profiles p
  where p.id = p_person_profile and p.type = 'person';
  if v_user is null then
    raise exception using errcode = 'PT404', message = 'manager.person_not_found';
  end if;
  -- profile_managers_after_change rejects removing the last owner.
  delete from public.profile_managers m
  where m.profile_id = p_business and m.user_id = v_user;
end;
$$;
revoke execute on function public.remove_profile_manager(uuid, uuid) from public;
revoke execute on function public.remove_profile_manager(uuid, uuid) from anon;
grant execute on function public.remove_profile_manager(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants
-- ---------------------------------------------------------------------------------------------

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated;

-- Public fields only (Req 4.15). owner_user_id, preferred_language, mode_2006, tags_text and
-- search_tsv are not granted (Req 4.16, 22.7); owners read them through my_profiles().
grant select (
  id, type, handle, display_name, bio, avatar_path, cover_path, city, country,
  dot_colour, theme, what_i_do, created_at, updated_at
) on table public.profiles to anon, authenticated;
grant insert (
  type, handle, display_name, bio, avatar_path, cover_path, city, country,
  preferred_language, dot_colour, theme, mode_2006, what_i_do
) on table public.profiles to authenticated;
grant update (
  handle, display_name, bio, avatar_path, cover_path, city, country,
  preferred_language, dot_colour, theme, mode_2006, what_i_do
) on table public.profiles to authenticated;
grant delete on table public.profiles to authenticated;

create policy profiles_anon_select on public.profiles
  for select to anon using (true);
create policy profiles_authenticated_select on public.profiles
  for select to authenticated using (true);
-- The insert trigger sets owner_user_id for persons, so the unique index rejects a second person
-- profile (Req 5.4). A business may be created only by a login that has a person profile (Req 6.7).
create policy profiles_authenticated_insert on public.profiles
  for insert to authenticated
  with check (
    auth.uid() is not null
    and (
      type = 'person'
      or (type = 'business' and exists (select 1 from public.my_profiles() m where m.role = 'person'))
    )
  );
create policy profiles_authenticated_update on public.profiles
  for update to authenticated
  using (public.acts_as(id))
  with check (public.acts_as(id));
-- A manager cannot delete a business (Req 7.11).
create policy profiles_authenticated_delete on public.profiles
  for delete to authenticated
  using (public.acts_as(id) and (type = 'person' or public.is_profile_owner(id)));

alter table public.profile_managers enable row level security;
revoke all on table public.profile_managers from anon, authenticated;
-- Writes only through add_profile_manager and remove_profile_manager.
grant select on table public.profile_managers to authenticated;

create policy profile_managers_authenticated_select on public.profile_managers
  for select to authenticated using (public.acts_as(profile_id));
;
