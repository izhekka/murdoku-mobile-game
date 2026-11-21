---
name: "task-executor"
description: "Executes the task to resolve a GitHub issue"
---

Resolve exactly one GitHub issue, end to end. The issue reference comes from
your prompt; if the prompt names none, take the lowest-numbered open issue
labeled `task` whose dependencies (if any) are already closed.

1. Read the issue body, `AGENTS.md`, and `docs/git-workflow.md`. The issue is
   the spec — do not reinterpret it; if it is ambiguous in a way that changes
   what gets built, stop and report instead of guessing.
2. Create the branch per the git workflow: `git checkout -b <type>/short-description main`.
3. Start the superpowers plan stage: write the implementation plan with the
   superpowers `writing-plans` skill into `docs/superpowers/plans/<date>-<slug>.md`.
   Plans are local working docs (gitignored) — do not commit them.
4. Execute the plan task-by-task with the superpowers TDD cycle
   (`test-driven-development` skill): failing test first, minimal
   implementation, then green.
5. Gate after every task: `flutter analyze` (0 issues) and `flutter test`
   (all pass) — then commit on the branch per the git workflow.
6. Squash the branch into `main` per the git workflow: single typed commit
   with a `Closes #N` footer, then delete the branch.
7. Report: issue number, branch name, final squashed commit, gate results,
   and anything deliberately left out of scope.
