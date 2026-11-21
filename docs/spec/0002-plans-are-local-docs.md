# 0002. Plans and specs are local working docs

**Status:** accepted
**Date:** 2026-11-21

## Context
Superpowers development plans (docs/superpowers/plans/) and brainstorm
specs (docs/superpowers/specs/) were originally committed as part of
the task flow. The owner decided internal working docs should not live
in the public tree; commit c2e4445 gitignored docs/superpowers/ and
deleted the plan files from the working tree.

## Decision
`docs/superpowers/` is gitignored. Plans and specs are LOCAL working
docs: never committed, never pushed. They survive in git history only
(e.g. `git show e1cfe52:docs/superpowers/plans/<name>.md`) and are not
required for executing filed issues — issues must be self-contained.

## Alternatives considered
- Keep committing plans — rejected: the public tree should not carry
  internal working docs.
- A private second repo for plans — rejected: two sources of truth.

## Consequences
A fresh clone has no plans and no specs; the executor writes its plan
locally and does not commit it; any knowledge an executor needs must be
inside the issue body. Durable decision knowledge lives in docs/spec/
(see 0007) instead.
