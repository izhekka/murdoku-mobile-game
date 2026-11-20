# Murdoku UX/Usability/A11y Improvement Plan

> **For the implementing model (glm-5.3-flash):** execute tasks **UX-1 … UX-6 in order**,
> TDD (failing test first), gate after every task (`flutter analyze` 0 issues &&
> `flutter test` all pass), commit after every task. If a fix fails twice after genuine
> debugging, STOP and report instead of weakening tests. Never edit
> `lib/l10n/generated/**` or other generated output. All user-facing strings via
> AppLocalizations (arb, en+ru key parity). No new runtime dependencies.
>
> Context: the app is complete and reviewed (see
> `2026-11-19-murdoku-flutter-app.md` and `2026-11-20-ru-furniture-graphics.md`).
> This plan fixes real usability findings from a live review of the running game
> (mobile viewport 412×915) plus the human owner's explicit complaints.

## Findings this plan addresses (evidence from live review)

- **F-0 (P0 BUG):** `case_factory.dart` builds `RoomDef`/`Suspect` **without
  `poolIndex`**, so every generated case shows English names («в Парlor», «Noel»,
  «Frank») even in the Russian UI. Task 18's unit tests used hand fixtures and
  masked this. Verified: no `poolIndex` argument at `case_factory.dart:47`.
- **F-1 (owner):** color scheme and graphics are not bright/colorful enough for an
  attractive game; room tints are muddy and hard to tell apart.
- **F-2 (owner):** item sprites are not game-ish, look like dark squares on the dark
  board.
- **F-3 (owner):** the suspect list is a horizontally scrolling strip showing ~2.5
  of 5 cards with truncated clue text. Owner wants a **3×2 grid** of 6 cards.
- **F-4:** bottom toolbar is 7 unlabeled icon buttons; no visible labels, cramped
  targets.
- **F-5:** large dead vertical space between board and suspect panel; board uses
  only ~40% of screen height.
- **F-6:** clue text wraps to 4 cramped lines inside small cards.
- **F-7:** game screen has no text-scale stress test (only the isolated BoardView
  has one).

## Global constraints (unchanged)

- Runtime deps exactly: flutter_riverpod, go_router, shared_preferences (+ template
  defaults material_ui, cupertino_icons; + cupertino_ui from the localization fix).
- TDD per task; full-suite green + analyze 0 before each commit; commit per task.
- arb key parity en↔ru must hold at all times (`test/l10n/localization_test.dart`
  enforces it — new keys go into BOTH files).
- A11y minimums: 48dp interactive targets, Semantics on every interactive element,
  usable at textScale 2.0, AA contrast in dark mode.

---

### UX-1 (P0): factory sets poolIndex — Russian names in generated cases

**Files:** modify `lib/domain/generator/case_factory.dart` (suspect + room
construction, ~line 47), `test/domain/generator/case_factory_test.dart`.

- [ ] **RED:** property test additions inside the 150-seed loop:
  `expect(c.suspects.every((s) => s.poolIndex >= 0 && s.poolIndex < 16), isTrue)`
  and the same for `c.rooms`. Also: for seed 1 easy, assert
  `c.rooms.any((r) => r.poolIndex == 1)` (proves distribution, not constants).
- [ ] **GREEN:** in `_attempt`, build suspects with `poolIndex: i` and rooms with
  `poolIndex: i` (both pools are index-aligned, 16 entries).
- [ ] Verify the rendered clue grammar test still passes (ru prep phrases come from
  the pools — with poolIndex set, generated cases show «в библиотеке», not
  «в Парlor»).
- [ ] **Commit:** `fix(generator): set poolIndex so Russian names render in generated cases`

### UX-2 (P0 UX): suspect panel → 3×2 grid with expandable selected card

**Files:** `lib/ui/widgets/suspect_panel.dart`, `lib/ui/screens/game_screen.dart`
(panel slot height), `test/ui/widgets/suspect_panel_test.dart`,
`test/ui/screens/game_screen_test.dart` (may need tap coordinates updated).

- [ ] **RED:** widget test — pump `SuspectPanel` with a 5-suspect generated case:
  `find.byType(GridView)` count 1; `find.byType(GridView)` has
  `physics: NeverScrollableScrollPhysics` when suspects ≤ 6; the panel shows **6
  slots** (5 cards + 1 empty decorative slot) in 3 columns × 2 rows; horizontally
  scrolling `ListView` is gone (`find.byType(ListView)` inside the panel → 0).
- [ ] **RED:** selected card expands — tap card 1, its clue `Text` has
  `maxLines: null` (visible fully); unselected cards show at most 2 lines
  (ellipsis).
- [ ] **GREEN implementation:**
  - `GridView.count(crossAxisCount: 3, shrinkWrap: true,
    physics: suspects.length <= 6 ? NeverScrollableScrollPhysics() :ClampingScrollPhysics(),
    childAspectRatio: ~1.05, padding: EdgeInsets.all(4), mainAxisSpacing: 4,
    crossAxisSpacing: 4)`.
  - Card layout (compact): avatar 24 + name (ellipsis) on one row; clue block
    below — selected card: `Expanded` scrollable full clues; unselected:
    `Text(maxLines: 2, overflow: ellipsis)`.
  - Placed check icon stays. 7th+ suspect (hard) → grid scrolls vertically.
  - Panel slot height in `game_screen.dart`: 160 → ~205 (two grid rows); keep
    SafeArea/toolbar layout stable.
- [ ] A11y: each card `Semantics(button: true, label: '{name}. {first clue}.')`.
- [ ] Update `game_screen_test` tap flow if card positions changed.
- [ ] **Commit:** `feat(ui): suspect panel as 3x2 grid with expandable selected card`

### UX-3 (P1): brighter palette and room colors

**Files:** `lib/core/theme.dart`, `lib/ui/widgets/board_view.dart`,
`test/core/theme_test.dart` (new), board tests.

- [ ] **RED:** theme test — new `roomColors` palette: for the first 7 colors,
  every pairwise pair has a minimum color distance
  (`((r1-r2)^2+(g1-g2)^2+(b1-b2)^2) > 9000`) so rooms are tellable apart; each
  color's HSL lightness in 0.45–0.75 (bright, not muddy).
- [ ] **GREEN:** replace `_roomPalette` with 8 vivid, distinct hues (suggested:
  amber #E0A458, teal #3FB8AF, orchid #B07CC6, coral #E26D5C, lime #9ACD5A, sky
  #58A6DC, magenta #D16BA5, sand #D8B26E — tune as needed for AA in dark mode).
- [ ] Board tint strength: cell fill alpha 0.35 → 0.55; the "blocked rows/cols"
  overlay stays subtle. Guest avatar palette: brighter (raise lightness of
  `suspectColors` similarly; test optional).
- [ ] Check both themes manually via the running web server (loopback) — bright
  and readable in dark mode.
- [ ] **Commit:** `feat(ui): vivid room palette and stronger board tints`

### UX-4 (P1): item sprites v2 — bright, game-ish, bigger

**Files:** `tool/gen_items.dart`, `assets/items/*` (regenerated),
`lib/ui/widgets/board_view.dart`, `lib/ui/widgets/legend_sheet.dart`, tests.

- [ ] Rewrite the sprite palette: bright saturated fills (wood #C98A4B, fabric
  #7FA8E0, leaf #6FBF5A, metal #B8BEC9, accent amber #F0B24A, red #E05A5A), keep
  the dark outline only as a thin 2px border at 128px scale; no near-black fills
  (the current piano is #222029 — replace with #3A3648 + bright keys).
- [ ] Items fill ~80% of the canvas (scale shapes up — coordinates are literal,
  multiply by ~1.25 where the shape allows).
- [ ] Regenerate (`dart run tool/gen_items.dart`); visually verify via the web
  server screenshot that items pop on the board.
- [ ] Board render size: centered furniture 24 → 28; legend 28 → 30.
- [ ] Tests: existing sprite-count/layering tests must stay green (no behavior
  change — this task is visual).
- [ ] **Commit:** `feat(assets): bright game-style item sprites v2`

### UX-5 (P1): toolbar labels + a11y pass

**Files:** `lib/ui/screens/game_screen.dart`, `lib/l10n/app_en.arb`,
`lib/l10n/app_ru.arb`, tests.

- [ ] **RED:** widget test — each toolbar button has a visible text label under
  its icon AND `Semantics(label: ...)`; assert labels for all 7 buttons using new
  arb keys (toolPlace/toolMark/toolErase/toolUndo/toolCheck/toolHint/toolAccuse;
  en: Place/Mark/Erase/Undo/Check/Hint/Accuse; ru: Поставить/Крестик/Стереть/
  Отменить/Проверить/Подсказка/Обвинить).
- [ ] **GREEN:** replace raw `IconButton`s with two-line mini buttons
  (`Column[Icon, Text(size 10)]`, min width 48, height 52, tooltip kept).
- [ ] Timer text gets `Semantics(label: '{difficulty}, прошло {time}')` (ru) /
  English equivalent — new arb key `timerSemantics`.
- [ ] Text-scale stress: new test pumping the **whole game screen** at
  textScale 2.0 (412×915) asserting no overflow exceptions (closes finding F-7 —
  the suspect grid from UX-2 is the risk area; clue text must ellipsize, not
  overflow).
- [ ] **Commit:** `feat(ui): labeled toolbar, timer semantics, full-screen text-scale test`

### UX-6 (P2): layout polish

**Files:** `lib/ui/screens/game_screen.dart`, board/panel sizing.

- [ ] Vertical distribution: board gets `flex: 5` (was 3), suspect grid fixed
  ~205px, toolbar fixed; verify on 412×915 and 320×569 that nothing overflows and
  the board is the dominant element (no dead gap between board and panel).
- [ ] `flutter test` + manual screenshot review via the loopback web server.
- [ ] **Commit:** `feat(ui): tighter game screen layout`

### UX-7: regression + on-device verification

- [ ] Full gate: `flutter analyze` 0, `flutter test` all pass.
- [ ] Integration smoke on the Android emulator (ru locale) — update it if the
    grid changed tap flow; furniture + sprites + legend still asserted.
- [ ] Manual screenshot review at 412×915: home, game (empty + solved), legend,
    settings — compare against the findings list; note anything still off in the
    commit message.
- [ ] **Commit:** `feat(ux): regression pass and on-device verification`

## Out of scope (this plan)

Sound/music, animations beyond Material defaults, new game mechanics, new
dependencies, iOS build.
