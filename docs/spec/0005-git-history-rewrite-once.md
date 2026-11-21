# 0005. Git history was rewritten once; never rewrite it again

**Status:** accepted
**Date:** 2026-11-21

## Context
All 53 commits on main were rewritten (2026-11-21) so author+committer
email is izhekka@gmail.com; all hashes changed and the old history was
permanently purged at the owner's request (refs/original deleted,
reflogs expired, aggressive gc). The rewrite is irreversible — old
commit 50e9d83 is unrecoverable.

## Decision
Git history is never rewritten again — no force-push, no filter-branch,
no rebase of pushed history — without the owner's explicit per-case
authorization. Normal work lands via branch → squash-merge into main
(docs/git-workflow.md); fixes are new commits, never rewrites.

## Alternatives considered
- Keep pre-rewrite backup refs — rejected by the owner: purged
  permanently.
- Treat the rewrite as repeatable cleanup tooling — rejected: the purge
  makes any further rewrite destructive with no recovery path.

## Consequences
A mistaken push can only be fixed with a forward commit; anything that
looks like history surgery must stop and ask the owner first.
