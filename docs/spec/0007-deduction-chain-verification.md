# 0007. Deduction-chain case verification

**Status:** accepted
**Date:** 2026-11-28

## Context
Case generation verified only uniqueness via backtracking search
(`countSolutions`). Uniqueness does not imply a human-solvable path: a
player facing a unique case could not always deduce placements step by
step from the clue cards.

## Decision
Generated cases are verified solvable by a tiered deduction engine
(`lib/domain/deducer.dart`): easy = candidate filtering + naked/hidden
singles; standard and hard additionally use uniqueness probes
(contradiction-based cell elimination). The clue-selection loop gates on
full chain solvability, and a final assertion re-verifies the exact
shipped clue set. The engine's ordered trace is the canonical
"solution hint" algorithm. Uniqueness remains guaranteed (sound
propagation to full placement implies exactly one solution).

## Alternatives considered
- Minimize-to-unique, then reject on a chain check — smallest diff, but
  wasted full search effort per rejected attempt and acceptance dropped,
  especially easy. The gate-predicate swap costs the same code and
  converges directly to leaner sets. Rejected.
- Chain-first construction (place, find clues realizing it, verify) —
  most control, most code, fights the pool/prune economy. Rejected.
- Single-card-only steps — contradicts the owner's own framing
  («combination of cards 1..n»). Rejected.

## Consequences
- Seeded cases change for nearly all seeds: golden digests and the
  attempt-seed convergence table are regenerated in the same change.
- Generation acceptance drops where the chain is strict (easy);
  probe-convergence measurements pin the attempt rates.
- A future player-facing hint UI would reuse this engine; it stays out
  of scope of the landing issue.
