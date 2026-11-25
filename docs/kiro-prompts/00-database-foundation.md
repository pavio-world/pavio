# Prompt for Kiro: Spec 00, Database Foundation

> **Historical prompt.** This is the prompt as it was given to Kiro for spec `00-database-foundation`

---

Create a feature spec named `00-database-foundation` for Pavio. Read every file in `.kiro/steering/` first; product.md and privacy.md are the source of truth.

We are building database first. This spec designs and builds the complete Supabase database for every Pavio feature, including features that will be built later, so later specs only add logic and UI. It also builds the privacy engine and proves it with tests. Do not build any user interface in this spec.

## Scope of this spec

1. Set up the Supabase folder (`supabase init`) and link it to our **remote** dev project with `supabase link` (there is no local database; follow the remote rules in supabase.md). Enable the `pgtap` extension on the dev project. Add the minimal Node tooling needed to run property based tests (Vitest, fast-check and a Postgres client). The Next.js app itself is scaffolded in Spec 01, so do not create it yet.
2. Design the full schema and write it as SQL migrations.
3. Build the privacy engine: `acts_as`, `can_view`, and a `view_as` function for page owners.
4. Enable Row Level Security with explicit policies on every table.
5. Build public directory search.
6. Write pgTAP tests and property based tests that prove the privacy rules.
7. Seed believable demo data.

## Data the schema must support

**Identity**
* Profiles of type person or business, with a unique handle, display name, bio, avatar and cover images, city and country, preferred language (en or sw for now, open to more), dot colour key, page theme settings, 2006 mode preference, and "what I do" tags that drive search.
* Business details: category, phone, website, opening hours, address.
* Each signed in user owns exactly one person profile and can manage several business profiles (owner and manager roles). All writes happen as a profile (acting as), never only as a login.

**Relationships** (one table with a type and a status)
* Connection between two people: request, then accept, mutual.
* Connection between two businesses: request, then accept, mutual.
* Follow from a person to a business: instant, one way.
* A business can never start a relationship with a person. Nobody can relate to themselves or to a page they manage. Support declining and removing.

**Circles**
* Unlimited custom circles per profile with free names. Members must be accepted connections, or followers for businesses. One person can be in many circles. Membership is private and silent.
* Every business has a built in "all followers" audience that updates automatically.

**Content** (one table for all page items, with a type and a flexible details field)
* Types: writing (blog post), gallery photo, status, story, vouch. Leave room for more types without schema change.
* Every item has an audience: public, connections, circles (one or more, through a link table) or group.
* New items default to connections. Writing is always public.
* Fields for expiry (stories: 24 hours), parent (for albums or replies later) and group (later).
* Status: the current status line, kept until changed.
* Vouches: a vouch is written by one profile about another; it shows on the subject's page. Every vouch is kept; the author can feature up to 8 (Top 8) with an order, and swap them at any time. Only featured vouches count toward search ranking. Decide in the design whether vouches live in the content table or their own table, as long as visibility still goes through `can_view`, and record the decision in `docs/decisions/`.
* Story views, so a viewer's story ring can show "seen".

**Signals**
* Notifications: connection request, connection accepted, new follower, vouch received, profile viewed, weekly search appearances. Notifications must never leak restricted content.
* Profile views (signed in viewers only) and daily search appearance counts.

**AI and integrations**
* AI usage per profile per day and a global monthly spend cap setting.
* A connected Last.fm username per profile (activity is built last).

**Stretch tables, created now and left unused**
* Groups and group members, with an optional linked circle so a group can become a circle.
* Conversations, conversation members, messages with the language they were written in, and message translations (one row per message per language).

## Privacy engine

* `acts_as(profile_id)`: true only if the signed in user owns or manages that profile.
* `can_view(item_id, viewer_profile_id)`: the only place visibility is decided. Rules are in privacy.md section 4. Signed out visitors are a viewer with no profile and see only public items.
* `view_as(owner_profile_id, simulated_viewer)`: lets a page owner list their own items exactly as a given connection, circle member, follower or stranger would see them. Only the owner of that page may call it.
* RLS policies on every table use these functions. Revoke grants that are not needed.

## Search

A public directory search over people and businesses by name, "what I do" tags, category and city, with typo tolerance. It reads only public data, never restricted items, and ranks results by text relevance boosted by the number of featured vouches. Record a search appearance for each profile returned.

## Tests (required before the spec is complete)

pgTAP tests in `supabase/tests/` for every table and policy, proving that unauthorised roles cannot read or write.

Property based tests in `tests/property/` (fast-check, against the remote dev project through `SUPABASE_DB_URL`, each run inside a transaction that is rolled back so no data is left behind) for at least these properties:
1. A stranger or signed out visitor never sees a non public item.
2. A connection sees connections items; a non connection never does.
3. A circle item is visible only to members of at least one of its circles, and to the owner.
4. Removing someone from a circle immediately removes their access to that circle's items.
5. An expired story is visible only to its owner.
6. `view_as` never returns an item the simulated viewer could not see through `can_view`.
7. A business can never create a relationship with a person.
8. No profile can have more than 8 featured vouches.
9. Search never returns a field or item that is not public.

## Seed data

Invented people and businesses only, enough for the demo: a nutritionist (Amina), a founder (Brian), a photographer, two more people, a cafe and a supplier business. Include connections, follows, several circles ("family", "the cabal", "close friends"), items with every audience type, an active story shared to one circle, an expired story, featured and unfeatured vouches, and a status for each person. Seeding may use the secret key, only in `supabase/seed/`.

## How I want the spec written

* Requirements in EARS format, grouped by area above, each with acceptance criteria.
* Run Analyze Requirements and resolve ambiguities with me before the design.
* Design: an entity relationship diagram (Mermaid), every table with columns, keys and indexes, every function with its logic, every policy, and the correctness properties linked to the requirements they validate.
* Tasks: small, ordered, each ending with passing tests; migrations first, then functions, then policies, then tests, then seed.
* Follow the build diary and commit rules in structure.md.
