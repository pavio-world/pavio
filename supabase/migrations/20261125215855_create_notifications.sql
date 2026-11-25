-- Migration 7: notifications, the notify helper, RLS and grants.
-- Spec 00 Req 15.1, 15.2, 15.10 to 15.13, 22.1 to 22.5; design "notifications", "Signals",
-- "Row Level Security policies", "Grants and revokes strategy".
-- The triggers that call private.notify come with their tables (migrations 8, 13 and 17).
-- notifications_weekly_uq is added by migration 19 with the weekly summary.
-- ---------------------------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles (id) on delete cascade,
  type public.notification_type not null,
  -- A deleted actor's name and handle must not linger in other people's notifications.
  actor_profile_id uuid references public.profiles (id) on delete cascade,
  -- No foreign key: may point at a relationship or a vouch.
  reference_id uuid,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notifications_data_object check (jsonb_typeof(data) = 'object')
);
-- The recipient's list, newest first; also the leading index for the recipient foreign key.
create index notifications_recipient_created_idx on public.notifications
  (recipient_profile_id, created_at desc);
create index notifications_actor_profile_id_idx on public.notifications (actor_profile_id);
-- ---------------------------------------------------------------------------------------------
-- Notify helper: the only insert path, called by triggers and definer functions (Req 15.11).
-- data only ever holds ids, handles, display names, profile type, counts and dates (Req 15.10).
-- ---------------------------------------------------------------------------------------------
create or replace function private.notify(
  p_recipient uuid,
  p_type public.notification_type,
  p_actor uuid,
  p_ref uuid,
  p_extra jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (recipient_profile_id, type, actor_profile_id, reference_id, data)
  select p_recipient, p_type, p_actor, p_ref,
         coalesce(p_extra, '{}'::jsonb) || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
           'actor_handle', a.handle,
           'actor_display_name', a.display_name,
           'actor_type', a.type))
  from (select 1) as x
  left join public.profiles a on a.id = p_actor;
end;
$$;
revoke execute on function private.notify(uuid, public.notification_type, uuid, uuid, jsonb) from public;
revoke execute on function private.notify(uuid, public.notification_type, uuid, uuid, jsonb) from anon, authenticated;
-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants
-- ---------------------------------------------------------------------------------------------
alter table public.notifications enable row level security;
revoke all on table public.notifications from anon, authenticated;
-- Recipients read their notifications and may only set read_at (Req 15.12, 15.13).
-- No insert or delete grant (Req 15.11).
grant select on table public.notifications to authenticated;
grant update (read_at) on table public.notifications to authenticated;
create policy notifications_authenticated_select on public.notifications
  for select to authenticated
  using (public.acts_as(recipient_profile_id));
create policy notifications_authenticated_update on public.notifications
  for update to authenticated
  using (public.acts_as(recipient_profile_id))
  with check (public.acts_as(recipient_profile_id));
;
