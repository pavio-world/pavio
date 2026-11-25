---
inclusion: always
---

# Pavio: structure and working rules

## Folders

```
src/
  app/                    Next.js routes
    (public)/[handle]/    public profile and business pages
    (app)/                signed in screens: edit, circles, notifications, search
    api/                  route handlers (ai, lastfm, og)
  components/             shared UI (shadcn based)
  features/<feature>/     feature code: components, queries, actions, schemas
  lib/
    supabase/             client.ts, server.ts, admin.ts (admin is restricted)
    ai/                   the single AI entry point
    i18n/                 t() helper
  config/                 site.ts, flags.ts, strings/en.ts, strings/sw.ts
supabase/
  migrations/             timestamped SQL migrations
  tests/                  pgTAP tests
  seed/                   demo accounts and sample data
tests/
  property/               fast-check property based tests
  e2e/                    Playwright tests
scripts/hooks/            scripts called by Kiro hooks
public/                   icons, manifest, brand assets
docs/                     decisions, prompts
```

## Naming

- Files: kebab case (`view-as-switcher.tsx`). Components: PascalCase. Database: snake_case, plural table names.
- Feature folders match spec names (`features/circles`, `features/view-as`).

## Working rules for the agent

1. **Specs first.** Every feature is built from a spec in `.kiro/specs/`. Do not build features that no spec asks for.
2. **Database first.** Read the current migrations before writing any data access code. Never guess a column name.
3. **Small steps.** One task at a time; keep the app building and tests passing after every task.
4. **Atomic commits as you go**, following git.md: one logical change per commit, Conventional Commit messages, every commit leaves the project working.
5. **Build diary.** After each completed spec task, add a short entry to `DEVLOG.md`: date, spec and task, what was built, any decision or problem worth remembering. Keep entries honest and brief.
6. **Decisions.** When a meaningful technical choice is made, record it in `docs/decisions/NNN-title.md` (context, decision, consequences).
7. Never commit secrets. Never edit `.env` files.
