-- Migration 4: lookup tables for languages, reserved handles and AI settings.
-- Spec 00 Req 3.5, 3.8, 3.9, 4.5, 4.6, 4.7, 17.2, 17.6, 22.1, 22.2, 22.5; design D-4.
-- New rows are added by later migrations without any table change (Req 4.6, 4.7).

-- Languages a profile may prefer. Readable by everyone to show language choices.
create table public.languages (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  created_at timestamptz not null default now(),
  constraint languages_code_key unique (code),
  constraint languages_code_format check (code ~ '^[a-z]{2,3}(-[A-Z]{2})?$')
);

alter table public.languages enable row level security;

revoke all on table public.languages from anon, authenticated;
grant select on table public.languages to anon, authenticated;

create policy languages_anon_select on public.languages
  for select to anon using (true);
create policy languages_authenticated_select on public.languages
  for select to authenticated using (true);

insert into public.languages (code, name) values
  ('en', 'English'),
  ('sw', 'Kiswahili');

-- Handles nobody may claim (Req 4.5). No grants and no policies: RLS denies all API access.
create table public.reserved_handles (
  id uuid primary key default gen_random_uuid(),
  word text not null,
  created_at timestamptz not null default now(),
  constraint reserved_handles_word_key unique (word)
);

alter table public.reserved_handles enable row level security;

revoke all on table public.reserved_handles from anon, authenticated;

insert into public.reserved_handles (word) values
  ('api'), ('app'), ('admin'), ('auth'), ('login'), ('logout'), ('signup'),
  ('settings'), ('search'), ('circles'), ('notifications'), ('edit'), ('help'),
  ('about'), ('terms'), ('privacy'), ('pavio'), ('www'), ('static'), ('_next'), ('demo');

-- AI limits as a single row (Req 17.2). Unreadable and unwritable by the API roles (Req 17.6).
create table public.app_settings (
  id uuid primary key default gen_random_uuid(),
  singleton boolean not null default true,
  monthly_spend_cap_usd numeric(10,2) not null default 10,
  ai_daily_call_limit integer not null default 20,
  max_cost_per_call_usd numeric(10,4) not null default 0.05,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_settings_singleton_key unique (singleton),
  constraint app_settings_singleton_true check (singleton),
  constraint app_settings_monthly_spend_cap_positive check (monthly_spend_cap_usd > 0),
  constraint app_settings_daily_call_limit_positive check (ai_daily_call_limit > 0),
  constraint app_settings_max_cost_per_call_positive check (max_cost_per_call_usd > 0)
);

alter table public.app_settings enable row level security;

revoke all on table public.app_settings from anon, authenticated;

create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function private.set_updated_at();

insert into public.app_settings default values;
;
