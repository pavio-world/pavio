-- Migration 20: AI usage per login and Nairobi day, the spend limit helper, ai_can_call and ai_record_call.
-- Spec 00 Req 17.1, 17.3 to 17.5, 17.7 to 17.9, 22.1 to 22.5, 22.11; design "AI usage", D-4, DR-2.
-- Rows are written only by ai_record_call, which only service_role can execute (DR-2).
-- ---------------------------------------------------------------------------------------------
create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Spend history survives profile deletion so the monthly cap stays correct (Req 17.1).
  acting_profile_id uuid references public.profiles (id) on delete set null,
  usage_day date not null,
  request_count integer not null default 0,
  cost_usd numeric(10,4) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_usage_request_count_nonnegative check (request_count >= 0),
  constraint ai_usage_cost_usd_nonnegative check (cost_usd >= 0),
  -- Also the leading index of the user_id foreign key.
  constraint ai_usage_user_profile_day_key unique (user_id, acting_profile_id, usage_day)
);
create index ai_usage_usage_day_idx on public.ai_usage (usage_day);
create index ai_usage_acting_profile_id_idx on public.ai_usage (acting_profile_id);

create trigger ai_usage_set_updated_at
  before update on public.ai_usage
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants: a login reads only its own rows; nobody writes through the API
-- (Req 17.5, 22.1 to 22.5). No anon policy or grant.
-- ---------------------------------------------------------------------------------------------
alter table public.ai_usage enable row level security;
revoke all on table public.ai_usage from anon, authenticated;
grant select on table public.ai_usage to authenticated;

create policy ai_usage_authenticated_select on public.ai_usage
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------
-- private.ai_under_limits: true while the login is under the daily call limit and the whole
-- month's cost is under the global spend cap (Req 17.2, 17.3). Null login is never under.
-- ---------------------------------------------------------------------------------------------
create or replace function private.ai_under_limits(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user is not null
    and coalesce((select sum(u.request_count) from public.ai_usage u
                  where u.user_id = p_user and u.usage_day = private.nairobi_today()), 0)
        < (select s.ai_daily_call_limit from public.app_settings s)
    and coalesce((select sum(u.cost_usd) from public.ai_usage u
                  where u.usage_day >= private.nairobi_month_start()), 0)
        < (select s.monthly_spend_cap_usd from public.app_settings s);
$$;
revoke execute on function private.ai_under_limits(uuid) from public;
revoke execute on function private.ai_under_limits(uuid) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- public.ai_can_call: the signed in login may make another AI call (Req 17.3).
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_can_call()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.ai_under_limits(auth.uid());
$$;
revoke execute on function public.ai_can_call() from public;
revoke execute on function public.ai_can_call() from anon, authenticated;
grant execute on function public.ai_can_call() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- public.ai_record_call: records one call and its cost for a login and the profile it acted as
-- (Req 17.4). Executable by service_role only (Req 17.7, 17.8, 22.11; DR-2).
--   PT403 acting.not_allowed  the login does not own or manage the acting profile (Req 17.9)
--   PT422 ai.bad_cost         a null, negative or too large cost (D-4)
--   PT429 ai.limit_reached    the daily limit or the monthly cap is already reached
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_record_call(p_user_id uuid, p_acting_profile uuid, p_cost_usd numeric)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.controls(p_user_id, p_acting_profile) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';
  end if;
  if p_cost_usd is null
     or p_cost_usd < 0
     or p_cost_usd > (select s.max_cost_per_call_usd from public.app_settings s) then
    raise exception using errcode = 'PT422', message = 'ai.bad_cost';
  end if;
  if not private.ai_under_limits(p_user_id) then
    raise exception using errcode = 'PT429', message = 'ai.limit_reached';
  end if;
  insert into public.ai_usage (user_id, acting_profile_id, usage_day, request_count, cost_usd)
  values (p_user_id, p_acting_profile, private.nairobi_today(), 1, p_cost_usd)
  on conflict (user_id, acting_profile_id, usage_day)
  do update set request_count = public.ai_usage.request_count + 1,
                cost_usd = public.ai_usage.cost_usd + excluded.cost_usd;
end;
$$;
revoke execute on function public.ai_record_call(uuid, uuid, numeric) from public;
revoke execute on function public.ai_record_call(uuid, uuid, numeric) from anon, authenticated;
grant execute on function public.ai_record_call(uuid, uuid, numeric) to service_role;
;
