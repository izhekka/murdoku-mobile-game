---
name: develop
description: Run the GitHub-issue development loop end to end — use when the user says /develop, "run the dev loop", "continue the issue queue", "develop the task queue", or asks to keep working the open task issues. Picks the lowest-numbered open task issue, dispatches the task-executor agent, runs one in-run code-review round, pushes the landed work, files new issues for gaps the executor reported.
---

# Develop

Work the GitHub issue queue: pick one issue, dispatch the `task-executor`
subagent, run one review round, push, file the reported gaps, repeat. You
are the orchestrator — all executor work happens in subagents, never in your
own context. The run ends when the queue is empty, the cap is hit, or
something blocks.

## Invariants (bind the whole run)

- You push only fast-forward `main`, never force. Subagents never push
  (`docs/git-workflow.md`).
- One branch per issue, squashed into `main` per `docs/git-workflow.md`.
- Never edit generated output: `lib/l10n/generated/**`, `**/.dart_tool/**`,
  `*.g.dart`.
- Gap issues use the six-section format (submit-task §5).
- Strictly sequential: dispatch the next issue only after the previous
  dispatch's JSON report is parsed and acted on. The only parallelism is
  inside one issue's review round — at most one reviewer of each kind, each
  on that issue's branch.
- Gate policy (issue #105): the executor runs `flutter analyze` + touched
  tests during work (heavy raster batteries excluded with
  `--exclude-tags=raster`) and runs the FULL `make quality` once, at the
  squash point. Reviewers verify by diff + targeted tests and never re-run
  the full gate. You run one final `make quality` before each push as the
  backstop.

## Watchdog (issue #105)

A dispatched or resumed leg can die silently (run-17/18 pattern). After
every dispatch or resume:

- Heartbeat ~every 10 minutes: check progress signals — worktree file
  mtimes or growth of the subagent's output file.
- On a 10-minute stall: kill stale `flutter_tester` processes
  (`pkill -f flutter_tester`), then dispatch a fresh recovery subagent that
  continues from the worktree state (branch, staged/unstaged files, last
  gate output).

## Loop

### 1. Pick the next issue

The queue is every open issue labeled `task`, `gap`, or `issue` (union —
gh's REST labels param is AND-semantics, so filter client-side, never with a
comma-label query). Take the lowest number:

```bash
gh issue list --state open --json number,title,labels \
  | jq '[.[] | select(any(.labels[].name; . == "task" or . == "gap" or . == "issue"))] | sort_by(.number)'
```

Empty output → print exactly `queue empty — nothing to do` and stop. That is
the normal end state, not an error.

### 2. Dispatch the task-executor

Spawn a subagent running the `task-executor` agent
(`.agents/agents/task-executor.md`) with the issue number as its prompt;
instruct it to end with the JSON report per that file's step 8. Start the
watchdog heartbeat.

### 3. Parse the JSON report

The reply must be a single JSON object — `task-executor.md` step 8 is the
schema's single source of truth; parse it, do not restate it.

- Invalid JSON: send the SAME agent ONE follow-up asking for the corrected
  JSON only. Still invalid → stop the run and surface the raw output
  verbatim.
- `surfaced[]` (issue #78) is optional — present or absent both parse. It is
  note-only: print it in the run summary, count it in the accounting line's
  `surfaced`, never treat it as `gaps[]`, never file it solo. The only
  filing path for a surfaced fact is the Batcher ≥4 batch (§5 item 5).
- `review.findings` may carry items from both reviewers (issue #84): items
  from the visual-reviewer carry a `source: visual` marker; every bucket is
  parsed and acted on identically.

### 4. Act by status

- `ready_for_review` — gates green, work committed on the branch
  (pre-squash). Run one review round:

  1. Review-applies policy: review every issue whose reported
     `files_changed` touches code or tests; skip only pure documentation
     diffs (md/README-only). On skip, note `reviewer_dispatched: false` —
     and still resume the executor with its gap sweep no matter what. The
     marker is an unconditional synchronization point; the executor never
     finishes the round inline.
  2. Otherwise dispatch the `code-reviewer` agent
     (`.agents/agents/code-reviewer.md`) in the background with the issue
     number, the branch, and `AGENTS.md` — the issue is the spec.
  3. Visual predicate (issue #84): if `files_changed` touches render paths
     — `lib/ui/widgets/**`, `lib/core/skins.dart`, `lib/core/theme.dart`, or
     any `CustomPainter` subclass — ALSO dispatch the `visual-reviewer`
     agent (`.agents/agents/visual-reviewer.md`) in the background, together
     with the `code-reviewer`, with the issue number, branch, `AGENTS.md`,
     and the coverage-matrix reference. A logic-only diff gets no
     visual-reviewer. Both dispatches precede the executor resume.
  4. When a reviewer lands, forward its findings verbatim (SendMessage) —
     when both ran, one merged list. The executor evaluates each finding
     against its bounce budget, fixes in-branch what is in budget, re-runs
     the gates, squashes, and delivers the final report (parse per step 3).
     `[P0]`–`[P2]` from EITHER reviewer bind the bounce round.
  5. One review round total: never re-dispatch a reviewer for the fix diff
     (the executor's own delta check is the only follow-up). Review is an
     enhancement — a dispatch failure or junk findings are noted at run end
     and never stop the run.

- `completed` — push first gated on review findings: an unresolved `[P0]`
  outside `fixed_in_branch` blocks the landing — do not push, do not close
  the issue, surface it to the user, stop. Otherwise push
  (`git push origin main`, fast-forward only), confirm the issue auto-closed
  (`gh issue view <n> --json state -q .state`), and close it yourself with
  `gh issue close <n>` if it did not.
- `already_done` — close the issue with a one-line comment; re-land nothing.
- `blocked` / `failed` — stop the run and surface the JSON report verbatim.
  Do not push, do not file gaps from this report.

### 5. File the gaps

File only facts the executor reported in `gaps[]`. The Batcher rule (item 5)
decides solo vs batch — and for `severity_low` it is the ONLY filing path.
Instrument completeness stays demand-driven: counters/parsers gain constructs
only when one appears in measured code or the owner asks.

1. Materiality gate: file only `reachable` facts — something that ships can
   produce them (a player flow, a measured code path in `lib/`/`tool/`, or a
   running CI stage). A fact marked `note_only` by the executor, or whose
   evidence says "no current usage", "no host can produce this",
   "`lib/**` contains none", or "only if a future change", is NEVER filed —
   surface it in the run summary instead.
2. Duplicate-check against the same universe the pick step uses (open
   `task`/`gap`/`issue` issues); skip facts already covered.
3. Compose the six-section body (submit-task §5) grounded in the reported
   fact: `evidence` goes into Context verbatim; a fix touching code gets the
   gate in acceptance criteria and testing strategy (full `make quality`
   for `lib/**`; else analyze 0 issues + tests pass).
4. Ensure labels exist (idempotent, fresh-clone safe), then create with a
   provenance label + ONE class label + ONE severity label — never `task`:

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

   The class lines use `--force` so an existing label is re-colored, never
   left stale.
   - Provenance by origin: `gap` = executor's gap sweep; `issue` = reviewer
     finding (including `filed_as_tasks` entries — origin wins over the
     report section it appears in).
   - Class: tech-debt / tooling / documentation / user-facing / performance
     / security — the one matching what the fix is.
   - Severity: `severity_high` = likely player harm or blocks a feature;
     `severity_middle` = latent crash capability or a deferred core goal;
     `severity_low` = cosmetic, latent-internal, or tooling. The executor's
     `severity`/`mechanical` fields inform but do not bind — you may
     override at filing time.
   - Filing path: `severity_middle`/`severity_high` file solo here. A
     `severity_low` fact NEVER files solo. A low + non-mechanical fact needs
     your design call: either override `mechanical` to true (it joins the
     Batcher pool) or raise its severity and file solo — never leave it
     accumulating forever.
5. Batcher rule — the only path to a `severity_low` filing. If fewer than 4
   open low-severity mechanical tickets exist in the queue universe (each
   labeled `severity_low`, none middle/high, every fix mechanical; the count
   includes open batch seeds and this run's accumulated facts), do NOT file:
   record the fact in the run summary (`surfaced`) and accumulate it in
   memory, carried forward in run summaries. At ≥4, consolidate all of them
   into ONE batch issue (six-section body naming every item; shared
   class/severity + provenance labels) and ship it as one branch with
   per-item tests and one squash whose commit carries one `Closes #N`
   footer per consolidated issue.
6. Refuse to file a fact whose `evidence` is not concrete (no file:line,
   screenshot, or observed output) — surface it to the user instead.

### 6. Loop and stop conditions

Repeat from step 1 — gaps filed this iteration are eligible next iteration.
Stop conditions:

- Queue empty → print the per-issue summary (issue, status, commit, gaps
  filed) plus the accounting line — absorbed in-branch / filed / surfaced
  (absorbed = fixed inside a task's branch per the close-forward budget:
  reviewer findings the squash closes with `Closes #N` footers, and
  executor-sweep absorbs disclosed as `absorbed:` lines in `notes`; filed =
  follow-ups filed; surfaced = `note_only` facts, `surfaced[]` entries,
  below-the-line low facts, out-of-scope notes) — then stop normally.
- 10 issues in one run (hard cap) → print the same summary with the
  remaining queue, then stop.
- `blocked` / `failed` / invalid JSON after the one retry → stop and surface
  the raw JSON verbatim.
