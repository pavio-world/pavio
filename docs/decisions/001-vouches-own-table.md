# 001: Store vouches in their own table

Date: 25 November 2026

Spec: 00-database-foundation (Requirement 14.2, 14.3)

## Context

A vouch is written by an author about a subject. Unlike gallery photos, statuses or stories, it has two parties with different rights. The author writes the text, sets the audience, edits or deletes it, and features it in their Top 8. The subject can only hide it from their own page. Each author may feature at most 8 vouches, and the swap of featured vouches must happen in one transaction without tripping a uniqueness check halfway.

Every other content item lives in `content_items`, and visibility for all of them is decided by one function, `can_view(item_id, viewer_profile_id)`. Requirement 14.2 asks us to choose between `content_items` and a separate table, and Requirement 14.3 says every read of a vouch must still go through `can_view`.

## Decision

Vouches get their own table, `public.vouches`, with `author_profile_id`, `subject_profile_id`, `body`, `audience` (`public`, `connections` or `circles`, default `public`), `top8_position` (null or 1 to 8), `hidden_by_subject` and timestamps. A deferrable unique constraint on `(author_profile_id, top8_position)` enforces the Top 8, and a unique constraint on `(author_profile_id, subject_profile_id)` allows one vouch per author and subject.

Vouch ids are uuids from the same space as `content_items` ids (both use `gen_random_uuid()`, where a collision is practically impossible), so an id names exactly one item. `can_view` looks the id up in `content_items` first and then in `vouches`, treats the author as the owner, and lets the subject always see a vouch about them. `item_circles` links circles to either a content item or a vouch, with a check that exactly one of the two is set.

## Consequences

- `content_items` stays free of vouch only columns and column rules, and the vouch guards (self vouch, managed page, business to person, eligibility, author only and subject only updates) sit on one table.
- There is still one visibility check. No second visibility function exists, and policies on `vouches` call `can_view` like every other content policy.
- `can_view` does up to two primary key lookups per item instead of one. Both are indexed, so the cost is small.
- `item_circles` has two nullable foreign keys and two partial indexes instead of one foreign key, and the last circle link trigger has to handle both kinds of item.
- Queries that list a page's items (`page_items`) must union content items and vouches.
- `notifications.reference_id` can point at a vouch or another row, so it has no foreign key.
