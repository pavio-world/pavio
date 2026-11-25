# 003: Access relationships only through security definer functions

Date: 25 November 2026

Spec: 00-database-foundation (Requirement 8.19, 8.23, 28.7)

## Context

The `relationships` table holds every connection and follow, with a requester, a target, a type and a status of `pending`, `accepted` or `declined`. Requirement 8.23 says a relationship is readable only by users who act as the requester or the target. Requirement 8.19 adds a rule that row security cannot express: when the requester of a declined connection reads it, the status must read as `pending`. The requester is never told that they were declined.

RLS policies decide which rows a role may see. They cannot change the value of a column in a visible row. If the requester could select their own rows from `relationships`, they would read `declined` directly. A column level grant does not help either, because the requester still needs the status of their other relationships. A view that rewrites the status could be bypassed by anyone who can still read the base table, and it would need its own copy of the "acts as requester or target" filter.

Writes have similar needs. Every write must check the profile being acted as (`public.acts_as`), and several rules depend on the other party's type, on who manages which page, and on rows the caller cannot see, such as an existing declined request in the other direction (Requirements 8.7 to 8.12, 8.16 and 8.18).

## Decision

`relationships` has RLS enabled with no policies and no grants to `anon` or `authenticated`. The API cannot select, insert, update or delete its rows directly.

All access goes through security definer functions with `search_path = ''`:

- `public.request_relationship(p_from, p_to, p_type)` checks `acts_as(p_from)` and inserts the row.
- `public.respond_to_connection(p_relationship_id, p_accept)` lets only the target of a pending connection accept or decline it.
- `public.remove_relationship(p_relationship_id)` deletes a relationship when the caller is allowed to remove it (Requirements 8.13 to 8.15 and 8.17).
- `public.my_relationships(p_acting)` checks `acts_as(p_acting)` and returns only rows where the acting profile is the requester or the target (Requirement 8.23). For a declined connection whose requester is the acting profile, it returns the status as `pending` (Requirement 8.19).
- `public.relationship_counts(p_profile_id)` returns only the number of accepted connections and followers, for any viewer, and no profile ids, handles or names (Requirement 8.24).

The structural rules (no self relationships, no managed pages, no business to person, follow and connection shapes, one row per pair and type, immutable parties and type, the declined then re-ask replacement, and circle cleanup on delete) live in triggers on the table. They bind every writer, including the seed and tests that run as `postgres`, not only the RPCs. The RPCs add the acting checks on top.

Visibility helpers such as `private.is_connected` and `private.follows` read the table from inside security definer code, so `can_view` and the all followers audience keep working without any grant.

## Consequences

- A declined requester cannot learn that they were declined. The only readable path returns `pending`, and a repeat request from them fails with `relationship.exists`, the same message as a pending duplicate.
- A failed lookup in `respond_to_connection` or `remove_relationship` raises `relationship.not_found` whether the row is missing or the caller has no right to it, so the functions do not confirm that a relationship exists.
- The table's shape is hidden from the client. The app must call the RPCs and cannot use the generic Supabase table query builder for relationships. Any new read path must be a new definer function that checks `acts_as` and applies the same status masking.
- Security depends on the table staying ungranted and the functions staying definer. pgTAP checks that RLS is enabled on every table (`01_schema.test.sql`), that every definer function has an empty `search_path` and the planned execute grants (`02_security_definer.test.sql`), and that the status masking holds (`05_relationships.test.sql`). Property 15 tests the decline, re-request and removal sequence.
- Supabase Realtime cannot stream `relationships` changes to clients, because it respects the same grants. Notifications carry relationship events instead (Requirement 15).
