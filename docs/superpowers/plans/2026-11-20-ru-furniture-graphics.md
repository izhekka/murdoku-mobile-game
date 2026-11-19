# Murdoku Addendum: Russian default, furniture, item graphics

> **For the implementing model:** execute tasks in order, TDD, commit after each.
> Binding spec additions below amend the original plan's §2. The original §2.6
> non-goals are amended: localization beyond English and item graphics are now IN
> scope. The zero-binary-assets constraint is amended by Task 3 (CC0 sprites in
> `assets/items/`, with graceful fallback to Material icons if assets are absent).

**Goal:** Russian-first UI with grammatically correct clues; furniture on the map
(some cells occupiable, some blocking); real graphics for items.

## A. Localization design (Task 1)

- Add `lib/l10n/app_ru.arb` — full translation of every key. `supportedLocales`
  becomes [ru, en] automatically from the arb files.
- **Default locale is Russian, forced** (`locale: Locale('ru')`), overridable in
  Settings with a new language selector (system / русский / English) persisted via
  `Settings.language` (`language` enum: system, russian, english; default russian).
  Resolution: setting `russian` → `Locale('ru')`, `english` → `Locale('en')`,
  `system` → platform locale clamped to supported.
- **Names are content, localized by pool index.** `Suspect` and `RoomDef` gain
  `poolIndex` (int; `-1` = use the stored `name` string as-is). The factory records
  the pool position. Display resolution:
  - EN: existing `name` strings (unchanged behavior).
  - RU: Dart pools in `lib/domain/localized_names.dart` — NOT arb (they are
    content with morphology, like the English pools already are):
    `ruSuspectForms: List<(nom, gen)>` (16 entries),
    `ruRoomForms: List<(nom, prepPhrase)>` (16 entries, prepPhrase includes
    «в/на»: «в библиотеке», «на чердаке»),
    `ruObjectForms: Map<ObjectKind, (nom, gen)>`.
- **Clue grammar (ru) uses only two name forms:**
  - InRoom: `{name} — {roomPrepPhrase}.` → «Эшли — в библиотеке.» / «...на чердаке.»
  - SameRow/SameCol: `{name} — на том же этаже, что и {target}.` (nominative both)
  - Direction: `{name} — {dir} {target}.` with **genitive** target («севернее Веры»)
  - Beside / BesideObject: `{name} — около {target}.` with **genitive**
    («около Джека», «около стола»)
  - Alibi: `У {gen} железное алиби.`
  - EN templates unchanged.
- `describeClue` gains a `NameForms` resolver parameter
  (`NameForms.of(locale)`) providing `nom(id)`, `gen(id)`, `roomPrep(roomId)`,
  `objectNom(kind)`, `objectGen(kind)`; the victim resolves to
  «жертва» / «жертвы» (ru) or "the victim" (en).
- Tests that hardcode English sentences (suspect panel, etc.) pin the locale to
  `en` explicitly; tests using `l10nOf(tester)` keep working under ru automatically.

## B. Furniture design (Task 2)

- `ObjectKind` gains: `table, chair, flowers, sofa, bookshelf, lamp` (14 kinds total).
- `ObjectDef` gains `occupiable` (bool). Mapping `kindOccupiable(kind)`:
  chair, sofa → true; everything else → false (data-driven, single source).
- Per difficulty (amends §2.3): furniture counts —
  easy: 3 occupiable + 5 blocking; standard: 4 + 6; hard: 5 + 9
  (`objectCount` stays as occupiable+blocking total via new extension getters
  `occupiableCount`, `blockingCount`).
- Generation order (amends Task 5 pipeline): placement search first (unchanged),
  then furniture: blocking items only on empty cells (never under a solution
  guest, never on the victim, never two items on one cell); occupiable items on
  empty cells or under solution guests; occupiable never on the victim cell.
  Solvability is structural (the solution uses no blocking cells; blocking only
  shrinks the candidate space → uniqueness machinery unchanged).
- Engine changes: solver's DFS skips blocking cells; `canPlace` rejects blocking
  cells; `Difficulty` extension gains `occupiableCount`/`blockingCount`.
- Old `objectCount` getter maps to occupiable+blocking total for compatibility.
- Clue pool unchanged (BesideObject candidates grow with more furniture).
- UI: furniture icons render under guests (guest on top); occupiable vs blocking
  affordance; semantics label gains furniture info; clue strings use furniture
  names; how-to-play mentions furniture.

## C. Graphics (Task 3)

- Primary: **Kenney "Roguelike Modern" pack (CC0 license — no attribution
  required)**. Download the zip, extract furniture tiles, crop per-item PNGs into
  `assets/items/<kind>.png` via `tool/extract_items.dart` (package:image).
  Pixel-art tiles (16–32 px) scaled with `FilterQuality.none` to match the
  top-down map aesthetic.
- Fallback: `ItemSprite` widget uses `Image.asset` with `errorBuilder` → styled
  Material icon (existing behavior), so the app is never broken by a missing asset.
- Declare `assets/items/` in pubspec. Web build serves them via the dev server.

## Tasks

### Task 18: Russian localization + language setting + localized names
Files: `lib/l10n/app_ru.arb`, `lib/l10n/app_en.arb` (new keys only),
`lib/domain/models.dart` (poolIndex), `lib/domain/localized_names.dart`,
`lib/ui/widgets/suspect_panel.dart` (describeClue + resolver), settings
(language), app.dart (locale resolution), `tool`-level test helpers.
Tests: en/ru arb key parity; default locale is ru; language setting resolution;
clue sentence grammar for both locales (exact strings); name form resolution.

### Task 19: Furniture mechanics
Files: models (kinds, occupiable, counts), game_logic (canPlace), solver,
case_factory (furniture placement), clue_eval unchanged, board_view rendering,
game_screen/how-to-play copy. Tests: canPlace blocking; solver skips blocking;
property test over 150 seeds with furniture (validity + uniqueness + counts +
determinism); rendering tests.

### Task 20: Item graphics
Files: `tool/extract_items.dart`, `assets/items/`, pubspec assets, ItemSprite
widget, board_view integration. Tests: ItemSprite fallback path; asset presence
when downloaded (skippable if network blocked).

### Task 21: Full regression + smoke update + commit
Update integration smoke test for ru default + furniture; full gate; final commit.
