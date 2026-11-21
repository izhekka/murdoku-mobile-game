# 0003. Agent factory: canonical .agents/agents/ + make init projections

**Status:** accepted
**Date:** 2026-11-21

## Context
Agent definitions were duplicated per harness (.zcode/agents/,
.claude/agents/) with diverging formats. Commit c2e4445 introduced a
canonical agent factory: 4 agents in .agents/agents/*.md (portable
core: name, description, optional tools, body) projected by the root
Makefile (`make init zcode|claude`) into the harness dirs.

## Decision
- Edit agents ONLY in `.agents/agents/*.md`, then run
  `make init zcode claude`; never hand-edit the projections.
- `.zcode/` and `.claude/` are gitignored local artifacts — a fresh
  clone must run `make init zcode claude` before its harness sees the
  agents. Commits carry `.agents/` + Makefile only, never `.zcode/`.
- Agents NEVER push, force-push, or rewrite history — pushing stays
  with the owner (branch → squash → main per docs/git-workflow.md; the
  owner authorizes every push).

## Alternatives considered
- Per-harness canonical dirs — rejected: divergence and double
  maintenance.
- A sync script — rejected by the owner in favor of `make init`
  projections.

## Consequences
Every agent change is a two-step edit + project; machines without the
projections need the make step before their harness sees agents; the
no-push rule means an executor's finished work waits for owner
authorization to reach origin.
