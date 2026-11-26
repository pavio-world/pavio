-- Migration 19: weekly search summary notification and its pg_cron schedule.
-- Spec 00 Req 15.8, 15.9, 15.10, 16.10; design "Signals" (send_weekly_search_summaries),
-- "notifications" (notifications_weekly_uq), "Grants and revokes strategy".
-- Reads public.search_appearances (migration 18) and writes public.notifications (migration 7).

-- ---------------------------------------------------------------------------------------------
-- One weekly summary per profile and week. A re-run in the same week hits this index and adds
-- nothing (Req 15.9). The week is identified by the Nairobi date of its first day.
-- ---------------------------------------------------------------------------------------------
create unique index notifications_weekly_uq
  on public.notifications (recipient_profile_id, (data ->> 'week_start'))
  where type = 'weekly_search_appearances';

-- ---------------------------------------------------------------------------------------------
-- The summary. Covers the seven Nairobi days before today: run on a Monday, that is the Monday
-- to Sunday that just ended. One notification per profile with a positive total; profiles with
-- no appearances get none. data holds only the count and the two dates (Req 15.10).
-- Returns the number of notifications created.
-- ---------------------------------------------------------------------------------------------
create or replace function private.send_weekly_search_summaries()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_week_end date := private.nairobi_today() - 1;
  v_week_start date := private.nairobi_today() - 7;
  v_created integer;
begin
  with inserted as (
    insert into public.notifications (recipient_profile_id, type, data)
    select sa.profile_id,
           'weekly_search_appearances'::public.notification_type,
           pg_catalog.jsonb_build_object(
             'count', pg_catalog.sum(sa.count),
             'week_start', v_week_start,
             'week_end', v_week_end)
    from public.search_appearances sa
    where sa.appeared_on between v_week_start and v_week_end
    group by sa.profile_id
    having pg_catalog.sum(sa.count) > 0
    on conflict do nothing
    returning 1
  )
  select pg_catalog.count(*)::integer into v_created from inserted;
  return v_created;
end;
$$;
-- Only the job (running as the table owner) calls this; never the API roles.
revoke execute on function private.send_weekly_search_summaries() from public;
revoke execute on function private.send_weekly_search_summaries() from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Schedule: Monday 05:00 UTC, which is 08:00 in Nairobi. Scheduling by name again replaces the
-- job, so re-applying this migration cannot create a second one.
-- ---------------------------------------------------------------------------------------------
select cron.schedule(
  'pavio-weekly-search-summary',
  '0 5 * * 1',
  $job$select private.send_weekly_search_summaries()$job$
);
