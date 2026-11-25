---
inclusion: always
---

# Pavio: product

**Pavio. Your place in the world.** (pavio.world)

Pavio brings back two dead technologies for today:

1. **MySpace style personal pages.** Every person has one page that holds everything about them.
2. **The Yellow Pages.** A public directory where you find people and businesses by what they do (founders, nutritionists, plumbers, investors), something Instagram and TikTok cannot do.

Positioning: **connections, not feeds.** There is no feed. People come back because of notifications (who viewed you, who vouched for you, how often you appeared in search).

The core idea: **one page, many faces.** Your page shows a different face depending on who is looking, controlled by circles. Pavio is built for everyone, not one niche.

Hackathon: Kiroween 2026, Resurrection category. Deadline 4 December 2026, 2:00 pm Pacific (1:00 am 5 December, Nairobi). Every decision should favour a complete, polished, working product over breadth.

## Profiles

- One `profiles` table with a type: `person` or `business`. Businesses have extra details in `business_details`.
- A person can manage one or more business pages ("acting as"). Every action is performed **as a profile**, never as a login.
- You can never vouch for, connect with, or follow a page you manage yourself.

## Relationships

| Type | Between | Flow |
|---|---|---|
| connection | person and person | request, then accept (mutual) |
| connection | business and business | request, then accept (mutual), for suppliers and partners |
| follow | person to business | instant, one way |

A business can **never** start a relationship with a person. All relationships live in one `relationships` table with a type and a status.

## Circles

- Circles are unlimited, private and silent. Nobody is ever told which circles they are in.
- Only accepted connections (and, for businesses, followers) can be placed in circles. The owner assigns people; people never choose.
- One person can be in many circles. Circles have free names ("the cabal", "family").
- Businesses get an automatic, built in audience called **all followers**, because hand assigning thousands of followers does not scale. Their other circles (suppliers, partners) are hand picked.

## Audiences

Every content item has an audience: `public`, `connections`, `circles` (one or more chosen circles) or `group`. **New items default to connections.**

| Item | Audience | Label shown to viewers |
|---|---|---|
| Writing (blog posts) | always public | none |
| Gallery, status, vouches | chosen | none |
| Stories (24 hours) | chosen | yes: the circle name, or "Only for you" |

## Page sections

Header (photo, name, personal dot colour, status, connect or follow button), "what I do" tags (these drive search), activity (Last.fm, built last), stories, Top 8 vouches, writing, gallery, groups (stretch).

- **Status** works like Slack: a short line such as "on leave" that stays until changed.
- **Stories** expire after 24 hours.
- **Vouches:** every vouch is kept; the owner features up to 8 (Top 8) and can swap them at any time. Only featured Top 8 vouches count toward search trust ranking.
- **View as:** the owner can preview their page as any connection, circle member, follower or stranger.
- **Dot colour:** each person picks the colour of the dot in their doorway mark from a fixed palette (see design-system.md).

## Search and directory

Search only ever covers **public** data: names, "what I do" tags, public bios, business categories and location. Ranking is boosted by featured Top 8 vouches. Business reviews are out of scope.

## Delight features for the demo

- One click demo accounts (Amina, Brian, a business such as Java House style cafe; invented names only).
- **2006 mode:** a toggle that renders a page in early MySpace style.
- **AI themes:** describe a vibe, get a page theme; every theme is contrast checked before it is applied.
- **English and Swahili** for the whole interface.

## Scope order

Core: database foundation, profiles and acting as, relationships and circles, view as, search, vouches, writing, gallery, status, notifications, stories, AI themes, PWA polish.
Stretch (behind feature flags): groups, chat with automatic translation. Last: Last.fm activity.

Out of scope: business reviews, circle passes, feeds of any kind.
