-- Migration 21: the Last.fm username linked to a profile.
-- Spec 00 Req 18.1 to 18.3, 22.1 to 22.5; design "lastfm_links".
-- Private to the people who act as the profile: no anon grant, no public read.
-- ---------------------------------------------------------------------------------------------
create table public.lastfm_links (
  id uuid primary key default gen_random_uuid(),
  -- At most one link per profile (Req 18.1); the unique key is also the foreign key index.
  profile_id uuid not null references public.profiles (id) on delete cascade,
  username text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lastfm_links_profile_id_key unique (profile_id),
  constraint lastfm_links_username_format check (username ~ '^[A-Za-z][A-Za-z0-9_-]{1,14}$')
);

create trigger lastfm_links_set_updated_at
  before update on public.lastfm_links
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants: read and write only with acts_as on the profile (Req 18.2, 18.3).
-- ---------------------------------------------------------------------------------------------
alter table public.lastfm_links enable row level security;
revoke all on table public.lastfm_links from anon, authenticated;
grant select, insert, update, delete on table public.lastfm_links to authenticated;

create policy lastfm_links_authenticated_select on public.lastfm_links
  for select to authenticated
  using (public.acts_as(profile_id));

create policy lastfm_links_authenticated_insert on public.lastfm_links
  for insert to authenticated
  with check (public.acts_as(profile_id));

create policy lastfm_links_authenticated_update on public.lastfm_links
  for update to authenticated
  using (public.acts_as(profile_id))
  with check (public.acts_as(profile_id));

create policy lastfm_links_authenticated_delete on public.lastfm_links
  for delete to authenticated
  using (public.acts_as(profile_id));
;
