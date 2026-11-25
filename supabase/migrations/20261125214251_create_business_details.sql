-- Migration 6: business details, their validator, guard, RLS and grants.
-- Spec 00 Req 6.1 to 6.6, 22.1 to 22.5; design "business_details", "Helper functions",
-- "Profile and business guards", "Grants and revokes strategy".
-- ---------------------------------------------------------------------------------------------
-- Validator
-- ---------------------------------------------------------------------------------------------
-- Opening hours: an object whose keys are days mon..sun; each value is null or exactly
-- {"open": "HH:MM", "close": "HH:MM"} in 24 hour time (Req 6.4). The case expressions keep the
-- set returning json functions away from non object input.
create or replace function private.opening_hours_valid(p jsonb)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p is null or pg_catalog.jsonb_typeof(p) <> 'object' then false
    else not exists (
      select 1
      from pg_catalog.jsonb_each(p) as e(day, hours)
      where e.day not in ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
         or case
              when pg_catalog.jsonb_typeof(e.hours) = 'null' then false
              when pg_catalog.jsonb_typeof(e.hours) <> 'object' then true
              else not (
                (select pg_catalog.array_agg(k order by k) from pg_catalog.jsonb_object_keys(e.hours) as k)
                  = array['close', 'open']
                and pg_catalog.jsonb_typeof(e.hours -> 'open') = 'string'
                and pg_catalog.jsonb_typeof(e.hours -> 'close') = 'string'
                and (e.hours ->> 'open') ~ '^([01]\d|2[0-3]):[0-5]\d$'
                and (e.hours ->> 'close') ~ '^([01]\d|2[0-3]):[0-5]\d$'
              )
            end
    )
  end;
$$;
revoke execute on function private.opening_hours_valid(jsonb) from public;
-- Pure validator: the check constraint runs with the writer's privileges.
grant execute on function private.opening_hours_valid(jsonb) to anon, authenticated;
-- ---------------------------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------------------------
create table public.business_details (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  category text,
  phone text,
  website text,
  opening_hours jsonb not null default '{}'::jsonb,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One row per business (Req 6.2); the unique index also serves the foreign key.
  constraint business_details_profile_id_key unique (profile_id),
  constraint business_details_category_length check (category is null or char_length(category) <= 80),
  constraint business_details_phone_format check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  constraint business_details_website_format check (website is null or website ~ '^https?://'),
  constraint business_details_opening_hours_valid check (private.opening_hours_valid(opening_hours)),
  constraint business_details_address_length check (address is null or char_length(address) <= 300)
);
-- Directory search on category (Req 24).
create index business_details_category_trgm_idx on public.business_details
  using gin (lower(coalesce(category, '')) extensions.gin_trgm_ops);
-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------
-- Business details belong only to business profiles (Req 6.3). A missing profile is left to the
-- foreign key.
create or replace function private.business_details_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select p.type from public.profiles p where p.id = new.profile_id) <> 'business' then
    raise exception using errcode = 'PT422', message = 'business.not_a_business';
  end if;
  return new;
end;
$$;
revoke execute on function private.business_details_guard() from public;
revoke execute on function private.business_details_guard() from anon, authenticated;
create trigger business_details_guard
  before insert or update on public.business_details
  for each row execute function private.business_details_guard();
create trigger business_details_set_updated_at
  before update on public.business_details
  for each row execute function private.set_updated_at();
-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants
-- ---------------------------------------------------------------------------------------------
alter table public.business_details enable row level security;
revoke all on table public.business_details from anon, authenticated;
-- Every field is public data (Req 6.6); writes need acts_as on the business.
grant select on table public.business_details to anon, authenticated;
grant insert, update, delete on table public.business_details to authenticated;
create policy business_details_anon_select on public.business_details
  for select to anon using (true);
create policy business_details_authenticated_select on public.business_details
  for select to authenticated using (true);
create policy business_details_authenticated_insert on public.business_details
  for insert to authenticated
  with check (public.acts_as(profile_id));
create policy business_details_authenticated_update on public.business_details
  for update to authenticated
  using (public.acts_as(profile_id))
  with check (public.acts_as(profile_id));
create policy business_details_authenticated_delete on public.business_details
  for delete to authenticated
  using (public.acts_as(profile_id));
;
