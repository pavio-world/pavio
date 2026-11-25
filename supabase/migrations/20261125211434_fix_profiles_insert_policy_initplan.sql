-- Performance advisor fix for migration 5 (lint 0003 auth_rls_initplan).
-- Same rule as before; auth.uid() is wrapped in a scalar subquery so it is evaluated once per
-- statement instead of once per row.
alter policy profiles_authenticated_insert on public.profiles
  with check (
    (select auth.uid()) is not null
    and (
      type = 'person'
      or (type = 'business' and exists (select 1 from public.my_profiles() m where m.role = 'person'))
    )
  );
;
