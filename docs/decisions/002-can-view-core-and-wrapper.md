# 002: Keep visibility in one private core with a thin public wrapper

Date: 25 November 2026

Spec: 00-database-foundation (Requirement 20.1, 20.15, 21.4, 28.7)

## Context

Every content item and vouch has an audience, and Pavio's worst possible bug is a circle only story reaching someone outside the circle. Requirement 20.1 says one SQL function, `can_view(item_id, viewer_profile_id)`, is the only place that decides whether a viewer can see an item. RLS policies, page listings, storage reads and `view_as` all need that answer.

Two needs pull against each other. `view_as` must evaluate the page for a viewer who is not the caller: a connection, a circle member, a follower or a stranger. But the API must not let a signed in user ask `can_view` about someone else's profile id, because the answer would reveal that profile's access, and with it circle membership (Requirement 20.15). A single public function that trusts its viewer argument would allow that probing. Splitting the rule into a trusted and an untrusted copy would put the visibility logic in two places.

## Decision

All visibility logic lives in one function body, `private.can_view(p_item_id, p_viewer)`. It resolves the item (content item first, then vouch), lets the owner and a vouch subject see it, hides expired items from everyone else, requires a visible parent, and then checks the audience. It is a stable security definer function with `search_path = ''`, and execute is revoked from `public`, `anon` and `authenticated`, so the API cannot call it directly.

`public.can_view(p_item_id, p_viewer_profile_id)` is the function the API and RLS policies call. It contains no visibility logic. When the caller is an API caller (`private.is_api_caller()`, meaning the JWT role is `anon` or `authenticated`) and `public.acts_as(p_viewer_profile_id)` is false, it replaces the viewer id with null and calls the core. Otherwise it passes the viewer through. An untrusted viewer id therefore gets exactly the signed out answer: true only for non expired public items. Callers without API claims (`postgres` in tests, the seed, `pg_cron`) are trusted.

`private.page_items(owner, viewer)` lists a page (own content, own Top 8, received vouches that are not hidden) and filters every row through `private.can_view`. `public.page_items` nulls an untrusted viewer the same way as `public.can_view`. `public.view_as(owner, simulated_viewer)` first checks `public.acts_as(owner)` and raises `PT403 view_as.not_owner` if the caller does not own the page. It then calls `private.page_items` with the simulated viewer unchanged. That is the one place a caller may evaluate as another profile, and only for rows of their own page. `view_as` has no visibility logic of its own (Requirement 21.4).

## Consequences

- The visibility rule exists once. A fix to `private.can_view` applies at once to RLS, page listings, storage and `view_as`, and there is no second copy to drift.
- A signed in user cannot learn another profile's access by passing that profile's id. The wrong id silently becomes a null viewer, so the call reveals nothing beyond what is public, and it raises no error that could itself leak information.
- `view_as` can never show the owner more than the simulated viewer could see, because every row it returns passed the same core check with that viewer (Property 6).
- The core is security definer so it can read relationships, circles and group members that RLS hides from the caller. Its safety depends on the revoked execute grant and on the wrappers being the only public entry points. pgTAP checks both the grants and the definer settings.
- Each public call pays for an `is_api_caller` check and, when a viewer is given, an `acts_as` lookup before the core runs. Both are small indexed lookups.
- Anyone adding a new read path must call `public.can_view` or `private.can_view`, never write a new audience check. The privacy reviewer looks for this.
