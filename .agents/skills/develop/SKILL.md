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

The queue is every open issue whose labels include at least one of `task`,
`gap`, `issue` — owner-filed `task` issues stay findable alongside follow-up
`gap`/`issue` filings. gh's REST `labels` parameter is AND-semantics, so the
union is filtered client-side, never via a comma-label OR query:

```bash
gh issue list --state open --json number,title,labels \
  | jq '[.[] | select(any(.labels[].name; . == "task" or . == "gap" or . == "issue"))] | sort_by(.number)'
```

Take the lowest-numbered issue (first row of the sorted output). If the
output is empty, print exactly:

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

File only gaps the executor reported as `gaps[]` facts — reachable facts
only per the materiality gate below; the Batcher rule (item 5) decides
whether a filing ships solo or inside one batch issue. Instrument
completeness stays demand-driven: counters/parsers gain new constructs
only when one appears in measured code or the owner asks — never as a
spec-completeness follow-up.

1. Materiality gate: file only `reachable` facts — a fact is `reachable`
   when something that ships can produce it (a player flow, an existing
   measured code path in `lib/`/`tool/`, or a running CI stage), else
   `note_only` (unreachable by anything that ships). A fact whose
   reachability from the executor's gate (task-executor step 6b) is
   `note_only`, or whose evidence contains a disqualifier phrase —
   "no current usage", "no host can produce this",
   "`lib/**` contains none", "only if a future change" — is never
   filed: surface it in the run summary instead.
2. Duplicate-check against the same universe the pick step uses — every open
   issue whose labels include at least one of `task`, `gap`, `issue`:
   `gh issue list --state open --json number,title,labels | jq '[.[] | select(any(.labels[].name; . == "task" or . == "gap" or . == "issue"))]'`
   — skip facts already covered by an open issue.
3. Compose the issue body in the exact six-section format of submit-task §5
   (Description, User story, Context, Acceptance criteria, Testing strategy,
   Out Of scope), grounded in the reported fact: the `evidence` goes into
   Context verbatim; when the fix touches code, include the gate
   (`flutter analyze` reports 0 issues and `flutter test` passes) in the
   acceptance criteria and testing strategy.
4. File it. Ensure the follow-up labels exist first (idempotent — a fresh
   clone files labeled follow-ups without pre-setup):

   ```bash
   gh label create gap --color 006b75 2>/dev/null || true
   gh label create issue --color ff0000 2>/dev/null || true
   gh label create severity_low --color 800080 2>/dev/null || true
   gh label create severity_middle --color 800080 2>/dev/null || true
   gh label create severity_high --color 800080 2>/dev/null || true
   gh label create tech-debt --color e4e669 --description "Follow-up class: technical debt" --force 2>/dev/null || true
   gh label create tooling --color e4e669 --description "Follow-up class: contributor/internal tooling" --force 2>/dev/null || true
   gh label create documentation --color e4e669 --description "Follow-up class: documentation" --force 2>/dev/null || true
   gh label create user-facing --color e4e669 --description "Follow-up class: player-visible behavior" --force 2>/dev/null || true
   gh label create performance --color e4e669 --description "Follow-up class: speed/memory/efficiency" --force 2>/dev/null || true
   gh label create security --color e4e669 --description "Follow-up class: correctness/security boundary" --force 2>/dev/null || true
   ```

   The class ensure lines use `--force` so an existing label (e.g.
   `documentation`) is re-colored to `e4e669` instead of being left stale.
   Then create with the provenance, class, and severity labels — never
   `task`:
   `gh issue create --title <title> --body-file <tmpfile> --label <provenance> --label <class> --label <severity>`.
   Provenance by origin: `gap` when the fact originates from the executor's
   gap sweep; `issue` when it originates from a reviewer finding — including
   findings the executor recorded as `filed_as_tasks` with a matching gap
   fact (origin wins over the report section the fact appears in). Class,
   assigned by the orchestrator at filing time, is exactly ONE of
   `tech-debt` / `tooling` / `documentation` / `user-facing` /
   `performance` / `security` — pick the class matching what the fix is
   (internal code debt → `tech-debt`; contributor tooling → `tooling`;
   docs → `documentation`; player-visible behavior → `user-facing`;
   speed/memory → `performance`; correctness/security boundary →
   `security`) — stacked with the provenance and severity labels. Severity,
   assigned by the orchestrator at filing: `severity_high` = likely player
   harm or blocks a feature; `severity_middle` = latent crash-capability or
   a deferred core goal; `severity_low` = cosmetic, latent-internal, or
   tooling.
5. Batcher rule: when ≥4 open low-severity mechanical tickets accumulate in
   the queue (each labeled `severity_low`, none `severity_middle`/
   `severity_high`, every fix mechanical), consolidate them into ONE batch
   issue (six-section body naming every consolidated item) instead of solo
   dispatches. The batch ships as one branch with per-item tests and one
   squash that carries multiple `Closes #N` footers — one per consolidated
   issue. The batch issue carries the items' shared class + severity labels
   plus a provenance label (`gap` or `issue`) so the pick step finds it.
6. Refuse to file a gap whose `evidence` is not concrete (no file:line,
   screenshot, or observed output) — surface it to the user instead.

### 6. Loop and stop conditions

Repeat from step 1 — newly filed gap issues are eligible in the next
iteration. Stop conditions:

- Queue empty → print a per-issue summary (issue, status, commit, gaps
  filed) plus the run's accounting line — absorbed in-branch / filed /
  surfaced (absorbed = found issues fixed inside a task's branch per the
  close-forward budget, disclosed with issue numbers; filed = follow-up
  issues filed; surfaced = `note_only` facts and out-of-scope notes
  reported without a ticket) — and stop normally.
- 10 issues processed in one run (hard cap) → print the same summary
  (with the accounting line) and the remaining queue, then stop.
- `blocked` / `failed` / invalid JSON after the one retry → stop and surface
  the raw JSON verbatim.
