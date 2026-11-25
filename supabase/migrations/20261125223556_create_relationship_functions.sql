-- Migration 9: the relationship RPCs, the only API path to public.relationships.
-- Spec 00 Req 8.4, 8.5, 8.13 to 8.19, 8.21, 8.23, 8.24, 22.3, 22.4; design "Relationship functions",
-- "Function execute grants", "Error Handling", DR-4; decision 003.
-- Structural rules stay in the table triggers of migration 8; these functions add the acting checks.
-- Every function revokes execute from public, anon and authenticated before its grants.
-- ---------------------------------------------------------------------------------------------
-- request_relationship: the acting profile asks for a connection or follows a business.
-- ---------------------------------------------------------------------------------------------
create or replace function public.request_relationship(
  p_from uuid,
  p_to uuid,
  p_type public.relationship_type
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_constraint text;
begin
  if not public.acts_as(p_from) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';
  end if;
  begin
    -- relationships_guard_insert decides the status and rejects every illegal shape.
    insert into public.relationships (requester_profile_id, target_profile_id, type)
    values (p_from, p_to, p_type)
    returning id into v_id;
  exception when unique_violation then
    -- Two identical requests at the same moment both pass the guard's lookup; the loser hits
    -- the unique index. Report it as the same duplicate the guard raises (Error Handling, 8.12).
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'relationships_pair_uq' then
      raise exception using errcode = 'PT409', message = 'relationship.exists';
    end if;
    raise;
  end;
  return v_id;
end;
$$;
revoke execute on function public.request_relationship(uuid, uuid, public.relationship_type) from public;
revoke execute on function public.request_relationship(uuid, uuid, public.relationship_type) from anon, authenticated;
grant execute on function public.request_relationship(uuid, uuid, public.relationship_type) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- respond_to_connection: only the target of a pending connection accepts or declines (8.4, 8.5, 8.21).
-- A missing row and a row the caller may not answer give the same not_found (decision 003).
-- ---------------------------------------------------------------------------------------------
create or replace function public.respond_to_connection(p_relationship_id uuid, p_accept boolean)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_r record;
begin
  select r.id, r.type, r.status, r.target_profile_id into v_r
  from public.relationships r
  where r.id = p_relationship_id
  for update;
  if not found or not public.acts_as(v_r.target_profile_id) then
    raise exception using errcode = 'PT404', message = 'relationship.not_found';
  end if;
  if v_r.type <> 'connection' or v_r.status <> 'pending' then
    raise exception using errcode = 'PT422', message = 'relationship.bad_transition';
  end if;
  -- A null p_accept leaves status null, which the not null constraint rejects.
  update public.relationships r
  set status = case when p_accept then 'accepted'::public.relationship_status
                    when not p_accept then 'declined'::public.relationship_status end
  where r.id = p_relationship_id;
end;
$$;
revoke execute on function public.respond_to_connection(uuid, boolean) from public;
revoke execute on function public.respond_to_connection(uuid, boolean) from anon, authenticated;
grant execute on function public.respond_to_connection(uuid, boolean) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- remove_relationship: remove, unfollow, withdraw, or clear a decline (8.13 to 8.15, 8.17).
-- ---------------------------------------------------------------------------------------------
create or replace function public.remove_relationship(p_relationship_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_r record;
  v_allowed boolean;
begin
  select r.id, r.type, r.status, r.requester_profile_id, r.target_profile_id into v_r
  from public.relationships r
  where r.id = p_relationship_id
  for update;
  if not found then
    raise exception using errcode = 'PT404', message = 'relationship.not_found';
  end if;
  v_allowed :=
       (v_r.type = 'connection' and v_r.status = 'accepted'
          and (public.acts_as(v_r.requester_profile_id) or public.acts_as(v_r.target_profile_id))) -- 8.13
    or (v_r.type = 'follow' and public.acts_as(v_r.requester_profile_id))                         -- 8.14
    or (v_r.status in ('pending', 'declined') and public.acts_as(v_r.requester_profile_id))        -- 8.15
    or (v_r.status = 'declined' and public.acts_as(v_r.target_profile_id));                       -- 8.17
  if not coalesce(v_allowed, false) then
    raise exception using errcode = 'PT404', message = 'relationship.not_found';
  end if;
  delete from public.relationships r where r.id = p_relationship_id;
end;
$$;
revoke execute on function public.remove_relationship(uuid) from public;
revoke execute on function public.remove_relationship(uuid) from anon, authenticated;
grant execute on function public.remove_relationship(uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- my_relationships: the acting profile's relationships. A declined request reads as pending to
-- its requester (8.19); only the two parties can read a relationship (8.23).
-- ---------------------------------------------------------------------------------------------
create or replace function public.my_relationships(p_acting uuid)
returns table (
  relationship_id uuid,
  type public.relationship_type,
  direction text,
  status public.relationship_status,
  other_profile_id uuid,
  other_handle text,
  other_display_name text,
  other_type public.profile_type,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.acts_as(p_acting) then
    raise exception using errcode = 'PT403', message = 'acting.not_allowed';             -- 8.23
  end if;
  return query
  select r.id,
         r.type,
         case when r.requester_profile_id = p_acting then 'outgoing' else 'incoming' end,
         case when r.status = 'declined' and r.requester_profile_id = p_acting
              then 'pending'::public.relationship_status else r.status end,              -- 8.19
         o.id,
         o.handle,
         o.display_name,
         o.type,
         r.created_at
  from public.relationships r
  join public.profiles o
    on o.id = case when r.requester_profile_id = p_acting
                   then r.target_profile_id else r.requester_profile_id end
  where p_acting in (r.requester_profile_id, r.target_profile_id)
  order by r.created_at desc, r.id;
end;
$$;
revoke execute on function public.my_relationships(uuid) from public;
revoke execute on function public.my_relationships(uuid) from anon, authenticated;
grant execute on function public.my_relationships(uuid) to authenticated;
-- ---------------------------------------------------------------------------------------------
-- relationship_counts: public counts for any viewer, with no ids, handles or names (8.24, 22.4).
-- ---------------------------------------------------------------------------------------------
create or replace function public.relationship_counts(p_profile_id uuid)
returns table (connections bigint, followers bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*) from public.relationships r
          where r.type = 'connection' and r.status = 'accepted'
            and p_profile_id in (r.requester_profile_id, r.target_profile_id)),
         (select count(*) from public.relationships r
          where r.type = 'follow' and r.target_profile_id = p_profile_id);
$$;
revoke execute on function public.relationship_counts(uuid) from public;
revoke execute on function public.relationship_counts(uuid) from anon, authenticated;
grant execute on function public.relationship_counts(uuid) to anon, authenticated;
;
