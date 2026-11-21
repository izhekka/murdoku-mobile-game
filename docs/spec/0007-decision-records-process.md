# 0007. Binding decisions are recorded here (this process)

**Status:** accepted
**Date:** 2026-11-22

## Context
Binding decisions (rules that future contributors or agents must not
violate) lived only in conversations and agent-side memory — invisible
to a fresh clone and to anyone reading the repo. Records 0001–0006
backfill decisions taken before this process existed.

## Decision
Adopt this decision-records process: scope = decisions that bind future
work (the test in README); the orchestrator drafts a record during the
brainstorm, the record travels inside the task issue's Context, the
executor commits it on the task branch; a decision with no code task
rides a tiny `docs:` issue. Records are immutable except Status;
reversal = a superseding record.

## Alternatives considered
- Single running DECISIONS.md — rejected: merges and edits blur what
  was decided when.
- Promoting full specs into docs/spec — rejected: specs are task-sized;
  decisions are smaller.
- Orchestrator commits records to main directly — rejected: bends the
  branch → squash pipeline.
- Owner-only manual records — rejected: relies on memory in the moment.

## Consequences
Every qualifying decision from now on adds one file here; task issues
grow a fenced record block when they carry a decision; the README index
is updated in the same commit that adds a record.
