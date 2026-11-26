-- Migration 14: story views. One row per story and viewing profile, recorded only for stories the
-- viewer may see, readable by the viewer and by the story owner.
-- Spec 00 Req 12.1 to 12.6, 22.1 to 22.3, 22.5; design "story_views", "Row Level Security
-- policies", "Grants and revokes strategy", "Error Handling".
-- The client records a view with an upsert that ignores duplicates (on conflict do nothing), which
-- needs the insert grant and the insert policy only.
-- ---------------------------------------------------------------------------------------------
create table public.story_views (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.content_items (id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- One row per story and viewer (Req 12.2); also the leading index of the story foreign key.
  constraint story_views_story_viewer_key unique (story_id, viewer_profile_id)
);
create index story_views_viewer_profile_id_idx on public.story_views (viewer_profile_id);
-- ---------------------------------------------------------------------------------------------
-- story_views_guard (Req 12.4): a view may point only at a story.
-- Security invoker on purpose: an API caller reads content_items through its own RLS, so an item it
-- cannot see looks missing and is left to the insert policy (can_view) and the foreign key. The
-- guard therefore never tells a caller that an invisible item exists or what type it is
-- (Req 20.12). Trusted callers (seed, tests) see every item and are always checked.
-- ---------------------------------------------------------------------------------------------
create or replace function private.story_views_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (select 1 from public.content_items ci
             where ci.id = new.story_id and ci.content_type <> 'story') then
    raise exception using errcode = 'PT422', message = 'story_view.not_a_story';
  end if;
  return new;
end;
$$;
revoke execute on function private.story_views_guard() from public;
revoke execute on function private.story_views_guard() from anon, authenticated;
create trigger story_views_guard
  before insert or update on public.story_views
  for each row execute function private.story_views_guard();
-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 12.3, 12.5, 12.6, 22.1 to 22.3, 22.5).
-- No anon policy or grant: signed out visitors never read or write story views.
-- ---------------------------------------------------------------------------------------------
alter table public.story_views enable row level security;
revoke all on table public.story_views from anon, authenticated;
grant select on table public.story_views to authenticated;
grant insert (story_id, viewer_profile_id) on table public.story_views to authenticated;
create policy story_views_authenticated_select on public.story_views
  for select to authenticated
  using (
    public.acts_as(viewer_profile_id)
    or exists (select 1 from public.content_items ci
               where ci.id = story_id and public.acts_as(ci.owner_profile_id))
  );
create policy story_views_authenticated_insert on public.story_views
  for insert to authenticated
  with check (public.acts_as(viewer_profile_id) and public.can_view(story_id, viewer_profile_id));
;
