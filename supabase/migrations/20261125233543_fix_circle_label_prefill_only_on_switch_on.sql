-- Fix after Spec 00 task 13 (Dominic's decision): the member label is pre-filled from the private
-- name only when the switch turns on (off to on, or an insert with the switch on) and the label is
-- empty or blank. While the switch is already on, a write that leaves the label empty or blank is
-- rejected with PT422 circle.label_required, so clearing a shown label can never copy the private
-- name back to members. Renaming keeps the label (9.7) and switching off keeps it (9.8).
-- Replaces only the trigger function body; the trigger, definer, search_path and ACL stay.

create or replace function private.circles_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_all_followers
     and (select p.type from public.profiles p where p.id = new.owner_profile_id) <> 'business' then
    raise exception using errcode = 'PT422', message = 'circle.all_followers_business_only'; -- 10.8
  end if;
  if tg_op = 'UPDATE' then
    if new.owner_profile_id <> old.owner_profile_id or new.is_all_followers <> old.is_all_followers then
      raise exception using errcode = 'PT422', message = 'circle.immutable';
    end if;
    if old.is_all_followers and new.private_name <> old.private_name then
      raise exception using errcode = 'PT422', message = 'circle.all_followers_fixed';      -- 10.6
    end if;
  end if;
  if new.show_member_label and (new.member_label is null or btrim(new.member_label) = '') then
    if tg_op = 'INSERT' or not old.show_member_label then
      -- The switch is turning on with no label: pre-fill from the private name (9.5).
      new.member_label := new.private_name;
    else
      -- The switch is already on: clearing the shown label is rejected (9.6).
      raise exception using errcode = 'PT422', message = 'circle.label_required';
    end if;
  end if;
  -- Nothing else touches member_label (9.7, 9.8); circles_label_when_shown stays the backstop for 9.6.
  return new;
end;
$$;
revoke execute on function private.circles_before_write() from public;
revoke execute on function private.circles_before_write() from anon, authenticated;
;
