# 0006. Quality gate pipeline (format, lints, CRAP ratchet)

**Status:** accepted
**Date:** 2026-11-22

## Context

CI ran analyze + test only; formatting, complexity, and coverage were unenforced, and
no conventions document existed. No free, maintained CRAP tool exists for Dart (DCM is
commercial), and repo guardrails cap dev dependencies and require offline operation.

## Decision

Adopt a hand-rolled quality pipeline: a pre-commit hook (`dart format
--set-exit-if-changed` + `flutter analyze`) via a committed `.githooks/` directory
activated with `core.hooksPath`; a curated lint set layered on `flutter_lints`; and
`tool/crap_check.dart` computing CRAP = comp² × (1−cov)³ + comp per method (analyzer AST
+ lcov from `flutter test --coverage`) with threshold 5, enforced as a ratchet against
`tool/crap_baseline.json` in CI and `make quality`. Gate scope is `lib/**` minus
generated code; `test/`, `tool/`, and `integration_test/` are formatted and linted but
excluded from CRAP because they yield no coverage data. `analyzer` is the sole new dev
dependency.

## Alternatives considered

DCM (commercial license, heavyweight dependency, no coverage-aware CRAP out of the box);
`very_good_analysis` (new dependency, rule churn outside our control); report-only CRAP
(unenforced metrics rot); fix-all-now rollout (deep refactor of verified solver code,
regression risk).

## Consequences

Future work must add no new or worsened CRAP violations and keep code formatted and
lint-clean; the baseline burns down toward deletion; adding further dev dependencies
still requires amending AGENTS.md's guardrail line.
