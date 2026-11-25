---
inclusion: always
---

# Pavio: git and commits

The commit history is part of the hackathon submission. Judges read it to see how Pavio was built, so it must tell a clear story.

## Atomic commits

- **One logical change per commit.** A commit does one thing: adds one migration, one function, one component, one test file group, or one fix. If the message needs the word "and" to describe two unrelated things, split it.
- **Every commit leaves the project working.** It builds, type checks and its tests pass. Never commit half finished work.
- **Keep kinds of change apart.** Schema migrations, application code, tests, steering or spec edits, and formatting are separate commits. A migration and the pgTAP test that proves it may go together.
- **Commit as you go**, not in one big commit at the end of a task. A spec task usually produces several small commits.
- Stage files explicitly (`git add <paths>`). Never use `git add .` or `git add -A` blindly; check `git status` and `git diff --staged` before committing.

## Message format (Conventional Commits)

```
<type>(<scope>): <what changed, imperative, lower case, max 72 chars>

<optional body: why, not how; reference the spec task, e.g. Spec 02 task 3.1>
```

- **Types:** `feat`, `fix`, `db` (migrations and SQL functions), `test`, `refactor`, `style`, `docs`, `chore`, `build`.
- **Scopes:** the feature or area: `profiles`, `relationships`, `circles`, `view-as`, `search`, `vouches`, `content`, `notifications`, `stories`, `ai`, `pwa`, `i18n`, `kiro`, `seed`.
- Examples:
  - `db(circles): add circles and circle_members tables with rls`
  - `test(privacy): property test that removed members lose circle access`
  - `feat(view-as): add viewer switcher to profile header`
  - `fix(search): exclude non public bios from directory results`

## Safety

- Never commit secrets or `.env` files. Never rewrite pushed history: no force push, no rebase of pushed commits, no amending pushed commits.
- Work on `main` in small commits. Push to `origin` after each completed spec task.
- Never commit generated noise (build output, coverage, logs); `.gitignore` covers these.
