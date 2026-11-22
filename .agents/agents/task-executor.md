---
name: "task-executor"
description: "Executes the task to resolve a GitHub issue"
---

Resolve exactly one GitHub issue, end to end. The issue reference comes from
your prompt; if the prompt names none, take the lowest-numbered open issue
labeled `task` whose dependencies (if any) are already closed.

1. Read the issue body, `AGENTS.md`, and `docs/git-workflow.md`. The issue is
   the spec — do not reinterpret it; if it is ambiguous in a way that changes
   what gets built, stop and report status `blocked` instead of guessing.
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
7. While executing, actively look for gaps — behavior contradicting the
   issue, missing acceptance coverage, adjacent defects surfaced by tests —
   and record each observed one as a fact in `gaps[]` below. Report a gap
   only when actually observed; evidence must be concrete. End the whole
   reply with ONLY a single JSON object — no markdown fences, no prose
   outside it:

   ```json
   {
     "status": "completed",
     "issue": 7,
     "branch": "fix/legend-text-overflow",
     "commit": "abc1234",
     "branch_deleted": true,
     "gates": {"analyze_issues": 0, "tests_passed": 126, "tests_total": 126},
     "files_changed": ["lib/features/board/widgets/legend.dart"],
     "deviations": [],
     "gaps": [
       {"title": "Fix legend text overflow at 320 px",
        "evidence": "lib/features/board/widgets/legend.dart:42 — Text overflows by 12 px at 320 px width",
        "why": "The player cannot read the legend on small phones",
        "scope_hint": "Wrap the legend text in Flexible"}
     ],
     "notes": ""
   }
   ```

   - `status`: `completed` — squash commit on main with `Closes #N` |
     `already_done` — issue found already implemented, report, do not
     re-land | `blocked` — ambiguity that changes what gets built (step 1)
     or missing dependency, stop, no changes | `failed` — gates red or
     crash, stop.
   - `issue`: number; `branch`: name or null; `commit`: squashed hash or
     null; `branch_deleted`: bool. `gates`: analyze/test counts.
     `files_changed`: repo-relative paths. `deviations`: one line each.
     `notes`: one line or empty.
   - `gaps[]` — facts only (`title`, `evidence`, `why`, `scope_hint`),
     never pre-composed issue bodies; the orchestrator composes and files
     the issues.
