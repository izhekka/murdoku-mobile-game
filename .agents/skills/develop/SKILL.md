---
name: develop
description: Run the GitHub-issue development loop end to end — use when the user says /develop, "run the dev loop", "continue the issue queue", "develop the task queue", or asks to keep working the open task issues. Picks the lowest-numbered open task issue, dispatches the task-executor agent, pushes the landed work, files new issues for gaps the executor reported.
---

# Develop

Work the GitHub `task` issue queue end to end: pick one issue, dispatch the
`task-executor` agent, push the completed work, file issues for the gaps the
executor found, repeat. You are the orchestrator; all executor work happens in
subagents — never in your own context. The run ends when the queue is empty,
the per-run cap is hit, or something blocks.

## Invariants (bind the whole run)

- Agents never push; the orchestrator pushes only fast-forward `main` (never
  force) — per `docs/git-workflow.md` pushing stays with the orchestrator.
- One branch per issue, squashed into `main` per `docs/git-workflow.md`.
- Never edit generated output (`lib/l10n/generated/**`, `**/.dart_tool/**`,
  `*.g.dart`).
- The six-section issue format is mandatory for gap issues (submit-task §5).
- Strictly sequential: the next dispatch happens only after the previous
  dispatch's JSON report is parsed and acted on.

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
Instruct it to end its reply with the JSON report per that file's step 7.
Never run the executor's steps in your own context.

### 3. Parse the JSON report

The reply must be a single JSON object per `.agents/agents/task-executor.md`
step 7 — that file is the schema's single source of truth; parse it, do not
restate it. On invalid JSON, send the SAME agent ONE follow-up asking for the
corrected JSON object only. If it is still invalid, stop the run and surface
the raw output verbatim.

### 4. Act by status

- `completed` — push the work: `git push origin main` (fast-forward only,
  never force). Confirm the issue auto-closed
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
