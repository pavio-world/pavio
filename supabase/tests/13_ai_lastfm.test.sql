-- AI usage and the Last.fm link (Spec 00, Req 17, 18, 22.11, 25.1, 25.2, 25.13; D-4, DR-1, DR-2).
-- The AI part comes first (task 25); the Last.fm section (task 26) follows it.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(180);

-- =============================================================================================
-- AI usage (task 25; Req 17.1 to 17.9, 22.11, 25.13)
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims.
-- Ann owns the person ai_ann and manages the business ai_shop. Ben, Cat, Dan, Eve and Fay each
-- own one person. The default limits (20 calls a day, 10 US dollars a month, 0.05 a call) apply
-- until a section changes app_settings, and the whole file rolls back.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('13a00000-0000-4000-8000-000000000001', 'ann.ai@example.invalid'),
  ('13a00000-0000-4000-8000-000000000002', 'ben.ai@example.invalid'),
  ('13a00000-0000-4000-8000-000000000003', 'cat.ai@example.invalid'),
  ('13a00000-0000-4000-8000-000000000004', 'dan.ai@example.invalid'),
  ('13a00000-0000-4000-8000-000000000005', 'eve.ai@example.invalid'),
  ('13a00000-0000-4000-8000-000000000006', 'fay.ai@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('13b00000-0000-4000-8000-000000000001', 'person', '13a00000-0000-4000-8000-000000000001', 'ai_ann', 'Ann'),
  ('13b00000-0000-4000-8000-000000000002', 'person', '13a00000-0000-4000-8000-000000000002', 'ai_ben', 'Ben'),
  ('13b00000-0000-4000-8000-000000000003', 'person', '13a00000-0000-4000-8000-000000000003', 'ai_cat', 'Cat'),
  ('13b00000-0000-4000-8000-000000000004', 'person', '13a00000-0000-4000-8000-000000000004', 'ai_dan', 'Dan'),
  ('13b00000-0000-4000-8000-000000000005', 'person', '13a00000-0000-4000-8000-000000000005', 'ai_eve', 'Eve'),
  ('13b00000-0000-4000-8000-000000000006', 'person', '13a00000-0000-4000-8000-000000000006', 'ai_fay', 'Fay');
insert into public.profiles (id, type, handle, display_name) values
  ('13b00000-0000-4000-8000-000000000007', 'business', 'ai_shop', 'AI Shop');
insert into public.profile_managers (profile_id, user_id, role) values
  ('13b00000-0000-4000-8000-000000000007', '13a00000-0000-4000-8000-000000000001', 'owner');

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, foreign keys, checks, indexes, trigger, RLS, policies and grants
-- (Req 17.1, 17.5, 22.1 to 22.5).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'ai_usage', 'ai_usage exists');
select columns_are('public', 'ai_usage', array[
  'id', 'user_id', 'acting_profile_id', 'usage_day', 'request_count', 'cost_usd', 'created_at', 'updated_at'
], 'ai_usage has exactly its eight columns');
select col_type_is('public', 'ai_usage', 'cost_usd', 'numeric(10,4)', 'cost_usd is numeric(10,4)');
select col_type_is('public', 'ai_usage', 'usage_day', 'date', 'usage_day is a date');
select col_not_null('public', 'ai_usage', 'user_id', 'a row always belongs to a login');
select col_is_null('public', 'ai_usage', 'acting_profile_id', 'the acting profile may become null');
select is((select confrelid::regclass::text || ':' || confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.ai_usage'::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.ai_usage'::regclass and attname = 'user_id')]::smallint[]),
  'auth.users:c', 'user_id references auth.users and cascades on delete');
select is((select confrelid::regclass::text || ':' || confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.ai_usage'::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.ai_usage'::regclass and attname = 'acting_profile_id')]::smallint[]),
  'profiles:n', 'acting_profile_id references profiles and is set null on delete');
select col_is_unique('public', 'ai_usage', array['user_id', 'acting_profile_id', 'usage_day'],
  'one row per login, acting profile and day');
select has_index('public', 'ai_usage', 'ai_usage_usage_day_idx', 'usage_day', 'ai_usage has the usage_day index');
select has_index('public', 'ai_usage', 'ai_usage_acting_profile_id_idx', 'acting_profile_id',
  'ai_usage has the acting profile index');
select has_trigger('public', 'ai_usage', 'ai_usage_set_updated_at', 'ai_usage keeps updated_at current');
select throws_ok($$ insert into public.ai_usage (user_id, usage_day, request_count)
                    values ('13a00000-0000-4000-8000-000000000001', current_date, -1) $$,
  '23514', null, 'request_count cannot be negative');
select throws_ok($$ insert into public.ai_usage (user_id, usage_day, cost_usd)
                    values ('13a00000-0000-4000-8000-000000000001', current_date, -0.01) $$,
  '23514', null, 'cost_usd cannot be negative');
select ok((select relrowsecurity from pg_class where oid = 'public.ai_usage'::regclass),
  'RLS is enabled on ai_usage');
select policies_are('public', 'ai_usage', array['ai_usage_authenticated_select'],
  'ai_usage has exactly its one policy');
select table_privs_are('public', 'ai_usage', 'anon', array[]::text[], 'anon has no privilege on ai_usage');
select table_privs_are('public', 'ai_usage', 'authenticated', array['SELECT'],
  'authenticated holds only select on ai_usage');

-- Functions: definer with an empty search_path (Req 3.6, 22.3).
select is_definer(s, f, a, s || '.' || f || ' is security definer')
from (values ('private', 'ai_under_limits', array['uuid']),
             ('public', 'ai_can_call', array[]::text[]),
             ('public', 'ai_record_call', array['uuid', 'uuid', 'numeric'])) as t(s, f, a);
select ok(exists (select 1 from pg_catalog.unnest((select proconfig from pg_catalog.pg_proc where oid = f::regprocedure)) c
                  where c = 'search_path=""'),
  f || ' sets an empty search_path')
from unnest(array['private.ai_under_limits(uuid)', 'public.ai_can_call()',
                  'public.ai_record_call(uuid, uuid, numeric)']) as f;

-- Execute grants (Req 17.3, 17.7, 22.11, 25.13; DR-2).
select ok(not has_function_privilege(r, 'public.ai_record_call(uuid, uuid, numeric)', 'execute'),
  r || ' cannot execute ai_record_call')
from unnest(array['public', 'anon', 'authenticated']) as r;
select ok(has_function_privilege('service_role', 'public.ai_record_call(uuid, uuid, numeric)', 'execute'),
  'service_role can execute ai_record_call');
select ok(not has_function_privilege(r, 'public.ai_can_call()', 'execute'), r || ' cannot execute ai_can_call')
from unnest(array['public', 'anon']) as r;
select ok(has_function_privilege('authenticated', 'public.ai_can_call()', 'execute'),
  'authenticated can execute ai_can_call');
select ok(not has_function_privilege(r, 'private.ai_under_limits(uuid)', 'execute'),
  r || ' cannot execute private.ai_under_limits')
from unnest(array['public', 'anon', 'authenticated']) as r;

-- ---------------------------------------------------------------------------------------------
-- As service_role, the Admin_Client role (DR-2): record calls and meet every rejection.
-- Claims carry only the role; service_role is a trusted caller, so is_api_caller is false.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
select ok(not private.is_api_caller(), 'is_api_caller is false for the service_role claims');
set local role service_role;
select is(current_user::text, 'service_role', 'running as service_role');

select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                 '13b00000-0000-4000-8000-000000000001', 0.01) $$,
  'service_role records a call for Ann as ai_ann');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                 '13b00000-0000-4000-8000-000000000001', 0.02) $$,
  'a second call the same day as the same profile is accepted');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                 '13b00000-0000-4000-8000-000000000007', 0.05) $$,
  'Ann records a call as the business she manages, at exactly max_cost_per_call_usd');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000002',
                                                 '13b00000-0000-4000-8000-000000000002', 0) $$,
  'a call with cost zero is accepted');

-- The login must control the acting profile (Req 17.9).
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000002', 0.01) $$,
  'PT403', 'acting.not_allowed', 'Ann cannot record a call as Ben''s profile');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000002',
                                                  '13b00000-0000-4000-8000-000000000007', 0.01) $$,
  'PT403', 'acting.not_allowed', 'Ben cannot record a call as Ann''s business');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001', null, 0.01) $$,
  'PT403', 'acting.not_allowed', 'a null acting profile is rejected');
select throws_ok($$ select public.ai_record_call(null, '13b00000-0000-4000-8000-000000000001', 0.01) $$,
  'PT403', 'acting.not_allowed', 'a null login is rejected');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-0000000000ff', 0.01) $$,
  'PT403', 'acting.not_allowed', 'an unknown acting profile is rejected');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000003',
                                                  '13b00000-0000-4000-8000-000000000001', 0.99) $$,
  'PT403', 'acting.not_allowed', 'the acting check comes before the cost check');

-- The cost must be between zero and max_cost_per_call_usd (D-4).
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', 0.06) $$,
  'PT422', 'ai.bad_cost', 'a cost above max_cost_per_call_usd is rejected');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', -0.01) $$,
  'PT422', 'ai.bad_cost', 'a negative cost is rejected');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', null) $$,
  'PT422', 'ai.bad_cost', 'a null cost is rejected');

-- What was recorded, and nothing from the rejected calls (Req 17.1, 17.4).
set local role postgres;
select is((select row(request_count, cost_usd)::text from public.ai_usage
           where user_id = '13a00000-0000-4000-8000-000000000001'
             and acting_profile_id = '13b00000-0000-4000-8000-000000000001'
             and usage_day = private.nairobi_today()),
  row(2, 0.03::numeric(10,4))::text, 'two calls as ai_ann share one row with count 2 and cost 0.03');
select is((select row(request_count, cost_usd)::text from public.ai_usage
           where user_id = '13a00000-0000-4000-8000-000000000001'
             and acting_profile_id = '13b00000-0000-4000-8000-000000000007'),
  row(1, 0.05::numeric(10,4))::text, 'the call as the business is recorded on its own row');
select is((select count(*)::int from public.ai_usage where user_id = '13a00000-0000-4000-8000-000000000001'),
  2, 'Ann has exactly two rows: the acting profile is recorded on each');
select is((select count(*)::int from public.ai_usage
           where user_id in ('13a00000-0000-4000-8000-000000000001', '13a00000-0000-4000-8000-000000000002',
                             '13a00000-0000-4000-8000-000000000003')),
  3, 'the rejected calls left no rows');
select is((select usage_day from public.ai_usage
           where user_id = '13a00000-0000-4000-8000-000000000002'),
  private.nairobi_today(), 'usage_day is the Nairobi day');

-- ---------------------------------------------------------------------------------------------
-- As Ann: she reads only her rows, cannot write, and cannot record her own call.
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ann claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ann');

select is(public.ai_can_call(), true, 'Ann is under both limits (Req 17.3)');
select is((select count(*)::int from public.ai_usage), 2, 'Ann reads exactly her two rows (Req 17.5)');
select is_empty($$ select 1 from public.ai_usage where user_id <> '13a00000-0000-4000-8000-000000000001' $$,
  'Ann cannot read anyone else''s usage');
select throws_ok($$ insert into public.ai_usage (user_id, acting_profile_id, usage_day, request_count)
                    values ('13a00000-0000-4000-8000-000000000001', '13b00000-0000-4000-8000-000000000001',
                            current_date + 1, 1) $$,
  '42501', null, 'authenticated cannot insert into ai_usage');
select throws_ok($$ update public.ai_usage set request_count = 0 $$,
  '42501', null, 'authenticated cannot update ai_usage');
select throws_ok($$ delete from public.ai_usage $$, '42501', null, 'authenticated cannot delete from ai_usage');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', 0.01) $$,
  '42501', null, 'authenticated cannot execute ai_record_call, even for herself (Req 17.8)');
select throws_ok($$ select private.ai_under_limits('13a00000-0000-4000-8000-000000000001') $$,
  '42501', null, 'authenticated cannot call private.ai_under_limits');

-- ---------------------------------------------------------------------------------------------
-- As Ben, and as Cat who has used nothing.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ben claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Ben');
select is((select count(*)::int from public.ai_usage), 1, 'Ben reads exactly his one row');
select is((select user_id from public.ai_usage), '13a00000-0000-4000-8000-000000000002'::uuid,
  'Ben''s row is his own');

set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Cat claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Cat');
select is_empty($$ select 1 from public.ai_usage $$, 'Cat has no usage rows and sees nobody else''s');
select is(public.ai_can_call(), true, 'Cat can call');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read, no write, no function (Req 17.5, 17.8, 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.ai_usage $$, '42501', null, 'anon cannot read ai_usage');
select throws_ok($$ insert into public.ai_usage (user_id, usage_day)
                    values ('13a00000-0000-4000-8000-000000000001', current_date) $$,
  '42501', null, 'anon cannot insert into ai_usage');
select throws_ok($$ update public.ai_usage set request_count = 0 $$, '42501', null, 'anon cannot update ai_usage');
select throws_ok($$ delete from public.ai_usage $$, '42501', null, 'anon cannot delete from ai_usage');
select throws_ok($$ select public.ai_can_call() $$, '42501', null, 'anon cannot call ai_can_call');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', 0.01) $$,
  '42501', null, 'anon cannot execute ai_record_call (Req 17.8)');

-- ---------------------------------------------------------------------------------------------
-- Daily limit: three calls per login and Nairobi day. Ann has made three (two as ai_ann, one as
-- the business), so the limit counts the login, not the profile (Req 17.2, 17.3).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
update public.app_settings set ai_daily_call_limit = 3;
-- Cat's only row is from yesterday: a past day does not count towards today.
insert into public.ai_usage (user_id, acting_profile_id, usage_day, request_count, cost_usd)
values ('13a00000-0000-4000-8000-000000000003', '13b00000-0000-4000-8000-000000000003',
        private.nairobi_today() - 1, 99, 0);

select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ann claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ann');
select is(public.ai_can_call(), false, 'Ann is at the daily limit of 3 across both profiles');

set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(auth.uid(), '13a00000-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Ben');
select is(public.ai_can_call(), true, 'Ben has used 1 of 3, so he can call: the limit is per login');

set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000003', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(auth.uid(), '13a00000-0000-4000-8000-000000000003'::uuid, 'auth.uid() is Cat');
select is(public.ai_can_call(), true, 'Cat''s 99 calls from yesterday do not count today');

set local role postgres;
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;
select is(current_user::text, 'service_role', 'running as service_role');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000001', 0.01) $$,
  'PT429', 'ai.limit_reached', 'a fourth call by Ann is rejected');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000001',
                                                  '13b00000-0000-4000-8000-000000000007', 0.01) $$,
  'PT429', 'ai.limit_reached', 'the limit holds for her other profile too');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000002',
                                                 '13b00000-0000-4000-8000-000000000002', 0.01) $$,
  'Ben''s second call is accepted');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000002',
                                                 '13b00000-0000-4000-8000-000000000002', 0.01) $$,
  'Ben''s third call, the last under the limit, is accepted');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000002',
                                                  '13b00000-0000-4000-8000-000000000002', 0.01) $$,
  'PT429', 'ai.limit_reached', 'Ben''s fourth call is rejected');
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000003',
                                                 '13b00000-0000-4000-8000-000000000003', 0.01) $$,
  'Cat''s first call today is accepted');

set local role postgres;
select is((select sum(request_count)::int from public.ai_usage
           where user_id = '13a00000-0000-4000-8000-000000000001' and usage_day = private.nairobi_today()),
  3, 'the rejected calls added nothing to Ann''s count');
update public.app_settings set ai_daily_call_limit = 4;
select is(private.ai_under_limits('13a00000-0000-4000-8000-000000000001'), true,
  'raising the limit to 4 lets Ann call again');
select is(private.ai_under_limits('13a00000-0000-4000-8000-000000000002'), true,
  'raising the limit to 4 lets Ben call again');

-- ---------------------------------------------------------------------------------------------
-- Monthly cap: the cost of every login this month counts, and the cap applies to everyone
-- (Req 17.2, 17.3). The cap is set one cent above the current total, so one more call crosses it.
-- ---------------------------------------------------------------------------------------------
update public.app_settings
set ai_daily_call_limit = 20,
    monthly_spend_cap_usd = (select ceil(coalesce(sum(cost_usd), 0) * 100) / 100 + 0.01
                             from public.ai_usage where usage_day >= private.nairobi_month_start());
select is(private.ai_under_limits('13a00000-0000-4000-8000-000000000005'), true,
  'Eve is under the daily limit and under the monthly cap');

select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;
select lives_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000005',
                                                 '13b00000-0000-4000-8000-000000000005', 0.05) $$,
  'Eve''s call is accepted while the total is still under the cap, and it crosses the cap');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000005',
                                                  '13b00000-0000-4000-8000-000000000005', 0.01) $$,
  'PT429', 'ai.limit_reached', 'Eve is rejected once the monthly cap is reached');
select throws_ok($$ select public.ai_record_call('13a00000-0000-4000-8000-000000000006',
                                                  '13b00000-0000-4000-8000-000000000006', 0.01) $$,
  'PT429', 'ai.limit_reached', 'Fay has used nothing, yet she is rejected too: the cap is global');

set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000006', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Fay claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000006'::uuid, 'auth.uid() is Fay');
select is(public.ai_can_call(), false, 'ai_can_call is false for Fay once the monthly cap is reached');

set local role postgres;
select is(private.ai_under_limits(null), false, 'a null login is never under the limits');
update public.app_settings set monthly_spend_cap_usd = 10;
select is(private.ai_under_limits('13a00000-0000-4000-8000-000000000006'), true,
  'raising the cap lets Fay call again');

-- ---------------------------------------------------------------------------------------------
-- Deleting a profile keeps its spend: the acting profile becomes null (Req 17.1).
-- ---------------------------------------------------------------------------------------------
select is((select sum(cost_usd) from public.ai_usage where user_id = '13a00000-0000-4000-8000-000000000005'),
  0.05::numeric, 'Eve has spent 0.05 as ai_eve');
delete from public.profiles where id = '13b00000-0000-4000-8000-000000000005';
select is((select count(*)::int from public.ai_usage
           where user_id = '13a00000-0000-4000-8000-000000000005' and acting_profile_id is null),
  1, 'Eve''s row survives the profile deletion with a null acting profile');
select is((select sum(cost_usd) from public.ai_usage where user_id = '13a00000-0000-4000-8000-000000000005'),
  0.05::numeric, 'her spend still counts after the profile is gone');

-- =============================================================================================
-- Last.fm link (task 26; Req 18.1 to 18.3, 22.1 to 22.5, 25.1, 25.2)
-- Reuses the people above: Ann owns ai_ann and manages the business ai_shop, Ben owns ai_ben,
-- Cat owns ai_cat, Dan owns ai_dan, Fay owns ai_fay. Eve's profile is already deleted.
-- =============================================================================================
set local role postgres;

-- ---------------------------------------------------------------------------------------------
-- Catalog: columns, foreign key, unique key, trigger, RLS, policies and grants (Req 18.1, 22.1 to 22.5).
-- ---------------------------------------------------------------------------------------------
select has_table('public', 'lastfm_links', 'lastfm_links exists');
select columns_are('public', 'lastfm_links', array[
  'id', 'profile_id', 'username', 'created_at', 'updated_at'
], 'lastfm_links has exactly its five columns');
select col_type_is('public', 'lastfm_links', 'username', 'text', 'username is text');
select col_not_null('public', 'lastfm_links', 'profile_id', 'a link always belongs to a profile');
select col_not_null('public', 'lastfm_links', 'username', 'a link always has a username');
select is((select confrelid::regclass::text || ':' || confdeltype::text from pg_catalog.pg_constraint
           where conrelid = 'public.lastfm_links'::regclass and contype = 'f'
             and conkey = array[(select attnum from pg_catalog.pg_attribute
                                 where attrelid = 'public.lastfm_links'::regclass and attname = 'profile_id')]::smallint[]),
  'profiles:c', 'profile_id references profiles and cascades on delete');
select col_is_unique('public', 'lastfm_links', 'profile_id', 'a profile has at most one link');
select has_trigger('public', 'lastfm_links', 'lastfm_links_set_updated_at', 'lastfm_links keeps updated_at current');
select ok((select relrowsecurity from pg_class where oid = 'public.lastfm_links'::regclass),
  'RLS is enabled on lastfm_links');
select policies_are('public', 'lastfm_links', array[
  'lastfm_links_authenticated_select', 'lastfm_links_authenticated_insert',
  'lastfm_links_authenticated_update', 'lastfm_links_authenticated_delete'
], 'lastfm_links has exactly its four policies');
select table_privs_are('public', 'lastfm_links', 'anon', array[]::text[], 'anon has no privilege on lastfm_links');
select table_privs_are('public', 'lastfm_links', 'authenticated', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'authenticated holds select, insert, update and delete on lastfm_links');

-- ---------------------------------------------------------------------------------------------
-- Username format: 2 to 15 characters of letters, digits, underscore and hyphen, starting with a
-- letter (Req 18.1). Checked as the test owner, so only the check constraint can reject.
-- ---------------------------------------------------------------------------------------------
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'a') $$,
  '23514', null, 'one character is too short');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'abcdefghijklmnop') $$,
  '23514', null, 'sixteen characters is too long');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', '') $$,
  '23514', null, 'an empty username is rejected');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', '1abc') $$,
  '23514', null, 'a username cannot start with a digit');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', '_abc') $$,
  '23514', null, 'a username cannot start with an underscore');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'ab cd') $$,
  '23514', null, 'a username cannot contain a space');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'ab.cd') $$,
  '23514', null, 'a username cannot contain a dot');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', E'abc\n') $$,
  '23514', null, 'a trailing newline is rejected');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'añbc') $$,
  '23514', null, 'a non ASCII letter is rejected');
select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000004', 'ab') $$,
  'two characters, the shortest username, is accepted');
select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000006', 'abcdefghijklmno') $$,
  'fifteen characters, the longest username, is accepted');
select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000003', 'A_b-9') $$,
  'capitals, digits, underscore and hyphen are accepted');
select is((select count(*)::int from public.lastfm_links
           where profile_id in ('13b00000-0000-4000-8000-000000000003', '13b00000-0000-4000-8000-000000000004',
                                '13b00000-0000-4000-8000-000000000006')),
  3, 'the three valid links are stored');
select is((select count(*)::int from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000002'),
  0, 'the rejected usernames left no row for Ben');

-- One link per profile (Req 18.1).
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000004', 'second') $$,
  '23505', null, 'a second link for the same profile is rejected');

-- ---------------------------------------------------------------------------------------------
-- As Ann: she writes and reads links for the profiles she acts as, and only those (Req 18.2, 18.3).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ann claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000001'::uuid, 'auth.uid() is Ann');

select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000001', 'ann_fm') $$,
  'Ann links a Last.fm username to her own profile');
select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000007', 'shop_fm') $$,
  'Ann links a username to the business she manages');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000002', 'ann_for_ben') $$,
  '42501', null, 'Ann cannot link a username to Ben''s profile');
select is((select count(*)::int from public.lastfm_links), 2,
  'Ann reads exactly the links of her two profiles');
select is_empty($$ select 1 from public.lastfm_links
                   where profile_id not in ('13b00000-0000-4000-8000-000000000001',
                                            '13b00000-0000-4000-8000-000000000007') $$,
  'Ann cannot read anyone else''s link');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000001', 'ann_again') $$,
  '23505', null, 'Ann cannot add a second link to the same profile');
select throws_ok($$ update public.lastfm_links set username = '1bad'
                    where profile_id = '13b00000-0000-4000-8000-000000000001' $$,
  '23514', null, 'an update to a badly formed username is rejected');
select lives_ok($$ update public.lastfm_links set username = 'ann_fm2'
                   where profile_id = '13b00000-0000-4000-8000-000000000001' $$,
  'Ann changes the username on her own link');
select is((select username from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000001'),
  'ann_fm2', 'the new username is stored');
select throws_ok($$ update public.lastfm_links set profile_id = '13b00000-0000-4000-8000-000000000002'
                    where profile_id = '13b00000-0000-4000-8000-000000000001' $$,
  '42501', null, 'Ann cannot move her link to a profile she does not act as');
select lives_ok($$ update public.lastfm_links set username = 'hacked'
                   where profile_id = '13b00000-0000-4000-8000-000000000004' $$,
  'Ann''s update of Dan''s link runs but matches no row');
select lives_ok($$ delete from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000004' $$,
  'Ann''s delete of Dan''s link runs but matches no row');
select lives_ok($$ delete from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000007' $$,
  'Ann removes the business link');
select is((select count(*)::int from public.lastfm_links), 1, 'Ann now reads one link');

-- ---------------------------------------------------------------------------------------------
-- As Ben: he sees nobody's link and cannot write to anyone else's profile.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims',
  json_build_object('sub', '13a00000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the Ben claims');
set local role authenticated;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '13a00000-0000-4000-8000-000000000002'::uuid, 'auth.uid() is Ben');

select is_empty($$ select 1 from public.lastfm_links $$, 'Ben reads no link while he has none of his own');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000001', 'ben_for_ann') $$,
  '42501', null, 'Ben cannot link a username to Ann''s profile');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000007', 'ben_for_shop') $$,
  '42501', null, 'Ben cannot link a username to a business he does not manage');
select lives_ok($$ update public.lastfm_links set username = 'hacked'
                   where profile_id = '13b00000-0000-4000-8000-000000000001' $$,
  'Ben''s update of Ann''s link runs but matches no row');
select lives_ok($$ delete from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000001' $$,
  'Ben''s delete of Ann''s link runs but matches no row');
select lives_ok($$ insert into public.lastfm_links (profile_id, username)
                   values ('13b00000-0000-4000-8000-000000000002', 'ben-fm') $$,
  'Ben links a username to his own profile');
select is((select count(*)::int from public.lastfm_links), 1, 'Ben reads only his own link');

-- ---------------------------------------------------------------------------------------------
-- Signed out visitor: no read and no write (Req 18.3, 22.5).
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');

select throws_ok($$ select 1 from public.lastfm_links $$, '42501', null, 'anon cannot read lastfm_links');
select throws_ok($$ insert into public.lastfm_links (profile_id, username)
                    values ('13b00000-0000-4000-8000-000000000001', 'anon_fm') $$,
  '42501', null, 'anon cannot insert into lastfm_links');
select throws_ok($$ update public.lastfm_links set username = 'anon_fm' $$,
  '42501', null, 'anon cannot update lastfm_links');
select throws_ok($$ delete from public.lastfm_links $$, '42501', null, 'anon cannot delete from lastfm_links');

-- ---------------------------------------------------------------------------------------------
-- What is stored, as the test owner: the other logins changed nothing, and deleting a profile
-- deletes its link.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select is((select username from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000001'),
  'ann_fm2', 'Ben''s update and delete left Ann''s link as she set it');
select is((select username from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000004'),
  'ab', 'Ann''s update and delete left Dan''s link untouched');
select is((select count(*)::int from public.lastfm_links), 5, 'Ann, Ben, Cat, Dan and Fay each hold one link');
delete from public.profiles where id = '13b00000-0000-4000-8000-000000000006';
select is((select count(*)::int from public.lastfm_links where profile_id = '13b00000-0000-4000-8000-000000000006'),
  0, 'deleting a profile deletes its link');

select * from finish();
rollback;
