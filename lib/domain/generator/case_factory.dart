import 'dart:math';

import '../models.dart';
import '../solver.dart';
import 'rooms.dart';

/// Curated name pools (content data, not UI strings).
const _suspectNames = [
  'Ash', 'Blair', 'Casey', 'Drew', 'Ellis', 'Frank', 'Gale', 'Harper',
  'Iris', 'Jack', 'Kai', 'Lane', 'Morgan', 'Noel', 'Oakley', 'Piper',
];

const _roomNames = [
  'Hall', 'Library', 'Kitchen', 'Cellar', 'Study', 'Ballroom',
  'Conservatory', 'Parlor', 'Attic', 'Pantry', 'Gallery', 'Chapel',
  'Solarium', 'Den', 'Foyer', 'Observatory',
];

const _retryBudget = 40;

/// Public aliases for tests: the localized pools in localized_names.dart are
/// index-aligned with these.
const suspectNamePool = _suspectNames;
const roomNamePool = _roomNames;

/// Deterministic: same [difficulty] and [seed] produce an identical case.
/// Tries seeds [seed]..seed+39; if none yields a unique puzzle inside the
/// difficulty's clue window, widens the window's max by +1 and retries the
/// whole budget (up to 4 widenings), then throws [StateError].
CaseData generateCase({required Difficulty difficulty, required int seed}) {
  for (var widen = 0; widen <= 3; widen++) {
    for (var i = 0; i < _retryBudget; i++) {
      final attempt = _attempt(difficulty, seed + i, widen);
      if (attempt != null) return attempt;
    }
  }
  throw StateError(
      'no unique case found for $difficulty within budget (seed $seed)');
}

CaseData? _attempt(Difficulty difficulty, int seed, int widen) {
  final rng = Random(seed);
  final g = difficulty.gridSize;
  final maxClues = difficulty.maxClues + widen;

  // 1. rooms with themed names; suspects with themed names. Index lists are
  // shuffled (not name copies) so each entry keeps the pool slot its name
  // came from — poolIndex must index the localized pools (UX-1). Same list
  // lengths as before, so the rng stream and the drawn names are unchanged.
  final rawRooms = generateRooms(gridSize: g, rng: rng);
  final roomSlots = List.generate(_roomNames.length, (i) => i)..shuffle(rng);
  final suspectSlots =
      List.generate(_suspectNames.length, (i) => i)..shuffle(rng);
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
          poolIndex: suspectSlots[i]),
  ];

  // 2. random placement search: first valid assignment is the solution.
  final solution = _randomPlacement(g, rooms, rng);
  if (solution == null) return null;

  // 3. victim: random room, random empty cell in it; murderer = that room's guest.
  final roomOrder = [...rooms]..shuffle(rng);
  Pos? victimPos;
  RoomDef? victimRoom;
  for (final room in roomOrder) {
    final empty = room.cells.where((c) => !solution.values.contains(c)).toList()
      ..shuffle(rng);
    if (empty.isEmpty) continue;
    victimPos = empty.first;
    victimRoom = room;
    break;
  }
  if (victimPos == null || victimRoom == null) return null;
  final vRoom = victimRoom;
  final murdererId = suspects
      .firstWhere((s) => vRoom.contains(solution[s.id]!))
      .id;

  // 4. furniture. Occupiable items may sit on empty cells or under solution
  // guests (a guest on a chair); blocking items only on empty cells — the
  // solution itself never uses one, so uniqueness machinery is unaffected.
  // Never on the victim cell, at most one item per cell.
  final occupied = solution.values.toSet();
  final allCells = [
    for (final room in rooms)
      for (final cell in room.cells) cell,
  ]..shuffle(rng);
  final used = <Pos>{victimPos};
  final occupiableKinds = occupiableKindsList..shuffle(rng);
  final blockingKinds = ObjectKind.values
      .where((k) => !kindOccupiable(k) && spriteBackedBlockingKinds.contains(k))
      .toList()
    ..shuffle(rng);
  final objects = <ObjectDef>[];
  for (final cell in allCells) {
    if (objects.length >= difficulty.occupiableCount) break;
    if (used.contains(cell)) continue;
    used.add(cell); // occupiable cells are taken even when under a guest
    objects.add(ObjectDef(
      id: 'o${objects.length}',
      kind: occupiableKinds[objects.length % occupiableKinds.length],
      pos: cell,
      occupiable: true,
    ));
  }
  for (final cell in allCells) {
    if (objects.length >= difficulty.objectCount) break;
    if (used.contains(cell) || occupied.contains(cell)) continue;
    used.add(cell);
    objects.add(ObjectDef(
      id: 'o${objects.length}',
      kind: blockingKinds[objects.length % blockingKinds.length],
      pos: cell,
      occupiable: false,
    ));
  }
  if (objects.length < difficulty.objectCount) return null;

  // 5. clue pool: candidates true of the solution, per type capped at 10.
  final pool = _cluePool(difficulty, suspects, rooms, solution, victimPos, objects, rng);

  // 6. minimize to unique, then enforce the clue window.
  final minimized = _minimizeToUnique(pool, g, rooms, suspectIds(suspects),
      victimPos, objects);
  if (minimized == null) return null;
  final pruned = _prune(minimized, g, rooms, suspectIds(suspects), victimPos, objects);
  var picked = pruned;
  // Coverage: no suspect may end up without a clue (empty cards confuse
  // players). Pool clues are all true of the solution, so additions are
  // uniqueness-safe. InRoom(s, own room) always exists for every suspect.
  final covered = picked.map((cl) => cl.suspectId).toSet();
  for (final s in suspects) {
    if (covered.contains(s.id)) continue;
    final candidate = pool.firstWhere(
      (cl) => cl.suspectId == s.id,
      orElse: () => InRoom(
          suspectId: s.id,
          roomId: roomOf(rooms, solution[s.id]!)!,
          negated: false),
    );
    picked.add(candidate);
  }

  if (picked.length > maxClues) return null;
  if (picked.length < difficulty.minClues) {
    final remaining = pool.where((c) => !picked.contains(c)).toList();
    // Prefer clue types the case doesn't have yet so every type (e.g. the
    // same-room item clue, UX-8/ADR 0004) can appear on cards even when it
    // never contributes to uniqueness (a same-room BesideObject is
    // logically an InRoom clue: one guest per room).
    final present = picked.map((c) => c.typeName).toSet();
    final ordered = [
      ...remaining.where((c) => !present.contains(c.typeName)),
      ...remaining.where((c) => present.contains(c.typeName)),
    ];
    for (final clue in ordered) {
      if (picked.length >= difficulty.minClues) break;
      picked.add(clue); // adding clues preserves uniqueness
    }
    if (picked.length < difficulty.minClues) return null;
    if (picked.length > maxClues) return null;
  }

  return CaseData(
    seed: seed,
    difficulty: difficulty,
    rooms: rooms,
    objects: objects,
    suspects: suspects,
    victimPos: victimPos,
    murdererId: murdererId,
    clues: picked,
    solution: solution,
  );
}

List<String> suspectIds(List<Suspect> suspects) =>
    suspects.map((s) => s.id).toList();

/// Backtracking over rows in random order; first complete assignment wins.
Map<String, Pos>? _randomPlacement(
    int g, List<RoomDef> rooms, Random rng) {
  final solution = <String, Pos>{};
  final usedCols = List<bool>.filled(g, false);
  final usedRooms = <String>{};
  final suspectIds = List.generate(g, (i) => 's$i');

  Map<String, Pos>? dfs(int row) {
    if (row == g) return Map.of(solution);
    final cols = List.generate(g, (i) => i)..shuffle(rng);
    for (final col in cols) {
      if (usedCols[col]) continue;
      final cell = (row: row, col: col);
      final roomId = roomOf(rooms, cell)!;
      if (usedRooms.contains(roomId)) continue;
      usedCols[col] = true;
      usedRooms.add(roomId);
      solution[suspectIds[row]] = cell;
      final found = dfs(row + 1);
      if (found != null) return found;
      solution.remove(suspectIds[row]);
      usedCols[col] = false;
      usedRooms.remove(roomId);
    }
    return null;
  }

  return dfs(0);
}

/// Assigns suspects to rows in order (one suspect per row via the placement
/// search), so each suspect id maps to exactly one cell.
List<Clue> _cluePool(
  Difficulty difficulty,
  List<Suspect> suspects,
  List<RoomDef> rooms,
  Map<String, Pos> solution,
  Pos victimPos,
  List<ObjectDef> objects,
  Random rng,
) {
  final byType = <String, List<Clue>>{
    'inRoom': [],
    'sameRow': [],
    'sameCol': [],
    'direction': [],
    'beside': [],
    'besideObject': [],
  };
  final ids = suspects.map((s) => s.id).toList();
  int manhattan(Pos a, Pos b) => (a.row - b.row).abs() + (a.col - b.col).abs();

  for (final s in ids) {
    final sp = solution[s]!;
    // InRoom: only the suspect's actual room is true of the solution.
    byType['inRoom']!
        .add(InRoom(suspectId: s, roomId: roomOf(rooms, sp)!, negated: false));
    for (final t in ids) {
      if (t == s) continue;
      final tp = solution[t]!;
      if (sp.row == tp.row) {
        byType['sameRow']!.add(SameRow(suspectId: s, targetId: t, negated: false));
      }
      if (sp.col == tp.col) {
        byType['sameCol']!.add(SameCol(suspectId: s, targetId: t, negated: false));
      }
      if (sp.row < tp.row) {
        byType['direction']!.add(DirectionClue(
            suspectId: s, targetId: t, direction: Direction.north, negated: false));
      }
      if (sp.row > tp.row) {
        byType['direction']!.add(DirectionClue(
            suspectId: s, targetId: t, direction: Direction.south, negated: false));
      }
      if (sp.col < tp.col) {
        byType['direction']!.add(DirectionClue(
            suspectId: s, targetId: t, direction: Direction.west, negated: false));
      }
      if (sp.col > tp.col) {
        byType['direction']!.add(DirectionClue(
            suspectId: s, targetId: t, direction: Direction.east, negated: false));
      }
      if (manhattan(sp, tp) == 1) {
        byType['beside']!.add(Beside(suspectId: s, targetId: t, negated: false));
      }
    }
    // Victim-targeted candidates.
    if (sp.row == victimPos.row) {
      byType['sameRow']!.add(SameRow(suspectId: s, targetId: victimId, negated: false));
    }
    if (sp.col == victimPos.col) {
      byType['sameCol']!.add(SameCol(suspectId: s, targetId: victimId, negated: false));
    }
    if (sp.row < victimPos.row) {
      byType['direction']!.add(DirectionClue(
          suspectId: s, targetId: victimId, direction: Direction.north, negated: false));
    }
    if (sp.row > victimPos.row) {
      byType['direction']!.add(DirectionClue(
          suspectId: s, targetId: victimId, direction: Direction.south, negated: false));
    }
    if (sp.col < victimPos.col) {
      byType['direction']!.add(DirectionClue(
          suspectId: s, targetId: victimId, direction: Direction.west, negated: false));
    }
    if (sp.col > victimPos.col) {
      byType['direction']!.add(DirectionClue(
          suspectId: s, targetId: victimId, direction: Direction.east, negated: false));
    }
    if (manhattan(sp, victimPos) == 1) {
      byType['beside']!.add(Beside(suspectId: s, targetId: victimId, negated: false));
    }
    for (final obj in objects) {
      // UX-8 / ADR 0004: propose the full same-room relation, matching the
      // new BesideObject semantics (not just Manhattan-1 cells).
      if (roomOf(rooms, sp) == roomOf(rooms, obj.pos)) {
        byType['besideObject']!
            .add(BesideObject(suspectId: s, objectId: obj.id, negated: false));
      }
    }
  }

  // Cap each type at 10, sampled deterministically.
  return [
    for (final entry in byType.entries)
      ...(entry.value..shuffle(rng)).take(10),
  ];
}

List<Clue>? _minimizeToUnique(
  List<Clue> pool,
  int g,
  List<RoomDef> rooms,
  List<String> ids,
  Pos victimPos,
  List<ObjectDef> objects,
) {
  // Plain greedy: add pool clues one by one until the count hits 1; the
  // pruning pass afterwards removes redundancy. (The capped count cannot be
  // used to measure progress — cap hides reductions — so no smart skipping.)
  var picked = <Clue>[];
  for (final clue in pool) {
    picked.add(clue);
    if (countSolutions(
          gridSize: g,
          rooms: rooms,
          clues: picked,
          suspectIds: ids,
          victimPos: victimPos,
          objects: objects,
        ) ==
        1) {
      return picked;
    }
  }
  return null; // pool exhausted without reaching uniqueness
}

/// One pruning pass: dropping a clue that keeps uniqueness stays dropped.
List<Clue> _prune(
  List<Clue> picked,
  int g,
  List<RoomDef> rooms,
  List<String> ids,
  Pos victimPos,
  List<ObjectDef> objects,
) {
  var kept = [...picked];
  var i = 0;
  while (i < kept.length) {
    final trial = [...kept]..removeAt(i);
    final unique = countSolutions(
          gridSize: g,
          rooms: rooms,
          clues: trial,
          suspectIds: ids,
          victimPos: victimPos,
          objects: objects,
        ) == 1;
    if (unique) {
      kept = trial;
    } else {
      i++;
    }
  }
  return kept;
}
