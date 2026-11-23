---
name: develop
description: Run the GitHub-issue development loop end to end — use when the user says /develop, "run the dev loop", "continue the issue queue", "develop the task queue", or asks to keep working the open task issues. Picks the lowest-numbered open task issue, dispatches the task-executor agent, runs one in-run code-review round, pushes the landed work, files new issues for gaps the executor reported.
---

# Develop

Work the GitHub `task` issue queue end to end: pick one issue, dispatch the
`task-executor` agent, run the in-run review round, push the completed work,
file issues for the gaps the executor found, repeat. You are the orchestrator;
all executor work happens in subagents — never in your own context. The run
ends when the queue is empty, the per-run cap is hit, or something blocks.

## Invariants (bind the whole run)

- Agents never push; the orchestrator pushes only fast-forward `main` (never
  force) — per `docs/git-workflow.md` pushing stays with the orchestrator.
- One branch per issue, squashed into `main` per `docs/git-workflow.md`.
- Never edit generated output (`lib/l10n/generated/**`, `**/.dart_tool/**`,
  `*.g.dart`).
- The six-section issue format is mandatory for gap issues (submit-task §5).
- Strictly sequential: the next issue's dispatch happens only after the
  previous dispatch's JSON report is parsed and acted on. The one parallelism
  allowed is inside a single issue's review round: at most one background
  `code-reviewer` at a time, dispatched against that issue's own branch.

## Loop

### 1. Pick the next issue

```bash
gh issue list --label task --state open --json number,title
```

Take the lowest-numbered issue. If there is none, print exactly:

```
queue empty — nothing to do
```

and stop. This is the normal end state, not an error.

### 2. Dispatch the task-executor agent

Spawn a subagent running the `task-executor` agent (defined in
`.agents/agents/task-executor.md`) with the issue number as its prompt.
Instruct it to end its reply with the JSON report per that file's report
contract (step 8). Never run the executor's steps in your own context.

### 3. Parse the JSON report

The reply must be a single JSON object per `.agents/agents/task-executor.md`
step 8 — that file is the schema's single source of truth; parse it, do not
restate it. On invalid JSON, send the SAME agent ONE follow-up asking for the
corrected JSON object only. If it is still invalid, stop the run and surface
the raw output verbatim.

### 4. Act by status

- `ready_for_review` — the executor's gates are green and its work is
  committed on the branch (pre-squash). Run one review round:
  1. Review-applies policy: review every issue whose reported
     `files_changed` touches code or tests; skip only pure documentation
     diffs (md/README-only) — review value is not size-predictable, so apply
     the policy, not size judgment. On skip, note `reviewer_dispatched:
     false` and still resume the executor no matter what — the marker is an
     unconditional synchronization point, and the executor must never finish
     the round inline — sending it straight to its gap sweep.
  2. Otherwise dispatch a subagent running the `code-reviewer` agent
     (`.agents/agents/code-reviewer.md`) in the background with the issue
     number, the branch, and `AGENTS.md` — the issue is the spec — and
     simultaneously resume the executor to run its gap sweep while the
     reviewer works.
  3. When the reviewer lands, forward its findings verbatim to the executor
     (SendMessage). The executor evaluates every finding against its bounce
     budget, fixes what is in budget in the same branch, re-runs the gates,
     and squashes — then delivers its final report; parse it per step 3.
  4. One review round total: never re-dispatch the reviewer for the fix diff
     (the executor's own delta check of the fix diff is the only follow-up).
     Review is an enhancement: a dispatch failure or junk findings are noted
     at the end of the run and never stop the run.
- `completed` — push gate first: confirm the report's `review.findings` has
  no `[P0]` finding outside `fixed_in_branch`. An unresolved `[P0]` blocks
  the landing: do not push, do not close the issue, surface it to the user
  and stop the run. Otherwise push the work: `git push origin main`
  (fast-forward only, never force). Confirm the issue auto-closed
  (`gh issue view <n> --json state -q .state`); if it did not, close it
  yourself with `gh issue close <n>`.
- `already_done` — close the issue with a one-line comment; do not re-land
  anything.
- `blocked` / `failed` — stop the run and surface the JSON report verbatim to
  the user. Do not push, do not file gaps from this report.

### 5. File the gaps

For each fact in `gaps[]`:

1. Duplicate-check against open `task` issues (`gh issue list --label task
   --state open`) — skip facts already covered by an open issue.
2. Compose the issue body in the exact six-section format of submit-task §5
   (Description, User story, Context, Acceptance criteria, Testing strategy,
   Out Of scope), grounded in the reported fact: the `evidence` goes into
   Context verbatim; when the fix touches code, include the gate
   (`flutter analyze` reports 0 issues and `flutter test` passes) in the
   acceptance criteria and testing strategy.
3. File it: `gh issue create --title <title> --body-file <tmpfile> --label task`.
4. Refuse to file a gap whose `evidence` is not concrete (no file:line,
   screenshot, or observed output) — surface it to the user instead.

### 6. Loop and stop conditions

Repeat from step 1 — newly filed gap issues are eligible in the next
iteration. Stop conditions:

- Queue empty → print a per-issue summary (issue, status, commit, gaps
  filed) and stop normally.
- 10 issues processed in one run (hard cap) → print the summary and the
  remaining queue, then stop.
- `blocked` / `failed` / invalid JSON after the one retry → stop and surface
  the raw JSON verbatim.
