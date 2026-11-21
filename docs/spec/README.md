# Decision records

Committed, append-only history of decisions that bind future work.

Scope test: **would a fresh contributor or a future agent violate
something by not knowing this?** If yes, it gets a record. Routine
per-task design details live in their issues instead; decisions whose
rationale is already fully written in AGENTS.md only get a record when
they change.

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
| 0001 | Item sprites come only from the game-icons.net pipeline | 2026-11-21 | accepted |
| 0002 | Plans and specs are local working docs | 2026-11-21 | accepted |
| 0003 | Agent factory: canonical .agents/agents/ + make init projections | 2026-11-21 | accepted |
| 0004 | BesideObject clues mean the same room | 2026-11-21 | accepted |
| 0005 | Git history was rewritten once; never rewrite it again | 2026-11-21 | accepted |
| 0006 | "Murdoku" is a working title — rename before store submission | 2026-11-19 | accepted |
| 0007 | Binding decisions are recorded here (this process) | 2026-11-22 | accepted |
