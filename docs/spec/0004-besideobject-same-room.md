# 0004. BesideObject clues mean the same room

**Status:** accepted
**Date:** 2026-11-21

## Context
Live play-testing showed a BesideObject clue («около предмета»)
pointing to a Manhattan-adjacent cell behind a wall, which read as
wrong to players: the clue's plain meaning is sharing the item's room.

## Decision
BesideObject («около предмета» / "beside the {object}") asserts the
guest is in the SAME ROOM as the item — not an adjacent cell. The
SUSPECT-beside clue («около <suspect>», "adjacent to {name}") keeps
Manhattan adjacency — the two clue kinds are deliberately different;
do not merge them. Execution is tracked as issue #1 (touches
clue_eval.dart; ru item forms need the instrumental case; old
BesideObject tests flip to the new semantics).

## Alternatives considered
- Keep adjacency and reword the clue — rejected: the room reading is
  what players actually expect from «около предмета».
- Make both clue kinds room-based — rejected: Manhattan adjacency
  between suspects is a distinct, useful deduction axis.

## Consequences
Clue generation, evaluation, and the ru/en templates change together;
existing BesideObject tests flip; future clue kinds must not silently
reuse the "beside" wording for two different relations.
