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
6. Review round between the gates and the squash. When the last task's gates
   have passed and all work is committed on the branch (pre-squash), run one
   review round:

   a. Interim marker: post the interim report — a single JSON object in the
      shape of step 8 with `status: "ready_for_review"`, the branch name,
      `commit` is `null` and `branch_deleted` is `false` (no squash yet),
      gates, `files_changed`, gaps so far, and `review` with
      `reviewer_dispatched: false` and empty findings buckets. Do NOT squash
      in this reply: the marker is an unconditional synchronization point —
      always post it and stop there; never run the rest of the review round
      (gap sweep, findings evaluation, squash) in the same reply, even when
      the review-applies policy means no reviewer will be dispatched. The
      orchestrator always resumes you — its resume notes the skip — to run
      the gap sweep while the reviewer works, or simply to proceed when no
      reviewer was dispatched; the single squash happens only after this
      round, in the resumed reply. The orchestrator then dispatches
      `code-reviewer` (issue number + branch + AGENTS.md per the
      review-applies policy) and resumes you to run the gap sweep — review
      and sweep run in parallel.
   b. Gap sweep: re-read the issue's acceptance criteria against the diff and
      the tests; actively look for behavior contradicting the issue, missing
      acceptance coverage, and adjacent defects surfaced by tests. Record
      each observed gap as a fact (`title`, `evidence`, `why`, `scope_hint`)
      plus exactly one `class` from
      `in_scope_miss|disclosed_by_new_tooling|out_of_scope_by_issue|environment_owner|observation_only`.
      Report a gap only when actually observed; evidence must be concrete.
   c. Findings evaluation — when the orchestrator forwards the reviewer's
      findings, every finding lands somewhere — never dropped:
      - `[P0]`/`[P1]` → fix in the branch if in budget, else keep it out of
        the branch;
      - `[P2]`/`[P3]` → fix if in budget and cheap, else note it in the
        final report;
      - bounce budget: an in-branch fix touches only files the issue already
        changed (plus new test files), needs no new dependencies, and costs
        ≤ 1 extra TDD cycle per finding. A finding outside this budget is
        recorded in the final report as `filed_as_tasks` and gets a matching
        gap fact in `gaps[]` (class `in_scope_miss` when the issue's scope
        covers it);
      - after any fix, re-run the gates (step 5); there is no full second
        review — at most a delta check of the fix diff — and one review round
        total;
      - reviewer dispatch failure or junk findings are noted in the final
        report and do NOT stop the run (review is an enhancement, not a
        dependency).
   d. Disposition: record each finding in the final report's
      `review.findings` under `fixed_in_branch` / `filed_as_tasks` /
      `noted` — one line each, `[Pn] file:line — finding`.

7. Squash the branch into `main` per the git workflow: single typed commit
   with a `Closes #N` footer, then delete the branch.
8. End the whole reply with ONLY a single JSON object — no markdown fences,
   no prose outside it:

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
        "scope_hint": "Wrap the legend text in Flexible",
        "class": "in_scope_miss"}
     ],
     "review": {"reviewer_dispatched": true,
                "findings": {"fixed_in_branch": [], "filed_as_tasks": [], "noted": []}},
     "notes": ""
   }
   ```

   - `status`: `completed` — squash commit on main with `Closes #N` |
     `ready_for_review` — gates green, work committed on the branch, no
     squash yet; the review round (step 6) is in flight, squash and final
     report follow on resume | `already_done` — issue found already
     implemented, report, do not re-land | `blocked` — ambiguity that changes
     what gets built (step 1) or missing dependency, stop, no changes |
     `failed` — gates red or crash, stop.
   - `issue`: number; `branch`: name or null; `commit`: squashed hash on
     `completed`, on `ready_for_review` `commit` is `null` and
     `branch_deleted` is `false` (pre-squash); `branch_deleted`: bool.
     `gates`: analyze/test counts. `files_changed`: repo-relative paths.
     `deviations`: one line each. `notes`: one line or empty.
   - `gaps[]` — facts only (`title`, `evidence`, `why`, `scope_hint`, plus
     one `class` from
     `in_scope_miss|disclosed_by_new_tooling|out_of_scope_by_issue|environment_owner|observation_only`),
     never pre-composed issue bodies; the orchestrator composes and files
     the issues.
   - `review` — `{reviewer_dispatched: bool, findings: {fixed_in_branch: [],
     filed_as_tasks: [], noted: []}}`; list items are one-line strings
     (`[Pn] file:line — finding`); `reviewer_dispatched` is false when the
     orchestrator skipped the dispatch (pure documentation diff per the
     review-applies policy) or the dispatch failed; findings recorded here
     must never be silently dropped, and neither dispatch failure nor junk
     findings stop the run — review is an enhancement, not a dependency.
