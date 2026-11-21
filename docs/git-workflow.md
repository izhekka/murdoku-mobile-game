# Git workflow

Branch, commit, and merge rules for this repository. They bind every
contributor — human or autonomous agent (currently the `task-executor`
agent, defined in `.agents/agents/task-executor.md`).

## Branches

- Branch from the current local `main` before starting any work:
  `git checkout -b <type>/short-description main`.
- Branch name: `<type>/short-description`
  - `<type>` — one of the commit types below, matching the dominant type of the change.
  - `short-description` — 2–5 lowercase kebab-case words describing the change.
- Examples: `feat/same-room-item-clues`, `fix/legend-text-overflow`, `docs/ux-plan-addendum`.
- One branch per issue. Never stack on another feature branch, and never commit
  to `main` directly — the only `main` commits an agent makes are squash commits (below).

## Commits

Subject format: `<type>(<optional scope>): <subject>`

- `type` — required. Allowed values:
  `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- `scope` — optional, a short area name (`board`, `clues`, `l10n`, `assets`, `skills`, …).
- `subject` — imperative mood, ≤ 72 characters, no trailing period.

Examples (from this repo's history):

- `feat(a11y): enable semantics tree at boot (web/automation + screen readers)`
- `docs(plan): UX-8/9/10 — same-room item clues, layout dead space, tall cards`
- `chore: remove unused ring helper from gen_items`

Intermediate commits on a branch may be red (e.g. the failing test of a TDD
cycle); the gates below must pass before a task is left or a branch is squashed.

## Finishing a task: squash into `main`

Branch history is work-in-progress; only the squashed result lands on `main`:

```bash
git checkout main
git merge --squash <type>/short-description
# gates: flutter analyze → 0 issues, flutter test → all pass
git commit -m "<type>: <imperative summary>" -m "Closes #<issue>"
git branch -D <type>/short-description
```

- The final commit follows the same subject rules; when the branch resolves an
  issue, add the `Closes #<issue>` footer so GitHub closes it when the owner pushes.
- If `main` moved while the branch was open, resolve conflicts during the squash
  merge; on semantic conflicts, stop and report instead of guessing.
- Do not push. Pushing `main` to `origin` stays with the owner: agents never
  push, never force-push, and never rewrite history.
