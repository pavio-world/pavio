# Implementation Plan: 00 Database Foundation

## Overview

This plan builds the whole Pavio database on the hosted Supabase project `pavio` (ref `tmglpalznmyonaynojyy`) in small steps, in this order: branch and tooling, decision records, migrations 1 to 23 in exactly the order of the design's **Migration Plan** (each with the pgTAP file that proves it), catalog-wide tests, the fast-check property suite, the demo seed, and final verification with the pull request.

Implementation languages: SQL (Postgres, plpgsql) for migrations and pgTAP tests; TypeScript (strict) for the property suite and seed. No Next.js app is created in this spec.

Every task ends with passing tests and the standard close-out described in **Notes**: a `DEVLOG.md` entry, atomic Conventional Commits staged by explicit path, and a push of `spec/00-database-foundation`.

Every migration task follows the **Migration_Workflow** described in Notes. Every migration that creates or replaces a function runs `revoke execute on function ... from public` (and from `anon` and `authenticated` where they are not meant to call it) before any grant, as in the design's **Grants and revokes strategy**.

## Tasks

- [ ] 1. Set up the branch, spec documents and Node tooling
  - [-] 1.1 Create the spec branch and commit the spec documents
    - `git checkout main && git pull`, confirm `main` is up to date with `origin/main`, then `git checkout -b spec/00-database-foundation`
    - Commit the untracked spec files (`.kiro/specs/00-database-foundation/requirements.md`, `design.md`, `tasks.md`, `.config.kiro`) as `docs(kiro): add spec 00 database foundation documents`, and `docs/kiro-prompts/00-database-foundation.md` as a separate `docs(kiro): add spec 00 prompt`, staging each path explicitly
    - Do not edit `requirements.md` or `design.md`
    - Close out: DEVLOG entry, push the branch with `git push -u origin spec/00-database-foundation`
    - _Requirements: 28.1, 28.2, 28.3, 28.4, 28.6_

  - [~] 1.2 Verify the existing Supabase folder and link
    - Check that `supabase/config.toml` exists, that `supabase/.temp/project-ref` holds `tmglpalznmyonaynojyy`, and that `supabase/migrations/20261125040502_enable_pgtap.sql` exists; run `supabase init` or `supabase link --project-ref tmglpalznmyonaynojyy` only for a part that is missing
    - Confirm with MCP `list_migrations` that `enable_pgtap` is applied and with `list_extensions` that `pgtap` is in the `extensions` schema; do not reapply it
    - If any command or config points at a project other than `pavio`, stop and ask Dominic
    - No commit is expected unless something was missing; close out with a DEVLOG entry
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

  - [~] 1.3 Add the minimal Node tooling
    - Create `package.json` (private) with dev dependencies only: `vitest`, `fast-check`, `pg`, `dotenv`, `tsx`, `typescript`, `@types/node`, `@types/pg`, `@supabase/supabase-js`; scripts `test:property` (`vitest run tests/property`) and `typecheck` (`tsc --noEmit`); no Next.js
    - Create `tsconfig.json` with `"strict": true` including `tests/` and `supabase/seed/`, and `vitest.config.ts` with a long test timeout and no watch mode
    - Confirm `.gitignore` already excludes `node_modules/`, `coverage/` and `*.log`; leave `.env.local` and `.env.example` untouched
    - Run `npm install` and `npm run typecheck`; commit `package.json`, `package-lock.json`, `tsconfig.json`, `vitest.config.ts` as `build(kiro): add minimal node tooling for property tests`
    - Close out: DEVLOG entry, push
    - _Requirements: 2.1, 2.2, 2.3, 2.6, 2.7, 28.10_

- [ ] 2. Record the design decisions
  - [~] 2.1 Write `docs/decisions/001-vouches-own-table.md`
    - Context, decision and consequences for storing vouches in their own `vouches` table sharing the uuid id space with `content_items`, resolved by `can_view`
    - Commit as `docs(vouches): record decision to store vouches in their own table`
    - _Requirements: 14.2, 14.3, 28.7_

  - [~] 2.2 Write `docs/decisions/002-can-view-core-and-wrapper.md`
    - Context, decision and consequences for keeping all visibility logic in `private.can_view` with `public.can_view` only nulling an untrusted viewer id; include how `view_as` reuses the core
    - Commit as `docs(content): record can_view core and wrapper decision`
    - _Requirements: 20.1, 20.15, 21.4, 28.7_

  - [~] 2.3 Write `docs/decisions/003-relationships-through-rpc.md`
    - Context, decision and consequences for denying direct table access to `relationships` and serving reads and writes through security definer RPCs (needed for declined-reads-as-pending)
    - Commit as `docs(relationships): record decision to access relationships through rpc`
    - Close out: DEVLOG entry, push
    - _Requirements: 8.19, 8.23, 28.7_

- [~] 3. Migration 1: `enable_pg_trgm_and_pg_cron`
  - Apply through the Migration_Workflow: `pg_trgm` in schema `extensions`, `pg_cron` in `pg_catalog`
  - Create `supabase/tests/01_schema.test.sql` (begin, plan, rollback, `finish()`), asserting both extensions are installed and `pg_trgm` is in `extensions`
  - Run `supabase test db --linked`; commit migration and test as `db(search): enable pg_trgm and pg_cron extensions`
  - Close out: DEVLOG entry, push
  - _Requirements: 1.6, 3.1, 3.2, 3.3, 25.10, 25.11_

- [~] 4. Migration 2: `setup_private_schema_and_privileges`
  - Apply through the Migration_Workflow: schema `private` with `revoke all ... from public, anon, authenticated`; the default privilege revokes on tables, sequences and functions in `public`, plus the global `alter default privileges for role postgres revoke execute on functions from public`
  - Create `private.set_updated_at`, `private.is_api_caller`, `private.nairobi_today`, `private.nairobi_month_start`, `private.immutable_array_to_text` and `private.tags_valid`, each with `revoke execute ... from public` first; keep execute for `anon` and `authenticated` only on the two pure validators
  - No USAGE on schema `private` for `anon` or `authenticated`, now or later (D-8)
  - Extend `01_schema.test.sql`: `has_schema_privilege` false for `anon` and `authenticated` on `private`; create `supabase/tests/02_security_definer.test.sql` asserting `search_path=` in `proconfig`, `immutable_array_to_text` is immutable, and `is_api_caller` returns true only for `anon`/`authenticated` claims
  - Run `supabase test db --linked`; commit as `db(kiro): add private schema and default privilege revokes`
  - Close out: DEVLOG entry, push
  - _Requirements: 3.9, 4.13, 22.3, 25.10, 25.11; D-8_

- [~] 5. Migration 3: `create_enum_types`
  - Apply through the Migration_Workflow: `profile_type`, `manager_role`, `relationship_type`, `relationship_status`, `audience`, `content_type` (no `vouch`), `notification_type`, `dot_colour`, `story_label_kind` with the labels in the design's **Enumerated types** table
  - Extend `01_schema.test.sql` with `enum_has_labels` for each enum
  - Run `supabase test db --linked`; commit as `db(kiro): add enum types`
  - Close out: DEVLOG entry, push
  - _Requirements: 3.10, 4.9, 8.1, 11.2, 11.3, 15.2_

- [~] 6. Migration 4: `create_lookup_tables`
  - Apply through the Migration_Workflow: `languages` (with `en`, `sw`), `reserved_handles` (the 21 words of Req 4.5), `app_settings` (singleton row: 10 US dollars cap, 20 calls a day, 0.05 per call), each with RLS enabled, policies and grants in the same file; SELECT on `languages` for `anon` and `authenticated` only
  - Extend `01_schema.test.sql`: uuid primary keys with `gen_random_uuid()`, `created_at`, `updated_at` trigger on `app_settings`, RLS enabled, the seeded rows, `anon`/`authenticated` cannot read or write `reserved_handles` or `app_settings`, cannot write `languages`
  - Run `supabase test db --linked`; commit as `db(profiles): add languages, reserved handles and app settings tables`
  - Close out: DEVLOG entry, push
  - _Requirements: 3.5, 3.8, 3.9, 4.5, 4.6, 4.7, 17.2, 17.6, 22.1, 22.2, 22.5, 25.1; D-4_

- [~] 7. Checkpoint: foundation migrations
  - Ensure all tests pass, ask the user if questions arise.
  - `supabase test db --linked` is green and the security advisor reports nothing.

- [ ] 8. Migration 5: `create_profiles_and_acts_as`
  - [~] 8.1 Write and apply the migration
    - Apply through the Migration_Workflow: `profiles` (columns, checks, generated `tags_text` and `search_tsv` from `what_i_do` directly, unique `lower(handle)`, unique `owner_user_id`, trigram and GIN indexes with `extensions.gin_trgm_ops`), `profile_managers`, `private.controls`, `private.share_controller`, `acts_as`, `my_profile_ids`, `my_profiles`, `is_profile_owner`, `add_profile_manager`, `remove_profile_manager`
    - Triggers: `profiles_before_write` (tag normalisation, handle never rewritten, reserved check only on insert or handle change, owner from `auth.uid()` for API callers, type and owner immutable), `profiles_after_insert` (owner manager row; the all followers circle is added in migration 10), deferred `profiles_business_has_owner`, `profile_managers_guard`, `profile_managers_after_change` (last owner protection, delete business when last owner login is gone), `updated_at` triggers
    - RLS and column grants exactly as in the design's profiles and profile_managers sections; `revoke execute ... from public` before each function grant
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.8, 4.10, 4.11, 4.12, 4.13, 4.14, 4.15, 4.16, 5.1, 5.2, 5.3, 5.4, 5.5, 5.7, 6.7, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12, 7.13, 22.6, 22.7; D-6_

  - [~] 8.2 Write `supabase/tests/03_handles_profiles.test.sql`
    - Handle format and reserved words; `Amina` rejected, not lowercased, and stored handle equals input (D-6); case-insensitive uniqueness; a profile whose handle is reserved later can still update `display_name` and `bio` but cannot change to a reserved word (`PT422 profile.handle_reserved`); defaults for language, dot colour, theme and 2006 mode; length boundaries; one person per login; public versus private column grants for `anon` and `authenticated`; avatar and cover path checks; `acts_as` true, false for anon and false for a missing id; `anon` cannot write
    - Simulate users with `set_config('request.jwt.claims', ..., true)` carrying `sub` and `role`, then `set local role`, in the canary order
    - _Requirements: 4.2, 4.3, 4.4, 4.5, 4.8, 4.10, 4.12, 4.13, 4.14, 4.15, 4.16, 5.2, 5.4, 7.4, 7.5, 7.6, 22.5, 25.1, 25.2, 25.4, 25.9, 25.10; D-6_

  - [~] 8.3 Write the manager part of `supabase/tests/04_business_managers.test.sql`
    - Owner row on business create, `add_profile_manager` and `remove_profile_manager` by an owner, rejection for a manager, manager cannot delete the business, last owner cannot be removed, deleting the last owner's login deletes the business, a manager can edit the business profile
    - Run `supabase test db --linked`; commit migration and tests as `db(profiles): add profiles, profile managers and acts_as with rls`
    - Close out: DEVLOG entry, push
    - _Requirements: 5.7, 6.7, 7.3, 7.9, 7.10, 7.11, 7.12, 7.13, 25.2, 25.4_

- [~] 9. Migration 6: `create_business_details`
  - Apply through the Migration_Workflow: `business_details` with checks (phone, website `^https?://`, `private.opening_hours_valid`, address length), unique `profile_id`, trigram index on category, `business_details_guard`, RLS, grants; create `private.opening_hours_valid` with execute kept for `anon` and `authenticated` (pure validator)
  - Extend `04_business_managers.test.sql`: one row per business, rejection for a person profile, website and opening hours checks, public read by `anon`, writes only with `acts_as`, `anon` cannot write
  - Run `supabase test db --linked`; commit as `db(profiles): add business details table with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 25.1, 25.2, 25.4_

- [~] 10. Migration 7: `create_notifications`
  - Apply through the Migration_Workflow: `notifications` (actor on delete cascade, `data` object check, indexes), `private.notify` (execute revoked from public, anon, authenticated), RLS select and update for the recipient, UPDATE grant on `read_at` only, no insert or delete grant
  - Create `supabase/tests/12_signals.test.sql` with the table part: recipient can read and mark read, cannot change other fields, other users and `anon` cannot read, direct inserts rejected for `anon` and `authenticated`
  - Run `supabase test db --linked`; commit as `db(notifications): add notifications table and notify helper`
  - Close out: DEVLOG entry, push
  - _Requirements: 15.1, 15.2, 15.10, 15.11, 15.12, 15.13, 25.1, 25.2_

- [~] 11. Migration 8: `create_relationships`
  - Apply through the Migration_Workflow: `relationships` with checks, `relationships_pair_uq` on the unordered pair and type, indexes, RLS enabled with no policies and no grants; `relationships_guard_insert` and `relationships_guard_update`; notification triggers (`connection_request`, `new_follower`, `connection_accepted` only on a real pending to accepted change, nothing on decline); `private.is_connected`, `private.follows`, `private.in_audience`
  - Create `supabase/tests/05_relationships.test.sql` with the table part: each allowed and rejected shape inserted as the test owner (business to person, follow shape, connection shape, self, managed page), status set by the guard, duplicate pair rejected with `PT409`, immutable fields, `anon` and `authenticated` cannot select or write the table, notifications created by the triggers
  - Run `supabase test db --linked`; commit as `db(relationships): add relationships table with guards and notifications`
  - Close out: DEVLOG entry, push
  - _Requirements: 8.1, 8.2, 8.3, 8.6, 8.7, 8.8, 8.9, 8.10, 8.11, 8.12, 8.18, 8.20, 15.3, 15.4, 15.5, 15.6, 25.1, 25.4_

- [~] 12. Migration 9: `create_relationship_functions`
  - Apply through the Migration_Workflow: `request_relationship`, `respond_to_connection`, `remove_relationship`, `my_relationships` (declined reads as `pending` to its requester), `relationship_counts` (execute for `anon` and `authenticated`); the others for `authenticated` only
  - Extend `05_relationships.test.sql`: accept and decline only by the target, requester cannot respond, remove rules for accepted, follow, pending and declined, decline then re-ask by requester rejected with the same `PT409`, re-ask by the former target replaces the row, target deletes the decline then a new request works, `my_relationships` masking and `PT403` without `acts_as`, `relationship_counts` returns counts only
  - Run `supabase test db --linked`; commit as `db(relationships): add relationship rpc functions`
  - Close out: DEVLOG entry, push
  - _Requirements: 8.4, 8.5, 8.13, 8.14, 8.15, 8.16, 8.17, 8.18, 8.19, 8.21, 8.23, 8.24, 22.4, 25.2, 25.3_

- [~] 13. Migration 10: `create_circles`
  - Apply through the Migration_Workflow: `circles` (checks, `circles_owner_name_uq`, `circles_all_followers_uq`, label order index), `circle_members`, `circles_before_write`, `circles_before_delete`, `circle_members_guard`, `private.in_circle`, the all followers insert on `profiles_after_insert` (with a backfill for any existing business), the `relationships_after_delete` cleanup trigger, RLS and column grants (`is_all_followers` not writable by the API)
  - Create `supabase/tests/06_circles.test.sql`: switch default off, label pre-filled on first switch on, switch on with no label rejected, renaming keeps the label, switch off keeps the label, duplicate private name rejected case-insensitively, member must be a connection or follower, duplicate membership rejected, all followers circle created per business with fixed name and cannot be renamed, deleted or hand-filled, all followers on a person rejected, label switch on all followers allowed, cascade of members and links on delete, removing a relationship removes dependent memberships, non-owner and `anon` cannot read or write circles
  - Run `supabase test db --linked`; commit as `db(circles): add circles and circle members tables with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 8.22, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10, 9.12, 9.13, 9.14, 9.15, 9.16, 9.18, 10.1, 10.2, 10.6, 10.7, 10.8, 22.8, 25.1, 25.2, 25.4_

- [~] 14. Migration 11: `create_groups`
  - Apply through the Migration_Workflow: `groups` (SELECT grant without `circle_id`), `group_members`, `groups_guard`, `in_group`, `group_linked_circle`, RLS, grants
  - Create `supabase/tests/16_stretch.test.sql` with the groups part: members and owner read, others and `anon` cannot, writes need `acts_as` on the owner, linked circle must be the owner's and is readable only through `group_linked_circle` by the owner, one membership per group and profile
  - Run `supabase test db --linked`; commit as `db(kiro): add stretch groups tables with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 19.1, 19.2, 19.3, 19.7, 25.1, 25.2_

- [ ] 15. Migration 12: `create_content_vouches_and_can_view`
  - [~] 15.1 Write and apply the migration
    - Apply through the Migration_Workflow: `content_items` (checks, `private.content_details_valid` with the NQ-5 path kinds, one status index, indexes), `vouches` (default audience `public`, audience limited to public, connections, circles, deferrable `vouches_top8_uq`, trust index), `item_circles`
    - Triggers: `content_items_before_write` (default audience, story expiry, status replacement with `id <> new.id`, API callers cannot back-date or extend), deferred `content_items_circles_present` and `vouches_circles_present`, deferred `item_circles_last_link` (D-7), `item_circles_guard`, `vouches_guard_insert`, `vouches_guard_update`
    - `private.can_view` (the only visibility logic; `union all` branches for the two partial indexes) and `public.can_view` (only nulls an untrusted viewer id); RLS with the `seen(id)` shorthand; column grants without `audience` and `hidden_by_subject` (D-3)
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.8, 11.9, 11.10, 11.11, 11.12, 11.13, 11.14, 11.15, 11.16, 14.1, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 14.11, 14.12, 14.13, 14.14, 14.15, 14.17, 20.1, 20.2, 20.3, 20.4, 20.5, 20.6, 20.7, 20.8, 20.9, 20.10, 20.11, 20.12, 20.13, 20.14, 20.15, 22.4, 23.7; D-3, D-5, D-7_

  - [~] 15.2 Write `supabase/tests/07_content_can_view.test.sql`
    - Every `can_view` branch: owner (including expired), vouch subject (hidden or not), each audience, expiry, null viewer, non-existent id, parent visibility, untrusted viewer id treated as null; default audiences; writing always public; circles required at commit; `item_circles_last_link` cases (deleting the last link fails with `PT422 content.circles_required`, replacing links in one transaction passes, deleting the circle passes and leaves the item owner-only, deleting the item passes); status replacement and same-row upsert; gallery and story path kind checks; parent owner check; API caller cannot extend a story; `anon` cannot write; RLS reads of `content_items` and `vouches` filtered by `can_view`; `audience` and `hidden_by_subject` not readable by viewers
    - _Requirements: 11.4, 11.5, 11.6, 11.7, 11.8, 11.9, 11.10, 11.11, 11.12, 11.13, 11.15, 20.2, 20.3, 20.4, 20.5, 20.6, 20.7, 20.8, 20.10, 20.11, 20.12, 20.13, 20.15, 25.1, 25.2, 25.3, 25.4; D-3, D-7_

  - [~] 15.3 Write `supabase/tests/00_canary.test.sql`
    - As the test owner create persons A and B and a `connections` item owned by B; set claims with `sub` and `role` through `set_config(..., true)`; `ok(private.is_api_caller())` before the role switch; `set local role authenticated`; assert `current_user`, `auth.uid()`, and `is_empty` for B's item; `reset role` and repeat for `anon`; assert no USAGE on `private` for both roles; grant nothing on `private`
    - Run `supabase test db --linked`; commit migration and both test files as `db(content): add content items, vouches and can_view with rls`
    - Close out: DEVLOG entry, push
    - _Requirements: 25.9, 25.10, 25.11, 25.12; D-8, DR-1_

- [~] 16. Migration 13: `create_content_functions`
  - Apply through the Migration_Workflow: `create_content_item`, `create_vouch` (default audience `public`), `set_item_audience`, `item_audience`, `set_top8`, `my_received_vouches`, the `vouch_received` notification trigger; execute for `authenticated` only
  - Create `supabase/tests/08_vouches_top8.test.sql`: eligibility (connection same type, person following a business, business to person rejected, self, managed page, one vouch per pair), default audience `public`, circle links owned by the author, author-only edits and delete, subject-only hide, subject cannot edit or delete, `set_top8` limit, duplicates, non-author vouch, swaps in one call, `vouch_received` notification holds no vouch body, `my_received_vouches` needs `acts_as`, Search_Trust counting via `private.search_trust` is tested in task 22
  - Extend `07_content_can_view.test.sql`: `create_content_item` with circles creates links atomically, `set_item_audience` replaces links, `item_audience` returns nothing to a non-owner
  - Run `supabase test db --linked`; commit as `db(vouches): add content and vouch rpc functions`
  - Close out: DEVLOG entry, push
  - _Requirements: 11.7, 11.16, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 14.11, 14.12, 14.13, 14.14, 14.15, 14.16, 14.17, 14.18, 14.21, 14.23, 15.10, 25.2, 25.3, 25.4; NQ-2_

- [~] 17. Checkpoint: privacy core
  - Ensure all tests pass, ask the user if questions arise.
  - `supabase test db --linked` is green, including `00_canary.test.sql`, and the security advisor reports nothing.

- [~] 18. Migration 14: `create_story_views`
  - Apply through the Migration_Workflow: `story_views` with unique `(story_id, viewer_profile_id)`, `story_views_guard` (story items only), RLS (viewer or story owner reads; insert needs `acts_as` and `can_view`), grants
  - Extend `07_content_can_view.test.sql` with a story views section: one row per story and viewer with `on conflict do nothing`, rejection for a non-story item, rejection when `can_view` is false, owner reads views on their stories, others and `anon` cannot read or write
  - Run `supabase test db --linked`; commit as `db(stories): add story views table with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 25.1, 25.2, 25.4_

- [~] 19. Migration 15: `create_story_label`
  - Apply through the Migration_Workflow: `private.story_label` (execute revoked from public, anon, authenticated) and `public.story_label` (nulls an untrusted viewer; execute for `anon` and `authenticated`)
  - Create `supabase/tests/10_story_labels.test.sql`: no label for owner, invisible story, or non-circle audience (NQ-3); `member_label` only while the switch is on and only to members, first circle in Circle_Label_Order; `only_for_you` when no linked circle holds anyone else (including an empty linked circle, D-2); `shared_with_you` otherwise; all followers counted as current followers; switch off or removal takes effect at the next call; untrusted viewer id evaluates as null; no private name in any returned value
  - Run `supabase test db --linked`; commit as `db(stories): add story label function`
  - Close out: DEVLOG entry, push
  - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6, 13.7, 13.8, 13.9, 13.10, 13.11, 13.12, 13.13, 13.14, 25.3, 25.7; D-2, NQ-3_

- [ ] 20. Migration 16: `create_page_items_and_view_as`
  - [~] 20.1 Write and apply the migration
    - Apply through the Migration_Workflow: `private.page_items` (content, top8 hidden or not, received non-hidden; audience only for the owner; story label attached), `public.page_items` (execute for `anon` and `authenticated`), `public.view_as` (raises `PT403 view_as.not_owner`; execute for `authenticated` only, revoked from public and anon)
    - _Requirements: 14.19, 14.20, 21.1, 21.2, 21.3, 21.4, 21.5, 21.6, 21.7, 21.8; D-1_

  - [~] 20.2 Write `supabase/tests/11_view_as.test.sql`
    - Owner-only call; non-owner gets `PT403`; `anon` cannot execute; each simulated viewer (stranger, connection, circle member, follower, null) sees exactly the matching items; story label attached for the simulated viewer; no circle ids or names returned; `page_items` with an untrusted viewer id behaves as signed out
    - Extend `08_vouches_top8.test.sql`: a hidden vouch is absent from the subject's page listing, present in the author's Top 8 subject to `can_view`, and still readable by the subject
    - _Requirements: 14.19, 14.20, 14.21, 21.1, 21.2, 21.3, 21.5, 21.6, 21.7, 21.8, 25.3, 25.8_

  - [~] 20.3 Write `supabase/tests/09_circle_privacy.test.sql`
    - With a circle whose member label differs from its private name, a non-owner `authenticated` caller and `anon` cannot obtain the private name from `circles`, `circle_members`, `item_circles`, `groups`, `notifications`, `can_view`, `page_items`, `view_as`, `story_label`, `relationship_counts` or `my_relationships`; search is added in task 22
    - Run `supabase test db --linked`; commit migration and tests as `db(view-as): add page items and view as functions`
    - Close out: DEVLOG entry, push
    - _Requirements: 9.10, 9.11, 9.17, 13.10, 22.8, 25.6_

- [~] 21. Migration 17: `create_profile_views`
  - Apply through the Migration_Workflow: `profile_views` (unique per viewer, page and day, self check), `record_profile_view` (Nairobi day, rejects own and managed pages), the `profile_viewed` notification trigger on a new row only, RLS, SELECT grant only
  - Extend `12_signals.test.sql`: repeated views on one Nairobi day give one row and one notification, own and managed page rejected, `PT403` without `acts_as`, `anon` cannot execute or read, viewer and viewed can read, others cannot, notification data holds only allowed fields
  - Run `supabase test db --linked`; commit as `db(notifications): add profile views with daily dedup`
  - Close out: DEVLOG entry, push
  - _Requirements: 15.7, 15.10, 16.1, 16.2, 16.3, 16.4, 16.5, 25.1, 25.2_

- [ ] 22. Migration 18: `create_search`
  - [~] 22.1 Write and apply the migration
    - Apply through the Migration_Workflow: `search_appearances`, `search_appearance_marks` (no grants), `private.search_trust`, `private.record_search_appearances`, `search_directory` (fully qualified `operator(extensions.<%)` and `extensions.word_similarity`, `set pg_trgm.word_similarity_threshold = 0.3`, ranking `text_score * (1 + 0.15 * ln(1 + trust))`, tie-break by trust then handle, appearances recorded for exactly the returned page; execute for `anon` and `authenticated`)
    - _Requirements: 14.22, 16.6, 16.7, 16.8, 16.9, 16.10, 24.1, 24.2, 24.3, 24.4, 24.5, 24.6, 24.7, 24.8, 24.9, 24.10, 24.11; NQ-2, NQ-4, NQ-6_

  - [~] 22.2 Write `supabase/tests/14_search.test.sql`
    - Typo tolerance ("nutritonist" finds "nutritionist"), each searched field, type and city filters, page size bounds (`PT422 search.bad_page`), trust boost ordering and equal-relevance tie-break, short query returns nothing and records nothing, returned column set is public only, appearances once per signed-in searcher per day and every time for `anon`, untrusted searcher id counted as anonymous, `anon` cannot read `search_appearances`, owner can
    - Extend `08_vouches_top8.test.sql`: Search_Trust counts distinct authors with public featured vouches, hidden ones count, unfeatured and non-public ones do not
    - _Requirements: 14.22, 16.6, 16.7, 16.8, 16.9, 16.10, 24.2, 24.3, 24.5, 24.6, 24.7, 24.8, 24.9, 24.10, 25.3_

  - [~] 22.3 Extend `09_circle_privacy.test.sql` with `search_directory`
    - No private name or member label appears in any search result for a query equal to the private name
    - Run `supabase test db --linked`; commit migration and tests as `db(search): add directory search with trust ranking`
    - Close out: DEVLOG entry, push
    - _Requirements: 24.5, 25.6_

- [~] 23. Migration 19: `schedule_weekly_search_summary`
  - Apply through the Migration_Workflow: `private.send_weekly_search_summaries` (previous 7 Nairobi days, one notification per profile with a positive total), `notifications_weekly_uq`, `cron.schedule('pavio-weekly-search-summary', '0 5 * * 1', ...)`
  - Extend `12_signals.test.sql`: the function creates one notification per profile with appearances and none for zero, a re-run in the same week adds nothing, data holds only count and dates, the cron job exists with the expected schedule, `anon` and `authenticated` cannot execute the function
  - Run `supabase test db --linked`; commit as `db(notifications): schedule weekly search summary`
  - Close out: DEVLOG entry, push
  - _Requirements: 15.8, 15.9, 15.10, 16.10, 25.3_

- [~] 24. Checkpoint: signals and search
  - Ensure all tests pass, ask the user if questions arise.
  - `supabase test db --linked` is green and the security advisor reports nothing.

- [~] 25. Migration 20: `create_ai_usage`
  - Apply through the Migration_Workflow: `ai_usage` (acting profile on delete set null), `private.ai_under_limits`, `ai_can_call` (execute for `authenticated`), `ai_record_call` (execute revoked from public, anon, authenticated; granted to `service_role` only), RLS select for the owning user, no write grants
  - Create `supabase/tests/13_ai_lastfm.test.sql` with the AI part: daily limit, monthly cap, cost above `max_cost_per_call_usd` rejected with `PT422 ai.bad_cost`, `PT429 ai.limit_reached`, acting profile recorded, rejection when the user does not control the acting profile, `anon` and `authenticated` cannot execute `ai_record_call` and `service_role` can, users read only their own rows, direct writes rejected
  - Run `supabase test db --linked`; commit as `db(ai): add ai usage table and spend cap functions`
  - Close out: DEVLOG entry, push
  - _Requirements: 17.1, 17.3, 17.4, 17.5, 17.7, 17.8, 17.9, 22.11, 25.1, 25.13; D-4, DR-2_

- [~] 26. Migration 21: `create_lastfm_links`
  - Apply through the Migration_Workflow: `lastfm_links` (unique profile, username check), RLS for `acts_as` on the profile, grants
  - Extend `13_ai_lastfm.test.sql`: username format, one link per profile, owner read and write, others and `anon` cannot
  - Run `supabase test db --linked`; commit as `db(profiles): add lastfm links table with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 18.1, 18.2, 18.3, 25.1, 25.2_

- [~] 27. Migration 22: `create_chat_tables`
  - Apply through the Migration_Workflow: `conversations`, `conversation_members`, `messages` (sender on delete set null), `message_translations` (unique per message and language), `in_conversation`, RLS, grants
  - Extend `16_stretch.test.sql`: members read, others and `anon` cannot, message insert needs `acts_as` and membership, sender set to null when the profile is deleted, one translation per language, tables otherwise empty
  - Run `supabase test db --linked`; commit as `db(kiro): add stretch chat tables with rls`
  - Close out: DEVLOG entry, push
  - _Requirements: 5.8, 19.4, 19.5, 19.6, 19.7, 19.8, 25.1, 25.2_

- [~] 28. Migration 23: `create_storage_buckets`
  - Apply through the Migration_Workflow: `public-media` (public, 5 MB) and `private-media` (private, 10 MB) inserted with `on conflict do nothing`, `try_uuid`, `private.media_kind_allowed` (execute for `authenticated` only), the six storage policies with the NQ-5 path rules
  - Create `supabase/tests/15_storage.test.sql`: owner-folder upload allowed and other folders rejected, `gallery` path in `public-media` and `avatar` path in `private-media` rejected, private reads allowed only through a visible referencing item, `anon` cannot insert, update or delete, `public-media` is not listable by others, selecting a private object (the signed URL path) fails when `can_view` is false
  - Run `supabase test db --linked`; commit as `db(content): add storage buckets and policies`
  - Close out: DEVLOG entry, push
  - _Requirements: 23.1, 23.2, 23.3, 23.4, 23.5, 23.6, 23.7, 25.2; NQ-5, D-1_

- [~] 29. Complete the catalog-wide pgTAP tests
  - Complete `01_schema.test.sql` for every table: uuid primary key with `gen_random_uuid()`, `created_at`, `updated_at` trigger on changing tables, leading index on every foreign key column, RLS enabled on every `public` table, policy names follow `<table>_<role>_<action>`, `anon` holds no insert, update or delete privilege on any table
  - Complete `02_security_definer.test.sql`: every security definer function has `prosecdef` and `search_path=`; for every function in the authenticated-only row of the grants table (including `view_as`) `anon` and `public` lack execute; `ai_record_call` is `service_role` only; every non-validator `private.*` function is not executable by `anon` or `authenticated`
  - Run `supabase test db --linked` and the security advisor; any finding is fixed in a new `fix_<what>` migration through the Migration_Workflow
  - Commit as `test(kiro): add catalog wide schema and privilege tests`
  - Close out: DEVLOG entry, push
  - _Requirements: 3.5, 3.6, 3.8, 3.9, 3.11, 7.7, 13.13, 20.14, 21.7, 22.1, 22.2, 22.3, 22.5, 22.9, 25.1, 25.5, 25.13_

- [~] 30. Checkpoint: all migrations and pgTAP tests
  - Ensure all tests pass, ask the user if questions arise.
  - All 23 migrations are in `supabase/migrations/` with remote versions, all 17 pgTAP files pass, and the security advisor reports nothing.

- [ ] 31. Build the property test harness
  - [~] 31.1 Create `tests/property/runs.ts`
    - Export `PROPERTY_RUNS` read from the environment, default 25; throw an error naming `PROPERTY_RUNS` when it is set to anything other than a positive integer
    - Commit as `test(privacy): add property runs setting`
    - _Requirements: 26.17, 26.24; DR-3_

  - [~] 31.2 Create `tests/property/db.ts`
    - Load `.env.local` with `dotenv`; read only `SUPABASE_DB_URL` and throw a message naming it when absent
    - `withRolledBackTx(fn)`: open a client, `begin`, run `fn`, always `rollback` in `finally`
    - `readCanary` (reject any role but `authenticated` or `anon`, set `request.jwt.claims` with `{ sub, role }` through `set_config($1, true)` with a bound parameter, read `private.is_api_caller()` as the test owner), `checkCanary` (after `set local role`, assert `current_user`, `auth.uid()` and the captured value, else throw `CanaryError`), and `asUser` composing them; no grant on schema `private`
    - Commit as `test(privacy): add transaction and simulated user harness`
    - _Requirements: 2.4, 2.5, 26.2, 26.3, 26.20, 26.21, 26.23; D-8, DR-1_

  - [~] 31.3 Create `tests/property/arbitraries.ts`
    - fast-check generators for logins, person and business profiles, manager rows, relationships in legal and illegal shapes, circles with random private names, switches and member labels that differ from private names, memberships, content items and vouches with every audience, expired stories, and simulated viewers; plus fixture insert helpers that run as the test owner
    - Commit as `test(privacy): add property test generators`
    - _Requirements: 26.1_

  - [~] 31.4 Create `tests/property/canary.test.ts`
    - Examples: `authenticated` with a random `sub` passes; `anon` passes with null `auth.uid()`; `readCanary` with `service_role` claims captures false and `checkCanary` throws `CanaryError`; no USAGE on `private` for both roles; sanity test that B's `connections` item is invisible to stranger A through RLS and `can_view`
    - Run `npm run typecheck` and `npm run test:property`; commit as `test(privacy): add canary and sanity tests for simulated users`
    - Close out: DEVLOG entry, push
    - _Requirements: 26.20, 26.21, 26.22, 26.23; D-8, DR-1_

- [ ] 32. Visibility properties in `tests/property/visibility.property.test.ts`
  - [~] 32.1 Write property test for strangers and signed-out visitors
    - **Property 1: Strangers and signed-out visitors never see a non-public item**
    - **Validates: Requirements 20.1, 20.4, 20.5, 20.6, 20.7, 20.11, 22.4, 22.5**
    - Check `can_view` and RLS reads of `content_items`, `vouches`, `page_items` and `view_as`

  - [~] 32.2 Write property test for connections audience
    - **Property 2: Connections see connections items; non-connections never do**
    - **Validates: Requirements 20.6, 8.4, 8.6**

  - [~] 32.3 Write property test for circle audience
    - **Property 3: A circle item is visible to exactly the owner and members of a linked circle**
    - **Validates: Requirements 20.7, 20.2, 14.12, 10.3**

  - [~] 32.4 Write property test for expired stories
    - **Property 5: An expired story is visible only to its owner**
    - **Validates: Requirements 20.4, 20.2, 11.10**
    - Run `npm run test:property`; commit as `test(privacy): add visibility property tests`; close out: DEVLOG entry, push

- [ ] 33. Circle access properties in `tests/property/circle-access.property.test.ts`
  - [~] 33.1 Write property test for circle removal
    - **Property 4: Removing a member from a circle immediately removes access**
    - **Validates: Requirements 9.19, 8.22, 10.5**

  - [~] 33.2 Write property test for switching a member label off
    - **Property 12: Turning off a member-label switch stops the label at the next call**
    - **Validates: Requirements 13.11, 9.8**
    - Run `npm run test:property`; commit as `test(privacy): add circle access property tests`; close out: DEVLOG entry, push

- [ ] 34. View as property in `tests/property/view-as.property.test.ts`
  - [~] 34.1 Write property test for view_as
    - **Property 6: view_as never shows more than the simulated viewer could see**
    - **Validates: Requirements 21.1, 21.4, 21.5, 21.3, 20.15**
    - Run `npm run test:property`; commit as `test(view-as): add view as property test`; close out: DEVLOG entry, push

- [ ] 35. Relationship properties in `tests/property/relationships.property.test.ts`
  - [~] 35.1 Write property test for relationship shapes
    - **Property 7: A business can never start a relationship with a person**
    - **Validates: Requirements 8.7, 8.8, 8.9, 8.10, 8.11, 8.2, 8.3, 8.6**

  - [ ]* 35.2 Write property test for declined connections
    - **Property 15: A declined connection reads as pending to its requester and blocks re-requests**
    - **Validates: Requirements 8.19, 8.16, 8.12, 8.17, 8.18, 8.21**
    - Run `npm run test:property`; commit as `test(relationships): add relationship property tests`; close out: DEVLOG entry, push

- [ ] 36. Top 8 property in `tests/property/top8.property.test.ts`
  - [~] 36.1 Write property test for the Top 8 limit
    - **Property 8: No author ever has more than 8 featured vouches, each at a distinct position**
    - **Validates: Requirements 14.16, 14.17, 14.18**
    - Run `npm run test:property`; commit as `test(vouches): add top 8 property test`; close out: DEVLOG entry, push

- [ ] 37. Search properties in `tests/property/search.property.test.ts`
  - [~] 37.1 Write property test for public-only search results
    - **Property 9: Search returns only public fields and public items**
    - **Validates: Requirements 24.5, 24.2, 22.4**

  - [ ]* 37.2 Write property test for search appearance counting
    - **Property 20: Search appearances count signed in searchers once per day and anonymous searches every time**
    - **Validates: Requirements 16.6, 16.7, 16.8, 24.8, 24.10**

  - [ ]* 37.3 Write property test for Search_Trust and ranking
    - **Property 21: Search_Trust counts public featured vouches by distinct authors and orders ranking**
    - **Validates: Requirements 14.22, 24.6, 24.7**
    - Run `npm run test:property`; commit as `test(search): add search property tests`; close out: DEVLOG entry, push

- [ ] 38. Circle privacy property in `tests/property/circle-privacy.property.test.ts`
  - [~] 38.1 Write property test for circle private names
    - **Property 10: A circle private name never reaches a non-owner**
    - **Validates: Requirements 9.10, 9.11, 9.17, 22.8, 13.10**
    - Read every granted surface listed in the property as the non-owner and as `anon`
    - Run `npm run test:property`; commit as `test(privacy): add circle private name property test`; close out: DEVLOG entry, push

- [ ] 39. Story label property in `tests/property/story-label.property.test.ts`
  - [~] 39.1 Write property test for story labels
    - **Property 11: The story label follows the member-label rules and reveals nothing else**
    - **Validates: Requirements 13.4, 13.5, 13.6, 13.1, 13.9, 13.10, 13.8**
    - Run `npm run test:property`; commit as `test(stories): add story label property test`; close out: DEVLOG entry, push

- [ ] 40. Acting properties in `tests/property/acts-as.property.test.ts`
  - [ ]* 40.1 Write property test for acts_as
    - **Property 13: acts_as equals the ownership model**
    - **Validates: Requirements 7.4, 7.5, 7.6**

  - [ ]* 40.2 Write property test for acting on writes
    - **Property 14: Every profile-owned write requires acts_as on the acting profile**
    - **Validates: Requirements 22.6, 7.8, 11.16, 9.9, 14.11, 18.2**
    - Run `npm run test:property`; commit as `test(profiles): add acts as property tests`; close out: DEVLOG entry, push

- [ ] 41. Profile properties in `tests/property/profiles.property.test.ts`
  - [ ]* 41.1 Write property test for tag normalisation
    - **Property 16: Tag normalisation and limits**
    - **Validates: Requirements 4.13**

  - [ ]* 41.2 Write property test for handle validation
    - **Property 17: Handle validation stores the handle exactly as given**
    - **Validates: Requirements 4.2, 4.3, 4.4, 4.5, 4.6**
    - Run `npm run test:property`; commit as `test(profiles): add profile property tests`; close out: DEVLOG entry, push

- [ ] 42. Signal properties in `tests/property/signals.property.test.ts`
  - [ ]* 42.1 Write property test for notification content
    - **Property 18: Notifications never carry restricted content**
    - **Validates: Requirements 15.10, 15.14, 15.3, 15.4, 15.6, 15.7, 14.23**

  - [ ]* 42.2 Write property test for profile view dedup
    - **Property 19: Profile views deduplicate per viewer, page and Nairobi day**
    - **Validates: Requirements 16.2, 16.3, 16.4, 15.7**
    - Run `npm run test:property`; commit as `test(notifications): add signal property tests`; close out: DEVLOG entry, push

- [~] 43. Checkpoint: property suite
  - Ensure all tests pass, ask the user if questions arise.
  - `npm run typecheck` and `npm run test:property` pass with zero failures; any shrunk counterexample found so far is kept as a regression test and noted in `DEVLOG.md` (Req 26.18).

- [ ] 44. Build the demo seed in `supabase/seed/`
  - [~] 44.1 Create `supabase/seed/cast.ts`
    - Typed constants for the invented cast in the design's **Seed Design**: five people with tags and statuses, Kahawa Corner (owner Brian, manager Wanjiru) and Shamba Fresh Supplies (owner Otieno) with business details, relationships, circles with switches and member labels, content items (public writing, connections and circle gallery photos, active circle story, expired public story, business all-followers story), the seven vouches with audiences, Top 8 positions and the hidden one; a fixed uuid for every row except the automatic all followers circles; emails on `demo.pavio.world`
    - Commit as `feat(seed): add demo cast data`
    - _Requirements: 27.1, 27.2, 27.3, 27.4, 27.5, 27.6, 27.7_

  - [~] 44.2 Create `supabase/seed/seed.ts`
    - Load `.env.local`; require `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `SUPABASE_DB_URL` with named errors; target guard on `tmglpalznmyonaynojyy` in both URLs before any write
    - Create missing auth users with `auth.admin.listUsers` and `auth.admin.createUser({ email_confirm: true, user_metadata: { demo: true } })` using the secret key (only allowed here)
    - Write data in one `pg` transaction as `postgres` using the idempotence rules in the design: upserts by fixed id, `where not exists` for relationships, memberships and links, accept with `status = 'pending'` guard, separate hide update, story `created_at` refresh and the 30-hour-old expired story; print the fingerprint
    - Add `seed` and `seed:verify` scripts to `package.json`; run `npm run typecheck`; commit as `feat(seed): add idempotent demo seed script`
    - _Requirements: 27.8, 27.9, 27.10, 27.11, 22.10_

  - [~] 44.3 Create `supabase/seed/verify.ts` and `supabase/seed/README.md`
    - `verify.ts` runs the seed twice and fails unless both fingerprints (row counts, cast notification count, md5 over seeded columns excluding story times) are equal
    - `README.md` explains how to run it and what it creates
    - Run `npm run seed:verify` against `pavio`; confirm Amina's Search_Trust is 2; record the result in `DEVLOG.md`; commit as `feat(seed): add seed run-twice check`
    - Close out: DEVLOG entry, push
    - _Requirements: 27.9_

- [~] 45. Add performance checks on the seeded database
  - Extend `07_content_can_view.test.sql` with a timed loop of `can_view` on a seeded row asserting p95 under 5 ms, and `14_search.test.sql` with a timed loop of `search_directory` asserting p95 under 200 ms
  - Run `supabase test db --linked`; commit as `test(search): add can_view and search latency checks`
  - Close out: DEVLOG entry, push
  - _Requirements: 20.16, 24.12_

- [ ] 46. Final verification
  - [~] 46.1 Run every suite and check the database
    - `supabase test db --linked` passes with zero failures; `npm run typecheck` and `npm run test:property` pass
    - MCP `get_advisors` security reports nothing; performance "unused index" notices are listed for the PR notes
    - Search the repository for the secret key variable and confirm it appears only in `supabase/seed/`; confirm no `.env` file, build, coverage or log output is tracked
    - _Requirements: 22.9, 22.10, 25.11, 26.19, 28.10_

  - [~] 46.2 Time the property suite at both run counts
    - Run `npm run test:property` with the default (25) and once with `PROPERTY_RUNS=100`; record both run times in `DEVLOG.md`
    - Commit as `docs(kiro): record property suite run times`; push
    - _Requirements: 26.17, 28.5, 28.11; DR-3_

- [ ] 47. Privacy review and pull request
  - [~] 47.1 Run the privacy-reviewer agent
    - Review every migration, policy, SQL function, the seed and the test harness; fix every Critical and High finding (schema fixes as new `fix_<what>` migrations through the Migration_Workflow, each with its test), rerun all suites, and keep the report for the PR
    - _Requirements: 28.8, 3.6_

  - [~] 47.2 Open the pull request and stop
    - Open `Spec 00: Database foundation` from `spec/00-database-foundation` into `main` with `gh pr create`, using the headings Summary, Spec (link to `.kiro/specs/00-database-foundation/`), Tasks completed, Database changes (migrations, policies, functions, advisor results), Tests (every suite with results), Reviews (privacy-reviewer report; no UI so no design review), Notes (decisions, type generation deferred to Spec 01, unused index notices)
    - Stop and ask Dominic to review and merge with a merge commit; do not merge
    - _Requirements: 28.8, 28.9_

## Notes

- **Migration_Workflow** (supabase.md) for every migration task: write the SQL; apply it to `pavio` (ref `tmglpalznmyonaynojyy`) with MCP `apply_migration` using the snake_case name from the design's Migration Plan, never to any other project; run `supabase migration fetch --yes`; run MCP `get_advisors` for security and performance and fix every security finding in a new `fix_<what>` migration before the next migration; never edit an applied migration; no `drop`, `truncate` or unscoped `delete` of existing data.
- **Type generation is deferred.** Req 3.4 and supabase.md ask for `supabase gen types typescript --linked > src/lib/supabase/types.ts` after each migration. There is no app in this spec, so types are generated in Spec 01; record this in the PR notes.
- **Function grants:** each function migration runs `revoke execute on function <signature> from public` (and from `anon`, `authenticated` when not meant for them) before any `grant`, because `create or replace` keeps old ACLs and new functions default to PUBLIC execute.
- **pgTAP conventions:** each file is `begin; select plan(n); ... select * from finish(); rollback;`; users are simulated with `set_config('request.jwt.claims', json_build_object('sub', ..., 'role', ...)::text, true)` then `set local role`, in the order of `00_canary.test.sql`.
- **Close-out for every task:** add a dated entry to `DEVLOG.md` (spec task, what was built, any decision or problem; the build-diary hook may add it, then check it); make atomic Conventional Commits per git.md, staging each path explicitly and checking `git status` and `git diff --staged` first (a migration may share a commit with its pgTAP test; DEVLOG entries go in a separate `docs(kiro)` commit); push `spec/00-database-foundation`. Never commit to `main`, never force push, never commit `.env` files.
- Property tests 1 to 12 are required. Tasks marked with `*` (Properties 13 to 21) are optional and can be skipped for a faster MVP; the same behaviour is also covered by the pgTAP files.
- Each property test uses `{ numRuns: PROPERTY_RUNS }` from `tests/property/runs.ts`, carries the comment `// Feature: 00-database-foundation, Property N: <property text>`, inserts fixtures as the test owner, switches with `asUser` before every assertion, and runs inside `withRolledBackTx`.
- A shrunk counterexample from a failing property becomes a regular regression test and a `DEVLOG.md` note (Req 26.18). Never weaken a failing test.
- Tasks run sequentially because they share one hosted database, one git branch and `DEVLOG.md`.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["2.1"] },
    { "id": 4, "tasks": ["2.2"] },
    { "id": 5, "tasks": ["2.3"] },
    { "id": 6, "tasks": ["3"] },
    { "id": 7, "tasks": ["4"] },
    { "id": 8, "tasks": ["5"] },
    { "id": 9, "tasks": ["6"] },
    { "id": 10, "tasks": ["7"] },
    { "id": 11, "tasks": ["8.1"] },
    { "id": 12, "tasks": ["8.2"] },
    { "id": 13, "tasks": ["8.3"] },
    { "id": 14, "tasks": ["9"] },
    { "id": 15, "tasks": ["10"] },
    { "id": 16, "tasks": ["11"] },
    { "id": 17, "tasks": ["12"] },
    { "id": 18, "tasks": ["13"] },
    { "id": 19, "tasks": ["14"] },
    { "id": 20, "tasks": ["15.1"] },
    { "id": 21, "tasks": ["15.2"] },
    { "id": 22, "tasks": ["15.3"] },
    { "id": 23, "tasks": ["16"] },
    { "id": 24, "tasks": ["17"] },
    { "id": 25, "tasks": ["18"] },
    { "id": 26, "tasks": ["19"] },
    { "id": 27, "tasks": ["20.1"] },
    { "id": 28, "tasks": ["20.2"] },
    { "id": 29, "tasks": ["20.3"] },
    { "id": 30, "tasks": ["21"] },
    { "id": 31, "tasks": ["22.1"] },
    { "id": 32, "tasks": ["22.2"] },
    { "id": 33, "tasks": ["22.3"] },
    { "id": 34, "tasks": ["23"] },
    { "id": 35, "tasks": ["24"] },
    { "id": 36, "tasks": ["25"] },
    { "id": 37, "tasks": ["26"] },
    { "id": 38, "tasks": ["27"] },
    { "id": 39, "tasks": ["28"] },
    { "id": 40, "tasks": ["29"] },
    { "id": 41, "tasks": ["30"] },
    { "id": 42, "tasks": ["31.1"] },
    { "id": 43, "tasks": ["31.2"] },
    { "id": 44, "tasks": ["31.3"] },
    { "id": 45, "tasks": ["31.4"] },
    { "id": 46, "tasks": ["32.1"] },
    { "id": 47, "tasks": ["32.2"] },
    { "id": 48, "tasks": ["32.3"] },
    { "id": 49, "tasks": ["32.4"] },
    { "id": 50, "tasks": ["33.1"] },
    { "id": 51, "tasks": ["33.2"] },
    { "id": 52, "tasks": ["34.1"] },
    { "id": 53, "tasks": ["35.1"] },
    { "id": 54, "tasks": ["35.2"] },
    { "id": 55, "tasks": ["36.1"] },
    { "id": 56, "tasks": ["37.1"] },
    { "id": 57, "tasks": ["37.2"] },
    { "id": 58, "tasks": ["37.3"] },
    { "id": 59, "tasks": ["38.1"] },
    { "id": 60, "tasks": ["39.1"] },
    { "id": 61, "tasks": ["40.1"] },
    { "id": 62, "tasks": ["40.2"] },
    { "id": 63, "tasks": ["41.1"] },
    { "id": 64, "tasks": ["41.2"] },
    { "id": 65, "tasks": ["42.1"] },
    { "id": 66, "tasks": ["42.2"] },
    { "id": 67, "tasks": ["43"] },
    { "id": 68, "tasks": ["44.1"] },
    { "id": 69, "tasks": ["44.2"] },
    { "id": 70, "tasks": ["44.3"] },
    { "id": 71, "tasks": ["45"] },
    { "id": 72, "tasks": ["46.1"] },
    { "id": 73, "tasks": ["46.2"] },
    { "id": 74, "tasks": ["47.1"] },
    { "id": 75, "tasks": ["47.2"] }
  ]
}
```
