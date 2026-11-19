# Murdoku (Flutter) Implementation Plan

> **For the implementing model:** Work through tasks **in order**, one at a time. Steps use
> `- [ ]` checkboxes — tick them in this file as you complete them. After every task run the
> full gate (`flutter analyze && flutter test`) and commit before starting the next task.
> If a task fails twice after genuine debugging attempts, STOP and report the failure with
> the command output instead of working around it. Do not weaken, skip, or delete tests.

**Goal:** A production-ready, offline mobile puzzle game where the player places murder-mystery
guests onto a mansion map (one guest per row, column, and room) using clue cards, then accuses
the guest who ends up alone with the victim.

**Architecture:** Pure-Dart puzzle engine (generation, clue evaluation, uniqueness solver) with
no Flutter imports, tested independently; Riverpod state layer connecting engine to UI; a
screen-per-feature Flutter UI with zero external assets (all visuals drawn with Material icons,
`CustomPainter`, and themed colors). Everything is procedural and seeded, so content is infinite
and reproducible (daily cases).

**Tech Stack:** Flutter (stable channel), Dart 3, `flutter_riverpod` (manual providers, no
codegen), `go_router`, `shared_preferences`, `flutter_test`, `integration_test`,
`flutter_gen_l10n` (en). Dev-only extra: `image` + `flutter_launcher_icons` for icon generation.

**Spec:** This document is self-contained. §2 *Game Design Spec* is the binding spec — every
task argues from it. Design informed by the original Murdoku rules
(https://murdoku.fans/en/how-to-play).

---

## 1. How to Execute This Plan

You (the implementing model) are building this app in an **empty repository** from scratch.
You have no conversation history beyond this file. Rules of engagement:

1. Work at the repository root. Task 0 creates the Flutter project **in place**.
2. **Task order is strict.** Later tasks consume exact interfaces produced by earlier tasks
   (declared in each task's *Interfaces* block). Never rename them.
3. **TDD:** in every task with tests, write the test first, watch it fail, implement, watch it
   pass. Never write implementation before its failing test exists.
4. **Gate after every task:** `flutter analyze` (zero issues) && `flutter test` (all pass).
   Only then commit (Task 0 sets up git; use the commit messages given in each task).
5. **Guardrails — do NOT:**
   - Add any package not listed in §3 Global Constraints (only exception: the two dev-only
     packages in Task 17).
   - Use code generation / `build_runner` / freezed / json_serializable. JSON is hand-written.
   - Add networking, analytics, ads, or tracking. The app is fully offline and collects nothing.
   - Put user-facing strings anywhere except `AppLocalizations` (arb file) once l10n exists
     (Task 7 onward).
   - Edit files under `*/.dart_tool/`, `*.g.dart`, or `.github/` generated output.
   - Change public APIs declared in an *Interfaces* block of an earlier task.
6. Flutter is **not installed** on this machine at plan-writing time. Task 0 installs it.
7. Where this plan says "record" a version, write it into the file you are told to record it in,
   verbatim from command output.

---

## 2. Game Design Spec (binding)

### 2.1 Core puzzle

- A **case** is played on a `G × G` square grid ("the mansion map"), where `G` is 5 (easy),
  6 (standard), or 7 (hard). Rows are numbered 0..G−1 top→bottom, columns 0..G−1 left→right.
- The grid is partitioned into exactly `G` **rooms**: orthogonally contiguous regions of
  roughly equal size (every cell belongs to exactly one room).
- There are `G` **guests** (suspects). The player must place every guest so that:
  1. each **row** contains exactly one guest;
  2. each **column** contains exactly one guest;
  3. each **room** contains exactly one guest.
- The **victim** is a fixed marker `V` printed on one cell of the map from the start. It is not
  placed by the player, does not block a row/column, and does not count against a room's
  capacity. Its cell cannot hold a guest (a cell holds at most one thing).
- 2–4 **objects** (piano, plant, suit of armor, chest, clock, globe, portrait, fireplace) are
  printed on cells that are empty in the solution. They never block placement rules; they only
  appear in clues.
- **The murderer** is the guest placed in the same room as the victim. By construction each
  room has exactly one guest, so exactly one guest shares the victim's room.
- Every **clue card** is TRUE for the solution ("every clue must be true — a rule, not a hint").
- The clue set makes the placement **uniquely solvable by logic** (verified by exhaustive
  solver: exactly 1 valid placement satisfies all rules + clues).

### 2.2 Clue taxonomy (complete for v1)

Target `t` in a clue is either a guest id (`s0`..`s(G−1)`) or `"V"` (the victim).
Directions: north = smaller row, south = larger row, west = smaller column, east = larger
column. "Beside" = orthogonally adjacent (Manhattan distance 1). A clue may be **negated**
("…was NOT…"). All clues are per-suspect statements shown as cards under that suspect's
portrait.

| Clue | Positive wording (en) | Semantics (true iff) |
|---|---|---|
| `InRoom(s, room)` | "{name} was in the {room}." | `roomOf[pos[s]] == room` |
| `SameRow(s, t)` | "{name} was on the same floor as {target}." | `pos[s].row == posTarget.row` |
| `SameCol(s, t)` | "{name} was in the same corridor as {target}." | `pos[s].col == posTarget.col` |
| `DirectionClue(s, t, dir)` | "{name} was {dir} of {target}." (e.g. "north of") | strictly: row/col comparison per direction |
| `Beside(s, t)` | "{name} was beside {target}." | `manhattan(pos[s], posTarget) == 1` |
| `BesideObject(s, obj)` | "{name} was beside the {object}." | `manhattan(pos[s], obj.pos) == 1` |

Negations invert the predicate. `Direction` means *strictly* anywhere in that half
(not necessarily aligned). A clue may not reference the guest it is attached to as its own
target (`s == t` forbidden), and `InRoom` never targets `"V"`.

### 2.3 Difficulty table

| Difficulty | Grid G | Objects | Target clue count | Retry budget |
|---|---|---|---|---|
| easy | 5 | 2 | 6–9 | 40 seeds |
| standard | 6 | 3 | 8–12 | 40 seeds |
| hard | 7 | 4 | 10–14 | 40 seeds |

If no seed in the budget yields a unique puzzle within the clue-count window, widen the max
clue count by +1 and retry the whole budget (still bounded; log via `debugPrint`).

### 2.4 Player-facing rules (exact copy for the how-to-play screen)

1. "Each guest appears exactly once in every row, column and room — like a sudoku of suspects."
2. "Every clue is true. Clues are rules, not hints."
3. "The map is evidence — rooms and objects are where the story happens."
4. "One guest shares a room with the victim. That guest is the murderer. Find them last."

### 2.5 Game flow & UI (v1 scope)

- **Home:** Continue case (if a save exists), New case (difficulty chooser; confirms and
  discards a running save), Daily case (locked to today's UTC date; shows done/undone),
  links: How to play, Statistics, Settings. First launch shows the tutorial overlay.
- **Playing:** Map board on one side, suspect panel (portrait + clue cards) on the other
  (stacked on portrait phones). Tap a suspect to select → tap a cell to place. Tap a placed
  suspect to remove it. **X tool** toggles elimination marks by tap or drag. **Eraser** clears
  marks on a cell (drag supported). **Undo** undoes any move. **Check** reports
  "N of G guests are correctly placed" (unlimited; costs nothing but pride). **Accuse** opens
  a suspect chooser; wrong accusation shows "{name} has an airtight alibi." and increments the
  mistake counter; correct accusation → victory. Placing all G guests correctly also prompts
  to accuse. **Pause menu:** resume, how to play, reveal solution (forfeits), quit to home.
- **Timer:** counts up while the screen is visible; pauses when app is backgrounded.
- **Victory:** time, difficulty, mistakes; updates stats; marks daily complete.
- **Hints (2 per game):** Hint A places one not-yet-placed guest correctly (locks it);
  Hint B eliminates one innocent suspect from the accusation sheet for this game.
- **Statistics:** per-difficulty solved/best/average time, current daily streak, total cases.
- **Settings:** theme (system/light/dark), haptics on/off, reset all progress (confirm).
- **Save/resume:** the active case (including marks and elapsed time) persists across app
  restarts; finishing or quitting clears it.
- **Daily:** `dailySeedFor(date) = date.year * 10000 + date.month * 100 + date.day` (UTC).
  One daily attempt per UTC day; streak logic in Task 15.

### 2.6 Non-goals for v1 (do not build)

Sound/music, animations beyond implicit Material motion, blocked/furniture cells, multi-house
maps, hand-authored stories beyond template flavor text, iCloud/Google-save sync, tablets
layout beyond graceful scaling, localization beyond English (but all strings via l10n).

---

## 3. Global Constraints

- Flutter **stable** channel; record the installed version (Task 0) and keep CI on `stable`.
- Runtime dependencies, exactly these three: `flutter_riverpod` (≥ 2.6), `go_router` (≥ 14),
  `shared_preferences` (≥ 2.3). Dev: `flutter_test`, `integration_test`, `flutter_lints`
  (defaults from `flutter create`), plus `image` and `flutter_launcher_icons` in Task 17 only.
- No code generation, no `build_runner`, no reflection. Hand-written `toJson`/`fromJson`.
- All user-visible strings via `AppLocalizations` from Task 7 on.
- 48 dp minimum touch targets; semantic labels on every interactive board element; app must be
  usable at OS text scale 2.0 and in dark mode.
- App works fully offline; no permissions requested; Android `targetSdk`/iOS deployment
  target keep `flutter create` defaults.
- Working title "Murdoku" (⚠ trademark caution: the name belongs to an existing game — rename
  before store submission; Task 17 flags it).
- Bundle id `com.murdoku.game`; display name "Murdoku"; version `1.0.0+1`.
- Every task ends: `flutter analyze` → 0 issues, `flutter test` → all pass, then commit.

---

## 4. File Structure (target)

```
lib/
  main.dart                        # bootstrap: prefs, ProviderScope, zone error guard
  app.dart                         # MaterialApp.router, theme, locale, ErrorWidget.builder
  core/theme.dart                  # light/dark ThemeData, room palette
  core/routes.dart                 # GoRouter: /, /game, /how-to-play, /stats, /settings
  domain/models.dart               # Pos, Difficulty, Suspect, RoomDef, ObjectDef, Clue, CaseData, BoardState, Move
  domain/clue_eval.dart            # evaluateClue(...)
  domain/solver.dart               # countSolutions / firstSolution
  domain/generator/rooms.dart      # generateRooms(...)
  domain/generator/case_factory.dart # generateCase(...)
  domain/game_logic.dart           # canPlace, applyMove, correctCount, boardSolved
  storage/prefs_repository.dart    # settings/save/stats persistence (JSON in shared_preferences)
  state/settings_controller.dart
  state/game_controller.dart       # GameNotifier + GameState
  state/stats_controller.dart
  ui/screens/home_screen.dart
  ui/screens/game_screen.dart
  ui/screens/how_to_play_screen.dart
  ui/screens/stats_screen.dart
  ui/screens/settings_screen.dart
  ui/widgets/board_view.dart
  ui/widgets/suspect_panel.dart
  ui/widgets/avatar.dart           # colored circle + icon, no assets
  ui/widgets/accuse_sheet.dart
  ui/widgets/dialogs.dart          # win dialog, confirm dialogs
  ui/widgets/tutorial_overlay.dart
l10n/app_en.arb
integration_test/smoke_test.dart
tool/gen_icon.dart                 # generates app icon PNG (Task 17)
test/                              # mirrors lib/ (one _test.dart per source file)
docs/superpowers/plans/            # this plan
```

---

## 5. Review Focus

Failure modes the spec implies but individual tasks might not exercise — each is pinned to
its owning task's tests:

1. **Non-unique or lying puzzles ship** → Task 5 property test over 150 seeds asserts
   uniqueness + all-clues-true + murderer consistency for every difficulty.
2. **Corrupt/legacy save JSON crashes the app** → Task 6 tests garbage and wrong-version
   payloads; repository must return null and log, never throw.
3. **Tap races / illegal taps corrupt board** (tap occupied cell, tap during win state) →
   Task 8 pins exact behavior: placing onto an occupied cell is a no-op; input ignored unless
   phase == playing.
4. **Daily case played across midnight changes mid-game** → Task 15 pins daily identity to
   the date the daily was started, not the current clock.
5. **Huge text scale or tiny screen clips the board** → Task 10 widget test runs at
   textScale 2.0 on a 320×569 surface and asserts the board stays within bounds.

---

### Task 0: Toolchain, scaffold, CI, git

**Files:**
- Create: everything `flutter create` produces, `.github/workflows/ci.yml`, `AGENTS.md`
- Modify: `pubspec.yaml` (dependencies)

**Interfaces:**
- Produces: runnable app skeleton; CI green baseline; git repo with initial commit.

- [ ] **Step 1: Install Flutter (stable)**

macOS: clone into `~/development/flutter` (or use homebrew: `brew install --cask flutter`).
Verify: `flutter doctor -v` reports no blocking issues for Android toolchain; accept Android
licenses with `flutter doctor --android-licenses` if prompted. Xcode setup can be deferred to
Task 17 — do not block on iOS now.

- [ ] **Step 2: Record the toolchain**

Run `flutter --version`, then create `.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

Add `TOOLCHAIN.md` at repo root containing the exact `flutter --version` output.

- [ ] **Step 3: Create the project in place**

```bash
cd <repo root>
flutter create --org com.murdoku --project-name murdoku --platforms android,ios .
git init && git add -A && git commit -m "chore: flutter scaffold"
```

- [ ] **Step 4: Add dependencies & enable l10n**

```bash
flutter pub add flutter_riverpod go_router shared_preferences
```

In `pubspec.yaml` add `generate: true` under `flutter:`, create `l10n/app_en.arb` with
`@@locale: en` and one placeholder key `appTitle` = "Murdoku". Create
`lib/l10n/app_localizations.dart` shim? No — run `flutter gen-l10n` and import from
`package:flutter_gen/gen_l10n/app_localizations.dart`.

- [ ] **Step 5: Baseline verification**

Run: `flutter analyze && flutter test`
Expected: 0 issues; the default widget test passes. Commit:
`git commit -am "chore: deps and l10n baseline"`

- [ ] **Step 6: Write AGENTS.md**

Content: one paragraph pointing at this plan (`docs/superpowers/plans/2026-11-19-murdoku-flutter-app.md`)
as the binding execution order, plus the §1 guardrails summarized. Commit `docs: add agents guide`.

---

### Task 1: Domain models

**Files:**
- Create: `lib/domain/models.dart`
- Test: `test/domain/models_test.dart`

**Interfaces:**
- Produces (all in `lib/domain/models.dart`, all immutable):

```dart
enum Difficulty { easy, standard, hard }
// extension: int get gridSize => 5/6/7; int get objectCount => 2/3/4;
//            int get minClues => 6/8/10; int get maxClues => 9/12/14;

enum Direction { north, south, east, west }
enum ObjectKind { piano, plant, armor, chest, clock, globe, portrait, fireplace }

typedef Pos = ({int row, int col});            // Dart 3 record; json as [row, col]

class Suspect  { final String id; final String name; }        // id "s0"..; const ctor, ==/hashCode on id
class RoomDef  { final String id; final String name; final List<Pos> cells; }  // id "r0"..; roomOf helper
class ObjectDef{ final String id; final ObjectKind kind; final Pos pos; }      // id "o0"..

sealed class Clue { String get suspectId; bool get negated; }
class InRoom       extends Clue { final String suspectId, roomId; final bool negated; }
class SameRow      extends Clue { final String suspectId, targetId; final bool negated; } // targetId may be "V"
class SameCol      extends Clue { final String suspectId, targetId; final bool negated; }
class DirectionClue extends Clue { final String suspectId, targetId; final Direction direction; final bool negated; }
class Beside       extends Clue { final String suspectId, targetId; final bool negated; }
class BesideObject extends Clue { final String suspectId, String objectId; final bool negated; }

class CaseData {                                             // + copyWith
  final int seed; final Difficulty difficulty;
  final List<RoomDef> rooms; final List<ObjectDef> objects;
  final List<Suspect> suspects;                             // length == gridSize
  final Pos victimPos; final String murdererId;
  final List<Clue> clues;
  final Map<String, Pos> solution;                          // suspectId -> pos (full truth)
}
// toJson/fromJson for CaseData and every nested type (hand-written).
```

- [ ] **Step 1: Failing tests** — JSON round-trip: build a hand-written `CaseData` fixture
  covering every `Clue` subtype (negated and not); `CaseData.fromJson(c.toJson()) == c`
  (implement `==` on all model classes). Also assert `Difficulty.easy.gridSize == 5` etc.
- [ ] **Step 2:** run, confirm compile failure (file missing).
- [ ] **Step 3: Implement** `models.dart` per Interfaces. Records have no `==` issues;
  implement `==`/`hashCode` on classes by value.
- [ ] **Step 4:** `flutter test test/domain/models_test.dart` → pass.
- [ ] **Step 5: Commit** `feat(domain): case models with json round-trip`

---

### Task 2: Clue evaluation

**Files:**
- Create: `lib/domain/clue_eval.dart`
- Test: `test/domain/clue_eval_test.dart`

**Interfaces:**
- Consumes: `Clue`, `CaseData` fields.
- Produces:

```dart
/// Evaluates a clue against a candidate placement. [placement] maps suspectId -> Pos
/// for ALL suspects. [targetPos] resolves "V" and suspect ids. Throws ArgumentError if
/// the clue references an unknown id or has suspectId == targetId.
bool evaluateClue(
  Clue clue, {
  required Map<String, Pos> placement,
  required Pos victimPos,
  required List<RoomDef> rooms,
  required List<ObjectDef> objects,
});
```

- [ ] **Step 1: Failing tests** — for each of the 6 clue types write a true case and a false
  case on a fixed 5×5 fixture (hand-coded rooms/objects/placement), plus: negation inverts;
  `Direction.north` is strict (`row <`, not `<=`); `Beside` is Manhattan == 1 (diagonal is
  NOT beside); `"V"` resolves to `victimPos`; `suspectId == targetId` throws.
- [ ] **Step 2:** run → fail (undefined).
- [ ] **Step 3: Implement** — pure functions, no Flutter imports. Helper:
  `Pos posOf(String id)` resolving `"V"` vs suspects.
- [ ] **Step 4:** pass. **Step 5: Commit** `feat(domain): clue evaluation semantics`

---

### Task 3: Uniqueness solver

**Files:**
- Create: `lib/domain/solver.dart`
- Test: `test/domain/solver_test.dart`

**Interfaces:**
- Consumes: `Difficulty`, `RoomDef`, `Clue`, `evaluateClue`.
- Produces:

```dart
/// Counts complete placements satisfying: one guest per row/col/room + all clues.
/// Stops early once count > cap (default 2). Guests are CaseData.suspects in order.
int countSolutions({
  required int gridSize,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> suspectIds, // ordered; placement keyed by these
  required Pos victimPos,
  required List<ObjectDef> objects,
  int cap = 2,
});

/// Returns the single solution, or null when count != 1.
Map<String, Pos>? firstSolution({/* same params */});
```

- [ ] **Step 1: Failing tests** — on a 5×5 with a known unique clue set, `countSolutions == 1`
  and `firstSolution` returns it; with clues reduced to a subset, count > 1 (== 2 with cap 2);
  with no clues on 5×5, count == 2 (capped) proving cap works. Reuse Task 2's fixture.
- [ ] **Step 2:** fail. **Step 3: Implement** — backtracking over rows; state per row: try
  every column not used, skip cells whose room already used; at each complete assignment
  evaluate all clues once (clues only reference full placement). Prune nothing clever —
  G ≤ 7 means ≤ 7! = 5040 permutations worst case; that is fast enough by orders of magnitude.
- [ ] **Step 4:** pass. **Step 5: Commit** `feat(domain): exhaustive uniqueness solver`

---

### Task 4: Room partition generator

**Files:**
- Create: `lib/domain/generator/rooms.dart`
- Test: `test/domain/generator/rooms_test.dart`

**Interfaces:**
- Produces:

```dart
/// Grows G contiguous rooms from random seed cells using frontier expansion,
/// balanced by preferring the currently-smallest room's frontier. All randomness
/// from [rng] (seeded by caller).
List<RoomDef> generateRooms({required int gridSize, required Random rng});
```

(`RoomDef.cells` filled; names assigned later by case factory.)

- [ ] **Step 1: Failing tests** — for 100 seeds at G ∈ {5,6,7}: rooms.length == G; every cell
  in exactly one room (coverage, no overlap); each room orthogonally contiguous (BFS from
  first cell visits all its cells); max room size ≤ 2×min room size (soft balance — assert
  max ≤ min + 3); no room of size 0.
- [ ] **Step 2:** fail. **Step 3: Implement** — multi-source random growth; when a room's
  frontier is exhausted and cells remain unassigned, merge them into a random adjacent room.
- [ ] **Step 4:** pass. **Step 5: Commit** `feat(domain): seeded room generator`

---

### Task 5: Case factory (the generator pipeline)

**Files:**
- Create: `lib/domain/generator/case_factory.dart`
- Test: `test/domain/generator/case_factory_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:

```dart
CaseData generateCase({required Difficulty difficulty, required int seed});
// deterministic: same args -> identical CaseData (json-stable). Throws StateError only
// if the retry budget (§2.3) is exhausted.
```

- [ ] **Step 1: Failing property test** (the most important test in the app):

```dart
for (final d in Difficulty.values) {
  for (var seed = 1; seed <= 50; seed++) {
    final c = generateCase(difficulty: d, seed: seed);
    // 1. structure: G rooms; suspects.length == G; objects per §2.3; victim cell empty in solution.
    // 2. solution validity: one guest per row / per column / per room (assert as sets).
    // 3. all clues true: evaluateClue(...) is true for c.solution for every clue.
    // 4. uniqueness: countSolutions(...) == 1 and firstSolution == c.solution.
    // 5. murderer: the suspect in the same room as c.victimPos has id == c.murdererId.
    // 6. clue window: d.minClues <= c.clues.length <= d.maxClues.
    // 7. determinism: generateCase(d, seed).toJson() == second run's toJson().
  }
}
```

- [ ] **Step 2:** fail (function missing).
- [ ] **Step 3: Implement** the pipeline in this order:

1. `rng = Random(seed)`; rooms via Task 4; names from fixed pools
   (`_suspectNames`, `_roomNames` — 16+ each, curated, plain strings).
2. **Placement search:** backtracking over rows choosing an unused column whose room is
   unused, random order via `rng` — first found assignment is the solution.
3. Victim: pick a random room, then a random *empty* cell in it; murderer := that room's
   guest. (Empty = not in `solution.values`.)
4. Objects: `objectCount` distinct random empty cells, kinds shuffled from `ObjectKind`.
5. **Clue pool:** for each §2.2 type, enumerate candidate instances over
   suspects × (rooms | suspects+V | objects | directions), keep those TRUE for the solution
   (and valid per taxonomy constraints), cap each type at 10 sampled with `rng`.
6. **Minimize to unique:** shuffle pool; greedily add clues until
   `countSolutions(...) == 1`; then one pruning pass — try removing each clue, keep the
   removal if still unique (prefer removing earlier-added clues). If final count is outside
   the §2.3 window: below min → keep adding unused pool clues (uniqueness-safe) until min;
   above max → retry seed. Whole generation wrapped in the §2.3 retry budget.
7. Attach clues to their `suspectId` (cards render under the portrait — UI concern, storage
   is flat).

- [ ] **Step 4:** pass. If rare seeds fail the property test, do NOT relax assertions —
  raise the retry budget or fix the generator; report persistent failures.
- [ ] **Step 5: Commit** `feat(domain): full case generator with uniqueness guarantee`

---

### Task 6: Storage layer

**Files:**
- Create: `lib/storage/prefs_repository.dart`
- Test: `test/storage/prefs_repository_test.dart`

**Interfaces:**
- Consumes: `CaseData` JSON (Task 1).
- Produces:

```dart
class Settings { final ThemeMode themeMode; final bool haptics; }  // + json
class DailyState { final String lastCompletedDate; final int streak; } // yyyy-mm-dd UTC
class Stats { final Map<Difficulty, int> solved; final Map<Difficulty, Duration> bestTime;
              final Map<Difficulty, Duration> totalTime; final int totalCases; } // + json
class SavedGame { final CaseData caseData; final bool isDaily; final String dailyDate;
                  final BoardSnapshot board; }
class BoardSnapshot { final Map<String, Pos> placed; final Set<Pos> xMarks;
                      final Duration elapsed; final int hintsUsed;
                      final int wrongAccusations; } // + json

class PrefsRepository {
  PrefsRepository(this._prefs);
  Settings loadSettings();            Future<void> saveSettings(Settings s);
  SavedGame? loadActiveGame();        Future<void> saveActiveGame(SavedGame g);
  Future<void> clearActiveGame();
  Stats loadStats();                  Future<void> saveStats(Stats s);
  DailyState loadDailyState();        Future<void> saveDailyState(DailyState d);
}
```

(`BoardSnapshot` lives in `models.dart`; add it there in this task.)

- [ ] **Step 1: Failing tests** — with `SharedPreferences.setMockInitialValues({})`:
  defaults are null/empty; save→load round-trips Settings, Stats, DailyState, SavedGame
  (including a full CaseData with every clue type); **corruption cases:** stored JSON
  `"{not json"`, `{}`, `{"v": 99, ...}` (unknown version) all make `loadActiveGame()`
  return null (never throw); version key `v: 1` written on save.
- [ ] **Step 2:** fail. **Step 3: Implement** — single keys per object, `try/catch` +
  `debugPrint` on parse failure, return null/fallbacks.
- [ ] **Step 4:** pass. **Step 5: Commit** `feat(storage): prefs repository with fail-soft loads`

---

### Task 7: App shell, theme, routing, error handling

**Files:**
- Create: `lib/app.dart`, `lib/core/theme.dart`, `lib/core/routes.dart`
- Modify: `lib/main.dart`, `l10n/app_en.arb`
- Test: `test/app_shell_test.dart`

**Interfaces:**
- Consumes: Task 6 `PrefsRepository` (via provider `sharedPreferencesProvider`,
  `prefsRepositoryProvider`).
- Produces: `murdokuApp`-style `Widget app(BuildContext)` root; providers:
  `settingsControllerProvider` (Notifier<Settings> persisting on change);
  routes `/` (HomeScreen placeholder), `/game`, `/how-to-play`, `/stats`, `/settings`
  (placeholder `Scaffold`s saying the route name via l10n). `AppTheme.light/dark` with a
  noir-mystery palette (deep indigo/charcoal + amber accent); room palette
  `List<Color> roomColors(int g)` (muted, distinct, AA-contrast in both modes).
  `main.dart`: `runZonedGuarded`, `ErrorWidget.builder` → friendly l10n message +
  `FlutterError.onError` logging.

- [ ] **Step 1: Failing widget test** — pump app; home renders app title; dark mode toggle
  via settings controller changes `ThemeData.brightness`; navigating to `/stats` renders its
  placeholder; every placeholder string comes from `AppLocalizations`.
- [ ] **Step 2:** fail. **Step 3: Implement** (Riverpod `ProviderScope` in `main`; GoRouter
  with `redirect` none). **Step 4:** pass; full gate.
- [ ] **Step 5: Commit** `feat(app): shell, theme, routing, error guard`

---

### Task 8: Game controller

**Files:**
- Create: `lib/domain/game_logic.dart`, `lib/state/game_controller.dart`
- Test: `test/domain/game_logic_test.dart`, `test/state/game_controller_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces (`game_logic.dart`, pure):

```dart
enum Tool { place, markX, erase }
bool canPlace(CaseData c, Map<String,Pos> placed, String suspectId, Pos pos); // free cell, not victim cell
int correctCount(CaseData c, Map<String,Pos> placed); // guests at their solution pos
bool boardSolved(CaseData c, Map<String,Pos> placed); // all G placed && each at solution pos
```

Also add to `lib/domain/models.dart` in this task:

```dart
/// UTC-date → deterministic daily seed, per §2.5.
int dailySeedFor(DateTime utcDate) => utcDate.year * 10000 + utcDate.month * 100 + utcDate.day;
```

Produces (`game_controller.dart`):

```dart
enum GamePhase { playing, won, revealed }
class GameState {
  final CaseData caseData; final GamePhase phase;
  final Map<String, Pos> placed; final Set<Pos> xMarks;
  final String? selectedSuspectId; final Tool tool;
  final Duration elapsed; final int hintsUsed; final int wrongAccusations;
  final bool isDaily; final String? dailyDate; final Set<String> eliminatedSuspects;
}
class GameNotifier extends Notifier<GameState> {
  void startNewCase(Difficulty d);            // random seed
  void startDaily(String utcDate);            // seed = dailySeedFor
  void resume(SavedGame g);
  void selectSuspect(String? id); void setTool(Tool t);
  void tapCell(Pos p);       // dispatch by tool: place/remove/toggle X — see tests
  void undo();               // full move history incl. X toggles
  ({int correct, int total}) runCheck(); // correct guest count via game_logic
  void hintPlacement();      // Hint A (needs hintsUsed < 2)
  void hintEliminate();      // Hint B: eliminates one innocent suspect
  AccuseResult accuse(String suspectId); // correct -> phase won + stats/daily updates
  void revealSolution();     // phase revealed
  void quit();               // clear save
  void tick();               // +1s while visible
}
// Persist after every mutating call (debounce not needed at this scale).
```

- [ ] **Step 1: Failing `game_logic` tests** — `canPlace` false on occupied/victim cells;
  `correctCount` counts only exact matches; `boardSolved` strictness.
- [ ] **Step 2: Failing controller tests** (`ProviderContainer` + mock prefs; fixed-seed
  `generateCase`): full happy path (place all per solution → `boardSolved`, `accuse(murderer)`
  → `won`, save cleared); wrong `accuse` increments `wrongAccusations`, stays `playing`,
  message flag set; `tapCell` with `tool.place`: places selected suspect on free cell; tapping
  the suspect's own cell removes it (toggle); **tapping a cell occupied by another suspect is
  a no-op**; input ignored when phase != playing; `undo` reverses place/remove/X-toggle;
  `resume(SavedGame)` restores board+elapsed; `hintPlacement` locks a correct placement;
  `hintEliminate` never eliminates the murderer; daily identity: `startDaily("2026-11-19")`
  twice → identical case json (uses `dailySeedFor`).
- [ ] **Step 3:** Implement to green.
- [ ] **Step 4:** Full gate. **Step 5: Commit** `feat(state): game controller with full rules`

---

### Task 9: Home screen

**Files:**
- Create: `lib/ui/screens/home_screen.dart`
- Modify: `l10n/app_en.arb`
- Test: `test/ui/screens/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 7 routes, Task 8 controller (`ref.watch` active-save existence,
  daily done-ness from Task 6 `DailyState`), Task 6 stats for totals line.
- Produces: `HomeScreen` with Continue (only when a `SavedGame` exists; shows difficulty +
  elapsed), New case (bottom sheet: three difficulty tiles → confirm-discard dialog if a
  save is active → `startNewCase` → `go('/game')`), Daily card (checkmark when today's UTC
  date == `lastCompletedDate`; disabled-state styling after completion), navigation rows to
  how-to/stats/settings.

- [ ] **Step 1: Failing widget tests** — with mock prefs: no save → no Continue button;
  with save → Continue visible with right label; New case with active save shows discard
  confirmation; daily done state renders completed marker. All strings from l10n.
- [ ] **Step 2–4:** fail → implement → pass. Use seeded controller overrides
  (`ProviderScope(overrides: [...])`) with a fixed-seed case — never rely on random content
  in widget tests.
- [ ] **Step 5: Commit** `feat(ui): home screen`

---

### Task 10: Board view

**Files:**
- Create: `lib/ui/widgets/board_view.dart`, `lib/ui/widgets/avatar.dart`
- Modify: `l10n/app_en.arb`
- Test: `test/ui/widgets/board_view_test.dart`

**Interfaces:**
- Consumes: `GameState` (Task 8), `AppTheme.roomColors`, `CaseData`.
- Produces: `BoardView` widget (root keyed `Key('board_view')`) — square `AspectRatio(1)`
  grid via `LayoutBuilder` +
  `GridView`-free custom `Stack`/`Table` (any approach; must scale to smallest dimension).
  Renders: room tint + room borders (thicker between rooms), victim cell (`V` badge +
  distinct color), objects (icon + semantic label "clock", from l10n per `ObjectKind`),
  placed suspects (avatar = colored circle + `Icons.person`, size ≥ 48 dp target), X marks,
  selected-suspect highlight, rows/cols containing a placed suspect lightly shaded
  ("blocked" affordance). Input: `onCellTap(Pos)`, drag callbacks for X/erase tools
  (`onCellDrag(Pos)`), all with `Semantics` labels ("row 3, column 5, Library room, empty").

- [ ] **Step 1: Failing widget tests** — fixed 5×5 case: taps invoke `onCellTap` with right
  `Pos`; avatar renders for placed suspect; X mark renders; victim cell is distinct;
  **text-scale stress:** pump at `textScaleFactor: 2.0` in a 320×569 surface —
  `tester.getRect(findBoard()).size` within screen bounds (Review Focus #5).
- [ ] **Step 2–4:** fail → implement → pass. **Step 5: Commit** `feat(ui): board view with accessibility`

---

### Task 11: Suspect panel

**Files:**
- Create: `lib/ui/widgets/suspect_panel.dart`
- Modify: `l10n/app_en.arb`
- Test: `test/ui/widgets/suspect_panel_test.dart`

**Interfaces:**
- Consumes: `GameState`, `CaseData.clues`, l10n.
- Produces: `SuspectPanel` — horizontally scrollable row (phones) / column (tablets via
  `LayoutBuilder`) of suspect cards: avatar, name, clue cards rendered as sentences via a
  `String describeClue(Clue, CaseData, AppLocalizations)` pure function in this file;
  selected state; placed state (check). Clue wording MUST follow §2.2 table (positive and
  negated forms) — write all template strings in the arb.

- [ ] **Step 1: Failing widget tests** — fixed case: every suspect card shows name and ≥1
  non-empty clue sentence (fixture guarantees clues per suspect); tapping selects
  (`onSuspectTap`); negated clue renders the negated sentence (assert exact arb output for
  one known clue).
- [ ] **Step 2–4:** fail → implement → pass.
- [ ] **Step 5: Commit** `feat(ui): suspect panel with clue cards`

---

### Task 12: Game screen assembly

**Files:**
- Create: `lib/ui/screens/game_screen.dart`
- Modify: `l10n/app_en.arb`
- Test: `test/ui/screens/game_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 8/10/11, `WidgetsBindingObserver`.
- Produces: `GameScreen` — top bar (back-to-home with confirm, timer via controller `tick`
  driven by a `Timer` paused by `AppLifecycleState`), board + suspect panel (portrait:
  vertical split; landscape/tablet: side-by-side), bottom toolbar: tool buttons (place /
  X / erase), undo, check, hint, accuse. Check result via `SnackBar`
  ("{n} of {g} guests are correctly placed"). Board-solved → auto-open accuse prompt.
  Pause menu: resume / how to play / reveal solution (confirm; forfeits) / quit (confirm).

- [ ] **Step 1: Failing widget test** — full flow on fixed-seed easy case: select suspect →
  tap its solution cell for every suspect (read solution via a
  `@visibleForTesting` getter on the controller state — it already stores `caseData`);
  assert `boardSolved`; assert accuse prompt appears; tapping the murderer wins and shows
  the victory dialog; tapping an innocent shows the alibi SnackBar and mistake count bumps.
  Also: app lifecycle hidden→visible does not double-tick (fake async).
- [ ] **Step 2–4:** fail → implement → pass (use `tester.pumpAndSettle` carefully; drive
  controller directly where widget plumbing is out of scope).
- [ ] **Step 5: Commit** `feat(ui): game screen with full loop`

---

### Task 13: Victory, accusation, stats update

**Files:**
- Create: `lib/ui/widgets/accuse_sheet.dart`, `lib/ui/widgets/dialogs.dart`
- Modify: `lib/state/stats_controller.dart` (create here), `l10n/app_en.arb`
- Test: `test/ui/widgets/accuse_sheet_test.dart`, `test/state/stats_controller_test.dart`

**Interfaces:**
- Consumes: Task 8 `accuse`, Task 6 stats/daily persistence.
- Produces: `AccuseSheet` (modal bottom sheet: suspect grid; `eliminatedSuspects` shown
  crossed-out and disabled); `VictoryDialog` (time formatted `mm:ss`, difficulty, mistakes,
  "Case closed" copy); `stats_controller.dart`:
  `StatsNotifier` with `recordWin({difficulty, time, mistakes, isDaily, dailyDate})` —
  updates solved/best/total/avg, daily streak: `+1` if `lastCompletedDate` == yesterday
  (UTC) else reset to `1`; same-day re-win does not double the streak.

- [ ] **Step 1: Failing tests** — stats math (first win, new best, avg, streak continue /
  break / same-day idempotent); accuse sheet disables eliminated suspects; victory dialog
  shows formatted time.
- [ ] **Step 2–4:** fail → implement → pass. **Step 5: Commit** `feat(ui): accusation, victory, stats`

---

### Task 14: Stats & settings screens

**Files:**
- Create: `lib/ui/screens/stats_screen.dart`, `lib/ui/screens/settings_screen.dart`
- Modify: `l10n/app_en.arb`
- Test: `test/ui/screens/stats_screen_test.dart`, `test/ui/screens/settings_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 6/7/13.
- Produces: `StatsScreen` (per-difficulty rows: solved, best, average; current streak;
  total cases; empty-state copy), `SettingsScreen` (theme segmented control, haptics
  switch, "Reset all progress" with confirm dialog → clears prefs keys, pops, snackbar).

- [ ] **Step 1: Failing tests** — stats render from seeded mock prefs; empty state copy;
  theme change persists (reload container → new value); reset clears settings? no — clears
  saves/stats/daily but KEEPS settings.
- [ ] **Step 2–4:** fail → implement → pass. **Step 5: Commit** `feat(ui): stats and settings screens`

---

### Task 15: Daily case & streak wiring

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`, `lib/state/game_controller.dart`
- Test: `test/state/daily_test.dart`

**Interfaces:**
- Consumes: Task 8 `startDaily`, Task 6 `DailyState`, Task 13 `recordWin`.
- Produces: home daily card → `startDaily(todayUtc())` → `/game`; win during daily calls
  `recordWin(isDaily: true, dailyDate: startedDate)`. **Identity rule:** the daily's date is
  captured when the case starts; playing across midnight keeps yesterday's case and marks
  THAT date complete (Review Focus #4). `todayUtc()` injectable for tests
  (`DateTime Function() clock = ...` provider override).

- [ ] **Step 1: Failing tests** — same date → same seed/case; clock crossing midnight
  mid-game: state still references start date; completion updates streak for the start
  date; daily card "done" only when `lastCompletedDate == todayUtc()`.
- [ ] **Step 2–4:** fail → implement → pass. **Step 5: Commit** `feat(state): daily case and streaks`

---

### Task 16: Tutorial & how-to-play

**Files:**
- Create: `lib/ui/screens/how_to_play_screen.dart`, `lib/ui/widgets/tutorial_overlay.dart`
- Modify: `l10n/app_en.arb`, home screen (first-launch flag in prefs `tutorialSeen`)
- Test: `test/ui/widgets/tutorial_overlay_test.dart`

**Interfaces:**
- Produces: `TutorialOverlay` — 3 steps (rules §2.4 verbatim + one illustrated hint about
  X marks), shown over home on first launch, dismiss stores flag; `HowToPlayScreen` —
  static rules + clue glossary (beside / north-south-east-west / same row).

- [ ] **Step 1: Failing tests** — first launch (mock prefs empty) shows overlay; after
  dismiss, not shown; how-to screen contains all four rule strings from l10n.
- [ ] **Step 2–4:** fail → implement → pass. **Step 5: Commit** `feat(ui): tutorial and rules screens`

---

### Task 17: Integration smoke test, icon, release build

**Files:**
- Create: `integration_test/smoke_test.dart`, `tool/gen_icon.dart`, `flutter_launcher_icons.yaml`
- Modify: `pubspec.yaml` (dev deps `image`, `flutter_launcher_icons`; name/version fields)
- Test: `integration_test/smoke_test.dart`

**Interfaces:**
- Consumes: everything.
- Produces: passing integration test; generated icons; release builds.

- [ ] **Step 1: Integration test** — real app, `ProviderScope` override forcing
  `startNewCase` seed to a fixed value (add an override hook in main for tests:
  `murdokuBootstrap({int? forcedSeed})`); drive: home → new easy case → place all guests
  via controller-visible solution → accuse murderer → victory dialog → back home → daily
  card state updated. Run: `flutter test integration_test/smoke_test.dart -d macos` (or an
  android emulator if attached).
- [ ] **Step 2: Icon generation** — `tool/gen_icon.dart` uses `package:image` to draw a
  1024×1024 PNG: dark indigo rounded-square background, amber 3×3 mini-grid, one amber
  suspect dot, one red `V` dot. `flutter_launcher_icons.yaml` consumes it
  (`flutter pub run flutter_launcher_icons`). Add `image` and `flutter_launcher_icons` as
  dev dependencies — the only allowed additions.
- [ ] **Step 3: Release prep** — `pubspec.yaml`: `name: murdoku`, `version: 1.0.0+1`;
  Android `applicationId`/label "Murdoku"; iOS `CFBundleDisplayName` "Murdoku". Add
  `README.md` (build/run/test instructions + TOOLCHAIN.md reference). **Add a top-of-file
  warning in README: "Murdoku" is a working title; rename before store submission
  (trademark).** Build: `flutter build apk --release` and
  `flutter build ipa --no-codesign`; both must succeed.
- [ ] **Step 4: Final QA checklist (manual, in simulator/emulator):** dark mode contrast;
  rotate phone; text scale max; offline (airplane mode) full flow; kill & resume mid-case;
  reset progress; back button behaviors. Record results in the final commit message.
- [ ] **Step 5: Full gate + Commit** `feat(release): integration test, icons, release builds`

---

## 6. Post-v1 backlog (explicitly out of scope now)

Sound & haptics beyond default, animations, blocked furniture cells, 8×8 expert mode,
hand-authored story campaigns, cloud sync, tablets-specific layouts, extra locales
(scaffold is ready), hint system expansions, share-results image.

---

*Plan written 2026-11-19. Self-review done: spec coverage ✓ (every §2.5 flow maps to a
task), interface names cross-checked between producer/consumer tasks, Review Focus items
each pinned to a test, proportion checked (algorithms given only where signature+tests do
not determine them).*
