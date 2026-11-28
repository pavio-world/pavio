# Future features

Features we agreed are worth building but left out of the current specs. Each entry says what it is, why it matters, and what it would change, so a later spec can pick it up without starting from scratch.

## Blogging

Blog posts are `writing` items in `content_items`. Their title, body and optional cover image live in `details`, and they are always public. The three features below build on that.

### Drafts

**What:** A post can be saved without being published. A draft is visible only to its owner. It does not appear on the profile page, in `view_as`, in `page_items` or anywhere else until the owner presses Publish. A published post can be unpublished, which turns it back into a draft without deleting it.

**Why:** Without drafts, every save is public at once, so a half written post is visible to anyone who opens the page. People who blog expect to write over several sittings.

**Database change:**
* Add `published_at timestamptz` to writing items: either a nullable column on `content_items` that is only used by writing, or a `published_at` field in `details`. A column is easier to index and to check.
* A check that only `writing` items may have a `published_at`.
* One new rule in `private.can_view`: a writing item with no `published_at` is visible only to its owner. The owner rule already comes first, so only the other viewers change.
* An RPC or a granted column so the owner can publish and unpublish.

**Tests:** a draft is invisible to a connection, a circle member, a stranger and a signed out visitor; it becomes public on publish; it disappears again on unpublish; `view_as` never shows a draft.

### Slugs

**What:** A readable address for each post, such as `pavio.world/amina/five-kenyan-breakfasts`, instead of `pavio.world/p/<id>`.

**Why:** Readable links are easier to share and look better in link previews and search results.

**Database change:**
* A `slug` for writing items, as a column or a field in `details`.
* Format check: lowercase letters, numbers and single hyphens between words, up to about 80 characters.
* Unique per owner, so two people can each have `my-first-post`.
* Generated from the title when the post is first published. After that it stays fixed unless the owner changes it, so shared links keep working.
* Optional later: keep old slugs so a renamed post still opens from its old link.

**Tests:** format rules; the same slug is rejected twice for one owner and allowed for two owners; the slug is not exposed for a draft to anyone but the owner.

### Tags

**What:** Topic tags on a blog post, such as `nutrition`, `breakfast`, `fintech`, so readers can see what a post is about and find other posts on the same topic.

**Why:** Tags make an owner's posts browsable and give a later post search something to work with. They follow the same idea as the profile's "what I do" tags.

**Database change:**
* A `tags text[]` on writing items, as a field in `details` or a column, reusing `private.tags_valid` (lowercase, trimmed, at most 20 tags, each 1 to 40 characters) and the same normalisation as `profiles.what_i_do`.
* A GIN index if posts are ever searched or listed by tag.

**Tests:** normalisation (case, spaces, duplicates); limits; a draft's tags are never visible to anyone but the owner.

## Where these fit

All three are small, and they touch only writing items. They fit best in the spec that builds the blog screens (the post list on the profile page, the post page and the editor), done as one migration with its pgTAP tests.

If blogging grows further (comments, post search, series), consider moving writing to its own side table, `writing_posts`, with real columns, linked one to one to `content_items`. That keeps `can_view` and circle links in one place while giving blog posts proper columns.
