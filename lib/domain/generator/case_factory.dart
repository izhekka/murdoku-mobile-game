import 'dart:math';

import 'package:murdoku/domain/deducer.dart';
import 'package:murdoku/domain/generator/rooms.dart';
import 'package:murdoku/domain/models.dart';

/// Curated name pools (content data, not UI strings).
const _suspectNames = [
  'Ash',
  'Blair',
  'Casey',
  'Drew',
  'Ellis',
  'Frank',
  'Gale',
  'Harper',
  'Iris',
  'Jack',
  'Kai',
  'Lane',
  'Morgan',
  'Noel',
  'Oakley',
  'Piper',
];

const _roomNames = [
  'Hall',
  'Library',
  'Kitchen',
  'Cellar',
  'Study',
  'Ballroom',
  'Conservatory',
  'Parlor',
  'Attic',
  'Pantry',
  'Gallery',
  'Chapel',
  'Solarium',
  'Den',
  'Foyer',
  'Observatory',
];

/// Budget of derived attempts per widening window in [generateCase].
const _retryBudget = 40;

/// Tag of the generator pipeline whose output lives in persisted pools
/// (issue 108). The case-pool envelope stores it alongside the cases; on
/// load a mismatching tag degrades the whole pool to empty, so a changed
/// pipeline (e.g. ADR 0007 gating) never serves stale-quality cases.
/// BUMP PROTOCOL: bump by 1 whenever generation semantics change in a way
/// that makes previously generated cases differ from fresh output (clue
/// rules, gating, board shape) — the stored pools are then discarded on
/// next load and silently regenerated.
const casePoolGeneratorTag = 2;

/// The per-case cap on `DirectionClue` cards of any polarity (issue 111).
/// Only the positive side can approach it — negated directions are not
/// emitted at all — so no downstream cap check is needed.
const _maxDirectionCards = 2;

/// Recovery windows for [generateCaseWithRecovery]: how many extra 40-seed
/// strides the drawn-seed start path may consume past the exhausted one.
const _recoveredWindows = 8;

/// Keeps derived attempt seeds in [0, 0x7FFFFFFF] — positive, JSON-safe,
/// and in the same positive, 64-bit-safe class as the runtime-drawn seeds
/// (`Random().nextInt(1 << 30)` in game_controller.dart).
const _seedMask = 0x7FFFFFFF;

/// The rng seed for attempt [attempt] after a requested [requested] seed:
/// a splitmix64 stream step (advance by the golden-ratio constant per
/// attempt) followed by the splitmix64 finalizer, masked to 31 bits.
///
/// Deriving per attempt is issue 61, landing §13's "hash the seed per
/// attempt" option: under the old sequential `requested + attempt` mapping
/// the first successful attempt collapsed every requested seed inside one
/// failure basin onto the same stored seed (easy 1–4 → 5, standard 28–43
/// → 44, hard 26–44 → 45). Derived attempts spread nearby requested seeds
/// over decorrelated rng streams, so adjacent requested seeds return
/// distinct cases.
int _derivedSeed(int requested, int attempt) {
  var x = (requested & 0x7FFFFFFFFFFFFFFF) + attempt * 0x9E3779B97F4A7C15;
  x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
  x = (x ^ (x >>> 27)) * 0x94D049BB133111EB;
  return (x ^ (x >>> 31)) & _seedMask;
}

/// Public aliases for tests: the localized pools in localized_names.dart are
/// index-aligned with these.
const suspectNamePool = _suspectNames;
const roomNamePool = _roomNames;

/// Deterministic: same [difficulty] and [seed] produce an identical case.
/// Tries the [seed]-derived attempt seeds of one 40-attempt window; if none
/// yields a chain-solvable puzzle (issue #106) inside the difficulty's clue
/// window, widens the window's max by +1 and retries the whole budget (up
/// to 4 widenings), then throws [StateError].
///
/// Each attempt derives its rng seed from (requested seed, attempt index)
/// via [_derivedSeed] (issue 61): nearby requested seeds spread their
/// attempts over decorrelated seeds instead of walking the same contiguous
/// window — the sequential mapping used before collapsed whole failure
/// basins onto one stored seed, so adjacent seeds returned the identical
/// case (§13: easy 1–4 → 5, standard 28–43 → 44, hard 26–44 → 45). The
/// derived mapping, the re-measured convergence table and the regenerated
/// golden digests landed together (issue 61) and are pinned by
/// test/domain/generator/seed_convergence_test.dart and
/// golden_digest_test.dart.
CaseData generateCase({required Difficulty difficulty, required int seed}) {
  for (var widen = 0; widen <= 3; widen++) {
    for (var i = 0; i < _retryBudget; i++) {
      final attempt = _attempt(difficulty, _derivedSeed(seed, i), widen);
      if (attempt != null) return attempt;
    }
  }
  throw StateError(
    'no deduction-chain case found for $difficulty within budget '
    '(seed $seed)',
  );
}

/// Recovery for the runtime-drawn seed path (issue 45): a requested seed
/// whose whole widened budget fails inside [generateCase] would hand the
/// interactive start path a crash. This re-enters the search on the next
/// 40-seed stride. Under per-attempt derivation (issue 61) each window
/// passes a different requested base, so every recovery window derives 40
/// fresh attempt seeds unlike any previous window's (the sequential
/// mapping re-walked tried seeds instead); a rare exhaust therefore
/// retries genuinely new ground. Deterministic in [seed] (forced-seed
/// tests stay reproducible), and [dailySeedFor] derivation is untouched.
///
/// Give-up safety: the loop spans `recoveryWindows + 1` windows, each
/// deriving 40 fresh attempts — the shipped default covers 360 derived
/// attempts per requested seed, and rethrows only when every window
/// exhausts at every widen level. [recoveryWindows] is a test seam
/// (0 pins the give-up rethrow) and behaves as 0 below zero. On give-up
/// the FIRST exhausted window's error is rethrown — its message carries
/// the requested seed.
CaseData generateCaseWithRecovery({
  required Difficulty difficulty,
  required int seed,
  int recoveryWindows = _recoveredWindows,
}) {
  StateError? exhausted;
  for (var window = 0; window <= max(0, recoveryWindows); window++) {
    final attemptSeed = seed + window * _retryBudget;
    try {
      return generateCase(difficulty: difficulty, seed: attemptSeed);
    } on StateError catch (e) {
      exhausted ??= e; // keep the first error: the requested-seed message
    }
  }
  throw exhausted!; // window 0 always ran, so a failure was captured
}

/// Everything the clue pipeline needs about one generated layout.
class _Prepared {
  const _Prepared({
    required this.rooms,
    required this.suspects,
    required this.solution,
    required this.victimPos,
    required this.murdererId,
    required this.objects,
  });

  final List<RoomDef> rooms;
  final List<Suspect> suspects;
  final Map<String, Pos> solution;
  final Pos victimPos;
  final String murdererId;
  final List<ObjectDef> objects;
}

CaseData? _attempt(Difficulty difficulty, int seed, int widen) {
  // One rng stream per attempt: _prepare consumes it for the layout, the
  // clue pipeline continues on the same stream — exactly like the original
  // inline flow (pinned by the golden-digest test).
  final rng = Random(seed);
  final prep = _prepare(difficulty, widen, rng);
  if (prep == null) return null;
  final clues = _buildClueSet(difficulty, prep, widen, rng);
  if (clues == null) return null;

  return CaseData(
    seed: seed,
    difficulty: difficulty,
    rooms: prep.rooms,
    objects: prep.objects,
    suspects: prep.suspects,
    victimPos: prep.victimPos,
    murdererId: prep.murdererId,
    clues: clues,
    solution: prep.solution,
  );
}

/// Attempts 1-4 of the original inline flow: layout, names, random placement,
/// victim and furniture. The rng call order is part of the deterministic
/// contract — every shuffle below happens exactly where it did before
/// (issue 35 decomposition; pinned by the golden-digest test).
_Prepared? _prepare(Difficulty difficulty, int widen, Random rng) {
  final g = difficulty.gridSize;

  // 1. rooms with themed names; suspects with themed names.
  final (rooms, suspects) = _namedCast(g, rng);

  // 2. random placement search: first valid assignment is the solution.
  final solution = _randomPlacement(g, rooms, rng);
  if (solution == null) return null;

  // 3. victim: random room, random empty cell in it; murderer = that room's guest.
  final victim = _pickVictim(rooms, solution, rng);
  if (victim == null) return null;
  final (victimPos, victimRoom) = victim;
  final murdererId = suspects
      .firstWhere((s) => victimRoom.contains(solution[s.id]!))
      .id;

  // 4. furniture. Occupiable items may sit on empty cells or under solution
  // guests (a guest on a chair); blocking items only on empty cells — the
  // solution itself never uses one, so the chain gate is unaffected.
  // Never on the victim cell, at most one item per cell.
  final objects = _buildObjects(difficulty, rooms, solution, victimPos, rng);
  if (objects == null) return null;

  return _Prepared(
    rooms: rooms,
    suspects: suspects,
    solution: solution,
    victimPos: victimPos,
    murdererId: murdererId,
    objects: objects,
  );
}

/// Rooms and suspects with themed names. Index lists are shuffled (not name
/// copies) so each entry keeps the pool slot its name came from — poolIndex
/// must index the localized pools (UX-1). Same list lengths as before, so
/// the rng stream and the drawn names are unchanged.
(List<RoomDef>, List<Suspect>) _namedCast(int g, Random rng) {
  final rawRooms = generateRooms(gridSize: g, rng: rng);
  final roomSlots = List.generate(_roomNames.length, (i) => i)..shuffle(rng);
  final suspectSlots = List.generate(_suspectNames.length, (i) => i)
    ..shuffle(rng);
  final rooms = [
    for (var i = 0; i < g; i++)
      RoomDef(
        id: rawRooms[i].id,
        name: _roomNames[roomSlots[i]],
        cells: rawRooms[i].cells,
        poolIndex: roomSlots[i],
      ),
  ];
  final suspects = [
    for (var i = 0; i < g; i++)
      Suspect(
        id: 's$i',
        name: _suspectNames[suspectSlots[i]],
        poolIndex: suspectSlots[i],
      ),
  ];
  return (rooms, suspects);
}

/// Shuffles the room order and picks the first room with a free cell; the
/// victim sits in that room's first free cell (rng order preserved).
(Pos, RoomDef)? _pickVictim(
  List<RoomDef> rooms,
  Map<String, Pos> solution,
  Random rng,
) {
  final roomOrder = [...rooms]..shuffle(rng);
  for (final room in roomOrder) {
    final empty = room.cells.where((c) => !solution.values.contains(c)).toList()
      ..shuffle(rng);
    if (empty.isEmpty) continue;
    return (empty.first, room);
  }
  return null;
}

/// Places the difficulty's furniture over the free cells. Returns null when
/// the layout cannot host the full blocking count (the caller drops the
/// attempt).
List<ObjectDef>? _buildObjects(
  Difficulty difficulty,
  List<RoomDef> rooms,
  Map<String, Pos> solution,
  Pos victimPos,
  Random rng,
) {
  final occupied = solution.values.toSet();
  final allCells = [
    for (final room in rooms)
      for (final cell in room.cells) cell,
  ]..shuffle(rng);
  final used = <Pos>{victimPos};
  final occupiableKinds = occupiableKindsList..shuffle(rng);
  final blockingKinds =
      ObjectKind.values
          .where(
            (k) => !kindOccupiable(k) && spriteBackedBlockingKinds.contains(k),
          )
          .toList()
        ..shuffle(rng);
  final objects = <ObjectDef>[];
  _placeOccupiable(
    objects,
    allCells,
    used,
    occupiableKinds,
    difficulty.occupiableCount,
  );
  _placeBlocking(
    objects,
    allCells,
    used,
    occupied,
    blockingKinds,
    difficulty.objectCount,
  );
  if (objects.length < difficulty.objectCount) return null;
  return objects;
}

/// Occupiable items first: on empty cells or under solution guests.
void _placeOccupiable(
  List<ObjectDef> objects,
  List<Pos> allCells,
  Set<Pos> used,
  List<ObjectKind> kinds,
  int count,
) {
  for (final cell in allCells) {
    if (objects.length >= count) break;
    if (used.contains(cell)) continue;
    used.add(cell); // occupiable cells are taken even when under a guest
    objects.add(
      ObjectDef(
        id: 'o${objects.length}',
        kind: kinds[objects.length % kinds.length],
        pos: cell,
        occupiable: true,
      ),
    );
  }
}

/// Blocking items next: only on cells no guest occupies.
void _placeBlocking(
  List<ObjectDef> objects,
  List<Pos> allCells,
  Set<Pos> used,
  Set<Pos> occupied,
  List<ObjectKind> kinds,
  int count,
) {
  for (final cell in allCells) {
    if (objects.length >= count) break;
    if (used.contains(cell) || occupied.contains(cell)) continue;
    used.add(cell);
    objects.add(
      ObjectDef(
        id: 'o${objects.length}',
        kind: kinds[objects.length % kinds.length],
        pos: cell,
      ),
    );
  }
}

/// Attempts 5-6 of the original inline flow: clue pool, minimize to a
/// deduction chain, prune, per-suspect coverage, clue-window fill and the
/// negated top-up. Returns null when the attempt cannot meet the
/// difficulty's clue window under its tier's chain gate (issue #106).
List<Clue>? _buildClueSet(
  Difficulty difficulty,
  _Prepared prep,
  int widen,
  Random rng,
) {
  final g = difficulty.gridSize;
  final maxClues = difficulty.maxClues + widen;
  final tier = deduceTierFor(difficulty);
  // Issue #93 leak-rule anchor: the room the victim stands in. The murderer
  // rule ("one guest shares a room with the victim") makes every positive
  // reference to that room a killer-naming card, so the pool builders below
  // never emit the excluded classes.
  final victimRoomId = roomOf(prep.rooms, prep.victimPos)!;

  // 5. clue pool: candidates true of the solution, every shuffled candidate
  // kept (see the cap comment above the pool literal).
  final pool = _cluePool(
    difficulty,
    prep.suspects,
    prep.rooms,
    prep.solution,
    prep.victimPos,
    victimRoomId,
    prep.objects,
    rng,
  );

  // 6. minimize to a chain-solvable set, then enforce the clue window.
  final minimized = _minimizeToChain(
    pool,
    g,
    prep.rooms,
    suspectIds(prep.suspects),
    prep.victimPos,
    prep.objects,
    tier,
  );
  if (minimized == null) return null;
  final picked = _fittedClueSet(
    difficulty,
    prep,
    pool,
    minimized,
    maxClues,
    tier,
  );
  if (picked == null) return null;
  ensureChainSolvable(
    g: g,
    rooms: prep.rooms,
    clues: picked,
    ids: suspectIds(prep.suspects),
    victimPos: prep.victimPos,
    objects: prep.objects,
    tier: tier,
  );
  return picked;
}

/// Prune, coverage, clue-window fill and the negated top-up: everything the
/// minimized set needs to fit the difficulty's window. Returns null when
/// the window cannot be met or a suspect has no pool candidate (issue 111).
List<Clue>? _fittedClueSet(
  Difficulty difficulty,
  _Prepared prep,
  List<Clue> pool,
  List<Clue> minimized,
  int maxClues,
  DeduceTier tier,
) {
  final pruned = _prune(
    minimized,
    difficulty.gridSize,
    prep.rooms,
    suspectIds(prep.suspects),
    prep.victimPos,
    prep.objects,
    tier,
  );
  var picked = ensureCoverage(pruned, pool, prep.suspects);
  if (picked == null) return null;
  if (picked.length > maxClues) return null;
  picked = _fillToMinClues(picked, pool, difficulty.minClues);
  if (picked.length < difficulty.minClues || picked.length > maxClues) {
    return null;
  }
  _topUpNegated(picked, pool, difficulty, maxClues);
  return picked;
}

/// Issue #106 hard final gate: the EXACT shipped clue set must chain-solve.
/// Every selection stage only adds solution-true clues (monotone for the
/// chain), so the throw cannot fire in correct code — it is the acceptance
/// anchor: any regression that ships an unchainable set crashes loudly.
///
/// Public seam (plainly public, like [ensureCoverage]; no
/// @visibleForTesting so this pure-Dart file stays flutter/meta-free): the
/// throw branch never fires in generated cases, and the CRAP gate requires
/// every decision branch covered — the unit test calls this directly with
/// a dead clue set to pin the throw.
void ensureChainSolvable({
  required int g,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> ids,
  required Pos victimPos,
  required List<ObjectDef> objects,
  required DeduceTier tier,
}) {
  if (_chainSolvable(
    g: g,
    rooms: rooms,
    clues: clues,
    ids: ids,
    victimPos: victimPos,
    objects: objects,
    tier: tier,
  )) {
    return;
  }
  throw StateError(
    'deduction chain failed on the shipped clue set '
    '(${clues.length} clues) — generator regression',
  );
}

/// True when [clues] fully solve by a deduction chain under [tier] — the
/// clue-selection gate predicate (issue #106). A null trace means the
/// attempt cannot ship this set.
bool _chainSolvable({
  required int g,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> ids,
  required Pos victimPos,
  required List<ObjectDef> objects,
  required DeduceTier tier,
}) =>
    Deducer(
      gridSize: g,
      rooms: rooms,
      clues: clues,
      suspectIds: ids,
      victimPos: victimPos,
      objects: objects,
      tier: tier,
    ).solve() !=
    null;

/// Coverage: no suspect may end up without a clue (empty cards confuse
/// players). Every pool clue is true of the solution, so additions are
/// chain-safe (issue #106: they never un-solve a chain-solvable set).
/// Returns null when an uncovered suspect has NO pool candidate — the
/// attempt is dropped, never filled (issue #111). The old coverage fallback
/// emitted direction cards, which the per-case direction cap can no longer
/// guarantee room for; in generated cases only the murderer can lack a
/// candidate (every other suspect always has InRoom(own room) in the pool),
/// so dropping such layouts is expected and the retry budget absorbs it.
///
/// Public seam (plainly public, like [ensureChainSolvable]; no
/// @visibleForTesting so this pure-Dart file stays flutter/meta-free): the
/// null branch fires during generation, but which attempt fails is not
/// observable from pipeline tests, and the CRAP gate requires every
/// decision branch covered — leak_filter_test.dart pins the seam directly.
List<Clue>? ensureCoverage(
  List<Clue> pruned,
  List<Clue> pool,
  List<Suspect> suspects,
) {
  final picked = [...pruned];
  final covered = picked.map((cl) => cl.suspectId).toSet();
  for (final s in suspects) {
    if (covered.contains(s.id)) continue;
    final index = pool.indexWhere((cl) => cl.suspectId == s.id);
    if (index == -1) return null;
    picked.add(pool[index]);
  }
  return picked;
}

/// Tops up a sub-window pick with pool candidates, preferring clue types the
/// case doesn't have yet so every type (e.g. the same-room item clue,
/// UX-8/ADR 0004) can appear on cards even when it never contributes to
/// the chain (a same-room BesideObject is logically an InRoom clue: one
/// guest per room). Returns the same list, mutated in place.
List<Clue> _fillToMinClues(List<Clue> picked, List<Clue> pool, int minClues) {
  if (picked.length >= minClues) return picked;
  final remaining = pool.where((c) => !picked.contains(c)).toList();
  final present = picked.map((c) => c.typeName).toSet();
  final ordered = [
    ...remaining.where((c) => !present.contains(c.typeName)),
    ...remaining.where((c) => present.contains(c.typeName)),
  ];
  for (final clue in ordered) {
    if (picked.length >= minClues) break;
    picked.add(clue); // adding clues preserves chain solvability
  }
  return picked;
}

/// Issue #10: top the picked set up to the difficulty's negated cap with
/// remaining pool candidates. Additions only: pool negated entries are true
/// of the solution, so chain solvability is preserved, and the clue window bounds
/// how many fit (attempts above maxClues were already rejected above).
void _topUpNegated(
  List<Clue> picked,
  List<Clue> pool,
  Difficulty difficulty,
  int maxClues,
) {
  final negatedCap = difficulty.maxNegatedClues;
  if (negatedCap > 0) {
    // Materialized snapshot: pool entries are distinct instances, so the
    // lazy `!picked.contains(c)` filter and this snapshot agree on every
    // element the loop visits.
    final left = _negatedLeft(pool, picked);
    var negatedCount = picked.where((c) => c.negated).length;
    for (final clue in left) {
      if (negatedCount >= negatedCap || picked.length >= maxClues) break;
      picked.add(clue);
      negatedCount++;
    }
  }
}

/// The not-yet-picked negated pool candidates, in pool order.
List<Clue> _negatedLeft(List<Clue> pool, List<Clue> picked) =>
    pool.where((c) => c.negated && !picked.contains(c)).toList();

List<String> suspectIds(List<Suspect> suspects) =>
    suspects.map((s) => s.id).toList();

/// Test seam for the issue-#93 pool-level leak assertions: rebuilds the
/// candidate pool of an already-generated case via [_cluePool] — the exact
/// call [_buildClueSet] makes when the case was born (same rooms, solution,
/// victim and objects). The positive side is rng-free: the exclusion
/// filters run at the emit sites before any shuffle, so the candidate SET
/// is data-deterministic for the case. The negated side is capped by a
/// shuffle-take, so a second run may carry a different negated subset —
/// every candidate it can carry is drawn from the already-filtered negated
/// list, which is why an excluded class appearing in ANY rebuilt pool is
/// impossible unless an emit site regressed. Lets leak_filter_test assert
/// the pool itself, not only the shipped set.
List<Clue> cluePoolFor(CaseData c) => _cluePool(
  c.difficulty,
  c.suspects,
  c.rooms,
  c.solution,
  c.victimPos,
  roomOf(c.rooms, c.victimPos)!,
  c.objects,
  Random(0),
);

/// Backtracking over rows in random order; first complete assignment wins.
Map<String, Pos>? _randomPlacement(int g, List<RoomDef> rooms, Random rng) =>
    _RandomPlacement(g, rooms, rng).search();

/// Mutable random-placement search (issue 35 decomposition). The rng call
/// order matches the original inline dfs exactly: one column shuffle per
/// row, recursing row by row.
class _RandomPlacement {
  _RandomPlacement(this.g, this.rooms, this.rng)
    : solution = <String, Pos>{},
      usedCols = List<bool>.filled(g, false),
      usedRooms = <String>{},
      suspectIds = List.generate(g, (i) => 's$i');

  final int g;
  final List<RoomDef> rooms;
  final Random rng;
  final Map<String, Pos> solution;
  final List<bool> usedCols;
  final Set<String> usedRooms;
  final List<String> suspectIds;

  Map<String, Pos>? search() => dfs(0);

  Map<String, Pos>? dfs(int row) {
    if (row == g) return Map.of(solution);
    final cols = List.generate(g, (i) => i)..shuffle(rng);
    for (final col in cols) {
      final found = tryCell(row, col);
      if (found != null) return found;
    }
    return null;
  }

  Map<String, Pos>? tryCell(int row, int col) {
    if (usedCols[col]) return null;
    final cell = (row: row, col: col);
    final roomId = roomOf(rooms, cell)!;
    if (usedRooms.contains(roomId)) return null;
    usedCols[col] = true;
    usedRooms.add(roomId);
    solution[suspectIds[row]] = cell;
    final found = dfs(row + 1);
    if (found != null) return found;
    solution.remove(suspectIds[row]);
    usedCols[col] = false;
    usedRooms.remove(roomId);
    return null;
  }
}

/// Manhattan distance between two cells.
int _manhattan(Pos a, Pos b) => (a.row - b.row).abs() + (a.col - b.col).abs();

/// Assigns suspects to rows in order (one suspect per row via the placement
/// search), so each suspect id maps to exactly one cell.
List<Clue> _cluePool(
  Difficulty difficulty,
  List<Suspect> suspects,
  List<RoomDef> rooms,
  Map<String, Pos> solution,
  Pos victimPos,
  String victimRoomId,
  List<ObjectDef> objects,
  Random rng,
) {
  final byType = <String, List<Clue>>{
    'inRoom': [],
    'onObject': [],
    'soleNearObject': [],
    'nearObject': [],
    'beside': [],
    'besideObject': [],
    'sameRow': [],
    'sameCol': [],
    'direction': [],
  };
  _positiveCandidates(
    suspects,
    solution,
    rooms,
    victimPos,
    victimRoomId,
    objects,
    byType,
  );

  // Cap each type deterministically (shuffle, then take). Issue #93: the
  // take() is dropped rather than enlarged — a shuffle-then-take cap is
  // prefix-preserving (same shuffle, bigger take appends candidates past
  // the old first 10 without moving them), so widening it never changed any
  // case the smaller pool generated; it only rescued attempts that
  // exhausted. Measured at the 9×9 board with the killer-naming exclusions
  // applied, cap 10 (the historical value) and cap 18 both starve the
  // uniqueness search — the minimize loop needs prefixes 41-100 clues
  // deep (hard seeds 1/3/5 measured) — so the pool keeps every shuffled
  // candidate. 5×5 output stays byte-identical to the cap-10 pool because
  // only post-prefix candidates are appended.
  //
  // Issue 111: the one exception is the direction type — after its shuffle
  // it keeps only its first [_maxDirectionCards] candidates, so a case can
  // never ship more direction cards than the cap. The shuffle call order is
  // untouched (no rng call added or moved).
  final pool = [
    for (final entry in byType.entries)
      ...(entry.value..shuffle(rng)).take(
        entry.key == 'direction' ? _maxDirectionCards : entry.value.length,
      ),
  ];

  // Issue #10: negated candidates, drawn TRUE of the solution (a card clue
  // is always a true statement): each raw predicate below is false of the
  // solution, so its negation holds. The pool carries at most the
  // difficulty's negated cap, so every downstream selection (minimize,
  // prune, coverage, fill) obeys the cap without any removal step. Guarded
  // by cap > 0 so easy keeps the exact old pool and rng stream. Per-type
  // caps: negated candidates join the pool like every other type; with
  // ≤3 negated in total, per-type counts stay trivially within it.
  final negatedCap = difficulty.maxNegatedClues;
  if (negatedCap > 0) {
    final negated = _negatedCandidates(
      suspects,
      solution,
      rooms,
      victimPos,
      objects,
    );
    pool.addAll((negated..shuffle(rng)).take(negatedCap));
  }
  return pool;
}

/// The positive (non-negated) candidate pool, in the original per-suspect
/// order: own room, suspect pairs (row/col, then directions, then beside),
/// victim relations, then objects (issue 35 decomposition).
///
/// Issue #93 exclusions at the emit sites: no InRoom(victim's room) — the
/// only suspect whose own room equals the victim's room is the murderer, so
/// that card names the killer; no Beside(victim) positive; and no
/// BesideObject positive for a victim's-room object (same killer-naming
/// shape). SameCol(victim) is dropped in [_victimSame].
void _positiveCandidates(
  List<Suspect> suspects,
  Map<String, Pos> solution,
  List<RoomDef> rooms,
  Pos victimPos,
  String victimRoomId,
  List<ObjectDef> objects,
  Map<String, List<Clue>> byType,
) {
  final ids = suspects.map((s) => s.id).toList();
  for (final s in ids) {
    final sp = solution[s]!;
    // InRoom: only the suspect's actual room is true of the solution — but
    // the victim's own room is never emitted positive (issue #93).
    final ownRoom = roomOf(rooms, sp)!;
    if (ownRoom != victimRoomId) {
      byType['inRoom']!.add(
        InRoom(suspectId: s, roomId: ownRoom, negated: false),
      );
    }
    _pairCandidates(ids, sp, s, solution, byType);
    _victimSame(sp, victimPos, s, byType);
    _victimDirections(sp, victimPos, s, byType);
    _objectCandidates(rooms, sp, victimRoomId, objects, s, byType);
  }
  _soleNearCandidates(suspects, solution, rooms, victimRoomId, objects, byType);
}

/// Issue 111: one pass over the items (outside the per-suspect loop): the
/// only guest within distance 1 of the item — when every other guest is
/// farther — gets a SoleNearObject candidate. Victim's-room items are
/// skipped (issue #93, same killer-naming shape as BesideObject).
void _soleNearCandidates(
  List<Suspect> suspects,
  Map<String, Pos> solution,
  List<RoomDef> rooms,
  String victimRoomId,
  List<ObjectDef> objects,
  Map<String, List<Clue>> byType,
) {
  for (final obj in objects) {
    if (roomOf(rooms, obj.pos) == victimRoomId) continue;
    final sole = _soleNearGuest(suspects, solution, obj.pos);
    if (sole == null) continue;
    byType['soleNearObject']!.add(
      SoleNearObject(suspectId: sole, objectId: obj.id, negated: false),
    );
  }
}

/// The id of the only guest within distance 1 of the item; null when none
/// or several are.
String? _soleNearGuest(
  List<Suspect> suspects,
  Map<String, Pos> solution,
  Pos itemPos,
) {
  String? sole;
  for (final s in suspects) {
    if (_manhattan(solution[s.id]!, itemPos) > 1) continue;
    if (sole != null) return null;
    sole = s.id;
  }
  return sole;
}

/// Per-pair candidates: same row/col first, then directions, then beside —
/// exactly the original emission order per pair.
void _pairCandidates(
  List<String> ids,
  Pos sp,
  String s,
  Map<String, Pos> solution,
  Map<String, List<Clue>> byType,
) {
  for (final t in ids) {
    if (t == s) continue;
    final tp = solution[t]!;
    _pairRowCol(s, sp, t, tp, byType);
    _pairDirections(s, sp, t, tp, byType);
    if (_manhattan(sp, tp) == 1) {
      byType['beside']!.add(Beside(suspectId: s, targetId: t, negated: false));
    }
  }
}

/// Same-row and same-col candidates for one suspect pair.
void _pairRowCol(
  String s,
  Pos sp,
  String t,
  Pos tp,
  Map<String, List<Clue>> byType,
) {
  if (sp.row == tp.row) {
    byType['sameRow']!.add(SameRow(suspectId: s, targetId: t, negated: false));
  }
  if (sp.col == tp.col) {
    byType['sameCol']!.add(SameCol(suspectId: s, targetId: t, negated: false));
  }
}

/// The four one-direction candidates for one suspect pair.
void _pairDirections(
  String s,
  Pos sp,
  String t,
  Pos tp,
  Map<String, List<Clue>> byType,
) {
  if (sp.row < tp.row) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: t,
        direction: Direction.north,
        negated: false,
      ),
    );
  }
  if (sp.row > tp.row) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: t,
        direction: Direction.south,
        negated: false,
      ),
    );
  }
  if (sp.col < tp.col) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: t,
        direction: Direction.west,
        negated: false,
      ),
    );
  }
  if (sp.col > tp.col) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: t,
        direction: Direction.east,
        negated: false,
      ),
    );
  }
}

/// Victim same-row candidate (issue #93: the same-col victim card is one of
/// the four excluded classes — corridor = column reads as «was with the
/// victim» — so it is never emitted in the positive pool; SameRow stays).
void _victimSame(
  Pos sp,
  Pos victimPos,
  String s,
  Map<String, List<Clue>> byType,
) {
  if (sp.row == victimPos.row) {
    byType['sameRow']!.add(
      SameRow(suspectId: s, targetId: victimId, negated: false),
    );
  }
}

/// The four one-direction victim candidates, in the original emission order.
void _victimDirections(
  Pos sp,
  Pos victimPos,
  String s,
  Map<String, List<Clue>> byType,
) {
  if (sp.row < victimPos.row) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: victimId,
        direction: Direction.north,
        negated: false,
      ),
    );
  }
  if (sp.row > victimPos.row) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: victimId,
        direction: Direction.south,
        negated: false,
      ),
    );
  }
  if (sp.col < victimPos.col) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: victimId,
        direction: Direction.west,
        negated: false,
      ),
    );
  }
  if (sp.col > victimPos.col) {
    byType['direction']!.add(
      DirectionClue(
        suspectId: s,
        targetId: victimId,
        direction: Direction.east,
        negated: false,
      ),
    );
  }
}

/// UX-8 / ADR 0004: propose the full same-room relation for every object in
/// the suspect's room, matching the BesideObject semantics (not just
/// Manhattan-1 cells). Issue #93: objects standing in the victim's room are
/// skipped on the positive side — a guest sharing a room with such an
/// object shares the victim's room, so the card names the killer.
/// Issue 111: the same skip guards the object-cell kinds — OnObject for a
/// seat the guest's solution cell IS (occupiable items only), NearObject at
/// exactly Manhattan distance 1 (the item's own cell belongs to OnObject).
void _objectCandidates(
  List<RoomDef> rooms,
  Pos sp,
  String victimRoomId,
  List<ObjectDef> objects,
  String s,
  Map<String, List<Clue>> byType,
) {
  final guestRoom = roomOf(rooms, sp);
  for (final obj in objects) {
    final objRoom = roomOf(rooms, obj.pos);
    if (objRoom == victimRoomId) continue;
    _oneObjectCandidates(obj, objRoom, guestRoom, sp, s, byType);
  }
}

/// One non-victim's-room object's positive candidates for guest [s]: the
/// same-room item clue, the seat the guest sits on, the item one step away.
void _oneObjectCandidates(
  ObjectDef obj,
  String? objRoom,
  String? guestRoom,
  Pos sp,
  String s,
  Map<String, List<Clue>> byType,
) {
  if (objRoom == guestRoom) {
    byType['besideObject']!.add(
      BesideObject(suspectId: s, objectId: obj.id, negated: false),
    );
  }
  if (obj.occupiable && obj.pos == sp) {
    byType['onObject']!.add(
      OnObject(suspectId: s, objectId: obj.id, negated: false),
    );
  }
  if (_manhattan(sp, obj.pos) == 1) {
    byType['nearObject']!.add(
      NearObject(suspectId: s, objectId: obj.id, negated: false),
    );
  }
}

/// The negated candidate pool: every raw predicate below is FALSE of the
/// solution, so its negation is true (issue #10). Per suspect: foreign
/// rooms, then per target row/col/directions/beside, then objects.
List<Clue> _negatedCandidates(
  List<Suspect> suspects,
  Map<String, Pos> solution,
  List<RoomDef> rooms,
  Pos victimPos,
  List<ObjectDef> objects,
) {
  final negated = <Clue>[];
  final ids = suspects.map((s) => s.id).toList();
  for (final s in ids) {
    final sp = solution[s]!;
    final sRoom = roomOf(rooms, sp)!;
    _negatedRooms(s, sRoom, rooms, negated);
    _negatedTargets(s, sp, ids, solution, victimPos, negated);
    _negatedObjects(s, sRoom, rooms, objects, negated);
  }
  return negated;
}

/// Every room the suspect is NOT in.
void _negatedRooms(
  String s,
  String sRoom,
  List<RoomDef> rooms,
  List<Clue> negated,
) {
  for (final r in rooms) {
    if (r.id != sRoom) {
      negated.add(InRoom(suspectId: s, roomId: r.id, negated: true));
    }
  }
}

/// Per-target negated candidates: suspect ids other than [s] plus the victim.
///
/// Issue #93: victim-target SameCol and Beside are excluded in BOTH
/// polarities — the negated forms never join the pool. SameRow(victim) and
/// the four directions stay (a negated «not in the victim's row» / strict
/// direction clue never reads as an accusation).
void _negatedTargets(
  String s,
  Pos sp,
  List<String> ids,
  Map<String, Pos> solution,
  Pos victimPos,
  List<Clue> negated,
) {
  final targets = [...ids.where((t) => t != s), victimId];
  for (final t in targets) {
    final tp = _negTargetPos(t, solution, victimPos);
    // Issue #93: the victim-target SameCol card is an excluded class in
    // both polarities — never emitted, negated included.
    _negatedRowCol(s, sp, t, tp, t != victimId, negated);
    // Issue 111: no negated direction candidates — with the per-case
    // direction cap the pool must not carry a second, uncapped polarity.
    if (_manhattan(sp, tp) != 1 && t != victimId) {
      negated.add(Beside(suspectId: s, targetId: t, negated: true));
    }
  }
}

/// The victim's cell for `V`, otherwise the target's solution cell.
Pos _negTargetPos(String t, Map<String, Pos> solution, Pos victimPos) =>
    t == victimId ? victimPos : solution[t]!;

/// Negated same-row and same-col candidates for one suspect-target pair.
/// [emitSameCol] is false only for the victim target (issue #93): the
/// victim's column card is an excluded class in both polarities.
void _negatedRowCol(
  String s,
  Pos sp,
  String t,
  Pos tp,
  bool emitSameCol,
  List<Clue> negated,
) {
  if (tp.row != sp.row) {
    negated.add(SameRow(suspectId: s, targetId: t, negated: true));
  }
  if (tp.col != sp.col && emitSameCol) {
    negated.add(SameCol(suspectId: s, targetId: t, negated: true));
  }
}

/// Every object NOT in the suspect's room.
void _negatedObjects(
  String s,
  String sRoom,
  List<RoomDef> rooms,
  List<ObjectDef> objects,
  List<Clue> negated,
) {
  for (final obj in objects) {
    if (roomOf(rooms, obj.pos) != sRoom) {
      negated.add(BesideObject(suspectId: s, objectId: obj.id, negated: true));
    }
  }
}

List<Clue>? _minimizeToChain(
  List<Clue> pool,
  int g,
  List<RoomDef> rooms,
  List<String> ids,
  Pos victimPos,
  List<ObjectDef> objects,
  DeduceTier tier,
) {
  // Plain greedy: add pool clues one by one until the set chain-solves; the
  // pruning pass afterwards removes redundancy. (The capped count cannot be
  // used to measure progress — cap hides reductions — so no smart skipping.)
  var picked = <Clue>[];
  for (final clue in pool) {
    picked.add(clue);
    if (_chainSolvable(
      g: g,
      rooms: rooms,
      clues: picked,
      ids: ids,
      victimPos: victimPos,
      objects: objects,
      tier: tier,
    )) {
      return picked;
    }
  }
  return null; // pool exhausted without reaching a solvable chain
}

/// One pruning pass: dropping a clue that keeps the set chain-solvable
/// stays dropped (issue #106: the trial predicate is chain solvability, not
/// bare uniqueness).
List<Clue> _prune(
  List<Clue> picked,
  int g,
  List<RoomDef> rooms,
  List<String> ids,
  Pos victimPos,
  List<ObjectDef> objects,
  DeduceTier tier,
) {
  var kept = [...picked];
  var i = 0;
  while (i < kept.length) {
    final trial = [...kept]..removeAt(i);
    final solvable = _chainSolvable(
      g: g,
      rooms: rooms,
      clues: trial,
      ids: ids,
      victimPos: victimPos,
      objects: objects,
      tier: tier,
    );
    if (solvable) {
      kept = trial;
    } else {
      i++;
    }
  }
  return kept;
}
