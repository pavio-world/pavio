---
inclusion: always
---

# Pavio: privacy rules (non negotiable)

Privacy is Pavio's core promise. A leak of a circle only story is the worst possible bug. These rules override convenience.

## 1. Enforced in the database

- **Row Level Security is enabled on every table**, with explicit policies. No table is exposed without policies.
- Revoke default grants that policies do not need. Write policies for the `anon` and `authenticated` roles.
- Application code must never be the only thing protecting data.

## 2. One visibility check

- A single SQL function decides whether a viewer can see a content item: `can_view(item_id, viewer_profile_id)`.
- Every policy on content, and every query that lists content, uses it. Never re implement visibility logic in TypeScript or in a second SQL function.
- **View as** calls the same logic with a stand in viewer, through a security definer function that only the page owner can call for their own page.

## 3. Acting as

- Every rule checks the **profile being acted as**, never only `auth.uid()`.
- A helper such as `acts_as(profile_id)` returns true only if the signed in user owns or manages that profile. Use it everywhere a write happens.

## 4. Audiences

- `public`: anyone, including signed out visitors and search.
- `connections`: accepted connections of the owner (and, for businesses, followers).
- `circles`: members of at least one of the item's chosen circles.
- `group`: members of the item's group (stretch).
- The owner always sees their own items.
- Expired items (stories past `expires_at`) are visible to nobody except the owner.
- **Writing is always public.** Search only ever reads public data.

## 5. Silence

- Never reveal circle membership to the people in it. A viewer of a story sees the circle label only because they are in that circle.
- Never reveal who else can see an item.
- Notifications must not leak private items (a "vouched for you" notice is fine; a preview of a circle only story sent to someone outside the circle is not).

## 6. Secret key

- The Supabase secret key (service role) **bypasses RLS**. It may only be used in `src/lib/supabase/admin.ts` and `supabase/seed/`.
- Any server code acting for a user uses a client created from that user's session.
- A Kiro hook blocks writes that add the secret key anywhere else.

## 7. Proof

- Every policy and the `can_view` function have pgTAP tests in `supabase/tests/`.
- The visibility rules also have property based tests (fast-check) with properties such as:
  - a stranger never sees a non public item
  - removing a person from a circle immediately removes their access to that circle's items
  - an expired story is visible only to its owner
  - view as never shows the owner more than the simulated viewer could see
  - a business can never create a relationship with a person
- A change that touches policies, `can_view` or relationships is not done until these tests pass.

## 8. AI and third parties

- Only send the minimum data needed to an AI provider. Never send private content to build a theme.
- Translated chat (stretch) must tell users that messages pass through an AI provider and allow turning translation off.
