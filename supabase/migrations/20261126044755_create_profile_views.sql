-- Migration 17: profile views, the record_profile_view RPC and the profile_viewed notification.
-- Spec 00 Req 15.7, 15.10, 16.1 to 16.5, 22.1 to 22.5; design "profile_views", "Signals",
-- "Row Level Security policies", "Grants and revokes strategy".
-- One row per viewing profile, viewed profile and Nairobi day. Writes only through
-- record_profile_view; anon records nothing (Req 16.2).
-- ---------------------------------------------------------------------------------------------
create table public.profile_views (
  id uuid primary key default gen_random_uuid(),
  viewed_profile_id uuid not null references public.profiles (id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles (id) on delete cascade,
  viewed_on date not null,
  viewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint profile_views_not_self check (viewed_profile_id <> viewer_profile_id),
  -- One row per viewer, page and Nairobi day (Req 16.4); also the leading index of the viewed foreign key.
  constraint profile_views_viewed_viewer_day_key unique (viewed_profile_id, viewer_profile_id, viewed_on)
);
create index profile_views_viewer_profile_id_idx on public.profile_views (viewer_profile_id);
create index profile_views_viewed_on_idx on public.profile_views (viewed_profile_id, viewed_on desc);
-- ---------------------------------------------------------------------------------------------
-- profile_viewed notification, only for a new row (Req 15.7, 16.4). reference_id is the view row id.
-- data holds only what private.notify adds (actor handle, display name, type) (Req 15.10).
-- ---------------------------------------------------------------------------------------------
create or replace function private.profile_views_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify(new.viewed_profile_id, 'profile_viewed', new.viewer_profile_id, new.id, null);
  return null;
end;
$$;
revoke execute on function private.profile_views_after_insert() from public;
revoke execute on function private.profile_views_after_insert() from anon, authenticated;
create trigger profile_views_after_insert
  after insert on public.profile_views
  for each row execute function private.profile_views_after_insert();
-- ---------------------------------------------------------------------------------------------
-- record_profile_view (Req 16.2 to 16.4): the viewing profile views a page, once per Nairobi day.
-- on conflict do nothing fires no insert trigger, so a repeat view adds no row and no notification.
-- ---------------------------------------------------------------------------------------------
create or replace function public.record_profile_view(p_viewer uuid, p_viewed uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not public.acts_as(p_viewer) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';             -- 16.2
  end if;
  if p_viewer = p_viewed or private.share_controller(p_viewer, p_viewed) then
    raise exception using errcode = 'PT422', message = 'profile_view.own_page';          -- 16.3
  end if;
  insert into public.profile_views (viewed_profile_id, viewer_profile_id, viewed_on)
  values (p_viewed, p_viewer, private.nairobi_today())
  on conflict (viewed_profile_id, viewer_profile_id, viewed_on) do nothing;
end;
$$;
revoke execute on function public.record_profile_view(uuid, uuid) from public;
revoke execute on function public.record_profile_view(uuid, uuid) from anon, authenticated;
grant execute on function public.record_profile_view(uuid, uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 16.5, 22.1 to 22.3, 22.5).
-- No anon policy or grant; no write grant for anyone (writes go through record_profile_view).
-- ---------------------------------------------------------------------------------------------
alter table public.profile_views enable row level security;
revoke all on table public.profile_views from anon, authenticated;
grant select on table public.profile_views to authenticated;
create policy profile_views_authenticated_select on public.profile_views
  for select to authenticated
  using (public.acts_as(viewed_profile_id) or public.acts_as(viewer_profile_id));
;
