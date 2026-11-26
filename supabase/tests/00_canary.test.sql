-- Canary: proves the simulated API users of every other test file are real. The claims carry
-- both sub and role, private.is_api_caller() is true for them, the role switch really happens,
-- auth.uid() is the simulated login, and a known restricted row is invisible. If a switch is
-- silently skipped the file aborts with an error instead of passing as a trusted caller.
-- Spec 00 Req 25.9 to 25.12; D-8, DR-1.
begin;
-- Same login workaround as 01_schema.test.sql: run as postgres with extensions on the path.
set local role postgres;
set local search_path = public, extensions;
select plan(13);
-- ---------------------------------------------------------------------------------------------
-- Fixtures, as the test owner with no claims: persons A and B with no relationship, and a
-- connections item owned by B. A is not connected to B, so A must never see it.
-- ---------------------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00a00000-0000-4000-8000-000000000001', 'a.canary@example.invalid'),
  ('00a00000-0000-4000-8000-000000000002', 'b.canary@example.invalid');
insert into public.profiles (id, type, owner_user_id, handle, display_name) values
  ('00b00000-0000-4000-8000-000000000001', 'person', '00a00000-0000-4000-8000-000000000001', 'a_canary', 'A'),
  ('00b00000-0000-4000-8000-000000000002', 'person', '00a00000-0000-4000-8000-000000000002', 'b_canary', 'B');
insert into public.content_items (id, owner_profile_id, content_type, audience, details) values
  ('00d00000-0000-4000-8000-000000000001', '00b00000-0000-4000-8000-000000000002', 'status', 'connections',
   '{"text": "connections only"}');
-- The restricted row exists, so the is_empty checks below cannot pass vacuously.
select isnt_empty($$ select id from public.content_items where id = '00d00000-0000-4000-8000-000000000001' $$,
  'the test owner sees B''s connections item');
-- Without claims the caller is trusted, so the canary can tell the two apart.
select ok(not private.is_api_caller(), 'is_api_caller is false without claims');
-- D-8: the API roles never get USAGE on private, and this file grants nothing on it.
select ok(not has_schema_privilege('authenticated', 'private', 'USAGE'), 'authenticated has no USAGE on private');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon has no USAGE on private');
-- ---------------------------------------------------------------------------------------------
-- Signed in as A, in the canary order (DR-1).
-- ---------------------------------------------------------------------------------------------
select set_config('request.jwt.claims',
  json_build_object('sub', '00a00000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the authenticated claims');
set local role authenticated;
-- Hard stop: if the switch did not happen, abort the whole file rather than report one failure.
do $$
begin
  if current_user::text <> 'authenticated' then
    raise exception 'canary: role switch to authenticated did not happen, current_user is %', current_user;
  end if;
end $$;
select is(current_user::text, 'authenticated', 'running as authenticated');
select is(auth.uid(), '00a00000-0000-4000-8000-000000000001'::uuid, 'auth.uid() is A');
select is_empty($$ select id from public.content_items where id = '00d00000-0000-4000-8000-000000000001' $$,
  'A cannot read B''s connections item');
select ok(not public.can_view('00d00000-0000-4000-8000-000000000001', '00b00000-0000-4000-8000-000000000001'),
  'can_view is false for A on B''s connections item');
-- ---------------------------------------------------------------------------------------------
-- Signed out (anon), in the same order.
-- ---------------------------------------------------------------------------------------------
set local role postgres;
select set_config('request.jwt.claims', json_build_object('sub', null, 'role', 'anon')::text, true);
select ok(private.is_api_caller(), 'is_api_caller is true for the anon claims');
set local role anon;
do $$
begin
  if current_user::text <> 'anon' then
    raise exception 'canary: role switch to anon did not happen, current_user is %', current_user;
  end if;
end $$;
select is(current_user::text, 'anon', 'running as anon');
select is(auth.uid(), null::uuid, 'auth.uid() is null for anon');
select is_empty($$ select id from public.content_items where id = '00d00000-0000-4000-8000-000000000001' $$,
  'anon cannot read B''s connections item');
set local role postgres;
select * from finish();
rollback;
