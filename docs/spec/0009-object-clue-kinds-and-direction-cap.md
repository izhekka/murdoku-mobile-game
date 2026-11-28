# 0009. Object clue kinds and the direction-card cap

**Status:** accepted
**Date:** 2026-11-28

## Context
After issue #106 (chain-verified generation) 71–80% of the shipped cards
were direction cards («south of Blair»): the clue pool listed direction
candidates ahead of beside and item cards, and the greedy picker filled
the set with them. A direction card is a half-map relation; several at
once must be held in mind together, which players find hard to follow.
The furniture already on the board carries local facts no card expressed:
a guest sits on a seat, stands next to a table. ADR 0004 made
BesideObject mean the item's ROOM, not its neighbourhood, so that kind
cannot express them.

## Decision
Three item-anchored clue kinds join the model, persisted and deduced:
- `OnObject` — the guest's cell is the item's cell (seats only);
- `NearObject` — the guest's cell is the item's cell or orthogonally
  adjacent to it;
- `SoleNearObject` — `NearObject` for the card's guest AND no other
  guest near the item.
Positive item clues never reference items standing in the victim's room
(the issue #93 killer-naming rule). A case ships at most two
`DirectionClue` cards in total; the generator drops an attempt instead of
exceeding the cap or shipping a killer-naming card. `BesideObject` keeps
its same-room meaning (ADR 0004); "near" wording is reserved for
`NearObject` and `SoleNearObject`.

## Alternatives considered
- Keep direction cards and explain them better in the tutorial —
  rejected: the load is holding several half-map relations at once, not
  the explanation.
- Place seats under guests so «sits on» pins most guests — measured: 97%
  of layouts solve, but 3–4 guests are pinned outright and the near and
  only-guest cards become decoration. Rejected.
- Constructive generation (choose the clue set first, furnish to match)
  — most control, largest rewrite; rejected for the pool/prune economy
  reasons of ADR 0007.

## Consequences
- Prototype measurement of this design: 90% / 61% / 68% of layouts
  (easy / standard / hard) chain-solve under the cap, most with no
  direction card; in 31–57% the murderer has no legal card and the layout
  is dropped. The existing retry budget absorbs both.
- Every stored generator pin regenerates; `casePoolGeneratorTag` bumps so
  stored case pools are discarded.
- New clue kinds must keep the three anchor families distinct: room
  (`InRoom`), item room (`BesideObject`), item cell or neighbourhood
  (`OnObject`, `NearObject`, `SoleNearObject`).
