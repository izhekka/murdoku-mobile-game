# Decision records

Committed, append-only history of decisions that bind future work.

Scope test: **does the decision change the app's architecture, domain
data flow, screen wiring, or CI pipeline design? If yes, it gets a
record.** Routine per-task design details live in their issues
instead; decisions whose rationale is already fully written in
AGENTS.md only get a record when they change.

## What does NOT get a record

- SDLC/agent/skill/plan/process decisions
- Git workflow and history rules
- Naming/branding chores
- Build-tool chores

Those live in AGENTS.md, docs/git-workflow.md, or the task issue
itself.

## Process

1. The orchestrator drafts a record during the brainstorm, while the
   alternatives and the why are fresh.
2. The record travels to the executor inside the task issue's Context
   as a fenced block naming the target path. A decision with no code
   task rides a tiny `docs:` issue through the same pipeline.
3. The executor commits the record file on the task branch alongside
   the change it documents, and adds the record's row to the Index
   below in the same commit.

## Rules

- One file per decision: `NNNN-<kebab-slug>.md`, zero-padded, strictly
  sequential (next = highest existing + 1).
- A record is immutable once accepted — except its **Status** line. To
  reverse a decision, write a new record that names the old one in its
  Context and flip the old record's Status to `superseded by NNNN`.
- Records may restate rules from AGENTS.md or docs/git-workflow.md but
  must not contradict them; their added value is the why and the
  alternatives considered.

## Template

```markdown
# NNNN. <Decision title>

**Status:** accepted
**Date:** YYYY-MM-DD

## Context
<The situation that forced a decision, and the prior state.>

## Decision
<What was decided, stated so a future agent can follow it as a rule.>

## Alternatives considered
<The real alternatives and why they lost.>

## Consequences
<What this binds future work to; what becomes easier or harder.>
```

## Index

| # | Title | Date | Status |
|---|-------|------|--------|
| 0004 | BesideObject clues mean the same room | 2026-11-21 | accepted |
| 0006 | Quality gate pipeline (format, lints, CRAP ratchet) | 2026-11-22 | accepted |

Scope narrowed 2026-11-22: non-architecture records 0001–0003 and 0005–0007 were removed — recoverable from git history.
