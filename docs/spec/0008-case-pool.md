# 0008. Pre-generated case pool for new cases

**Status:** accepted
**Date:** 2026-11-28

## Context
Case generation runs synchronously on the UI isolate at new-case start.
Deduction-chain gating (ADR 0007) raised generation cost; hard 9×9 can block
the UI for seconds (issue 98). Flutter cannot run Dart after the app closes
without plugins, and runtime dependencies are frozen.

## Decision
Persist per-difficulty pools of pre-generated unstarted CaseData in
shared_preferences under a versioned envelope carrying a generator-pipeline
tag (`casePoolGeneratorTag`, starts at 1; bumped when generation semantics
change). New cases are served by random pop from the pool; pools below 5
cases are refilled by batches of 10 generated in `Isolate.run` while the app
is open (single-flight per difficulty, checks at home init and after every
pick); an empty pool falls back to synchronous generation (today's exact
behavior) and still triggers the background refill. Generator-tag mismatch
discards stored pools, so pipeline changes never serve stale-quality cases.
`forcedSeed` (integration tests) bypasses the pool entirely; daily cases
stay seed-deterministic and outside the pool.

## Alternatives considered
- Only rework the solver (#98) — makes generation fast but still synchronous
  and on the critical path; the pool hides the cost class entirely during
  play. Complementary; re-measure the empty-pool fallback after this lands
  and re-judge #98 with data. Deferred.
- Files instead of shared_preferences — no benefit at this size (≤ 45 stored
  cases, a few hundred KB of JSON worst case); prefs already has the
  versioned-envelope pattern and is an existing dependency. Rejected.
- Memory-only pool (no persistence) — refills lost on every launch; the
  first case of every session would hit the synchronous path. Rejected.

## Consequences
Generation cost moves off the critical path during play; a cold start with
an empty pool still pays synchronous generation (re-measure issue 98 after
landing). A new storage entity and its invalidation protocol (the
generator-tag bump) must be maintained; daily cases stay seed-deterministic
and outside the pool; `resetProgress` intentionally keeps the pool (it is
anonymous content, not progress).
