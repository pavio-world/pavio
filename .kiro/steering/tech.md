---
inclusion: always
---

# Pavio: tech

## Stack

| Layer | Choice |
|---|---|
| App | Next.js (App Router), React, TypeScript (strict) |
| PWA | Web app manifest plus a Serwist service worker; installable on Android and iPhone |
| Styling | Tailwind CSS with the Pavio tokens, shadcn/ui components |
| Validation | Zod, shared between client and server |
| Data fetching | Supabase JS client; server components for public pages |
| Database | Supabase Postgres with Row Level Security on every table |
| Auth | Supabase Auth: email magic link and Google |
| Files | Supabase Storage: public bucket for public items, private bucket with signed URLs for restricted items |
| Realtime | Supabase Realtime (stretch: chat) |
| Server logic | Next.js route handlers and server actions (AI, Last.fm, link preview images) |
| Email | Resend as the Supabase SMTP provider |
| Hosting | Vercel, domain pavio.world |
| Tests | pgTAP (database), Vitest plus fast-check (property based), Playwright (end to end) |
| Migrations | Supabase CLI; every schema change is a committed SQL migration |

## There is no separate backend server

The database is the backend. Privacy rules live in Postgres (RLS and SQL functions), not in application code. Next.js route handlers do only the work that needs secret API keys or heavy CPU: AI calls, Last.fm, Open Graph images. Do not add Express, Fastify, NestJS or any other server unless the product steering is changed first.

## Server code rules

- Route handlers create a Supabase client **as the signed in user** (from their session cookie) so RLS still applies.
- The Supabase **secret key** (service role) is allowed in exactly two places: `src/lib/supabase/admin.ts` and `supabase/seed/`. Nothing else may import it. See privacy.md.
- All AI calls go through one module, `src/lib/ai/`, which checks a per user daily limit and a global monthly spend cap stored in the database before calling the model.

## Configuration

- Product name, tagline, domain and colours live in `src/config/site.ts`. Never hard code "Pavio" or the tagline in components.
- All interface text lives in `src/config/strings/en.ts` and `src/config/strings/sw.ts`, read through a small `t()` helper. Keys are flat and quoted (`"profile.connect": "Connect"`). Both files must always have the same keys; a hook checks this on every save.
- Feature flags live in `src/config/flags.ts`: `stories`, `groups`, `chat`, `activity`, `mode2006`, `aiThemes`.

## Performance and devices

Target mid range Android phones on mobile data. Keep client JavaScript small: prefer server components, lazy load heavy UI, use Next Image with Supabase image transforms.
