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

## One branch and one pull request per spec

- **Every spec gets its own branch**, created from an up to date `main` before the first task: `spec/<spec folder name>`, for example `spec/00-database-foundation`, `spec/02-relationships-circles`.
- All of that spec's commits (code, migrations, tests, DEVLOG entries) go on its branch. **Never commit directly to `main`.**
- Push the branch after each completed task so progress is visible on GitHub.
- **Open a pull request** into `main` when all the spec's tasks are done and its tests pass. Use GitHub through the available MCP tools or the `gh` CLI.
- **Pull request title:** `Spec NN: <spec name>`. **Description**, using these headings:
  - **Summary**: what the spec delivers, in plain language.
  - **Spec**: link to `.kiro/specs/<spec>/` (requirements, design, tasks).
  - **Tasks completed**: the task list with checkmarks.
  - **Database changes**: migrations added, policies and functions created, advisor results.
  - **Tests**: what was added and the result of every test suite.
  - **Reviews**: the privacy-reviewer report for any spec that touches data, and the design-reviewer report with screenshots for any spec that touches UI.
  - **Notes**: decisions, trade offs, anything left for later.
- **Before opening the pull request**, run the relevant reviewer agents and fix every Critical and High finding.
- **Merge** with a merge commit (not squash), so the atomic commit history stays readable on `main`. Then delete the branch and update local `main`.
- **Only Dominic merges.** Prepare the pull request, then stop and ask him to review and merge.

## One spec at a time (shared database)

There is one hosted Supabase project, and migrations apply to it as soon as they run, even from a branch. So:

- **Only one spec branch is open at a time.** Do not start the next spec until the previous pull request is merged into `main`.
- If a spec is abandoned, its migrations are still live: write a new migration that reverses them (with Dominic's approval) rather than leaving the database ahead of `main`.

## Safety

- Never commit secrets or `.env` files. Never rewrite pushed history: no force push, no rebase of pushed commits, no amending pushed commits.
- Never commit generated noise (build output, coverage, logs); `.gitignore` covers these.
