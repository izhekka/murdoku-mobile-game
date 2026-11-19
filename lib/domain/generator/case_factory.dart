import 'dart:math';

import '../clue_eval.dart';
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

  // 1. rooms with themed names; suspects with themed names.
  final rawRooms = generateRooms(gridSize: g, rng: rng);
  final roomNames = [..._roomNames]..shuffle(rng);
  final suspectNames = [..._suspectNames]..shuffle(rng);
  final rooms = [
    for (var i = 0; i < g; i++)
      RoomDef(id: rawRooms[i].id, name: roomNames[i], cells: rawRooms[i].cells),
  ];
  final suspects = [
    for (var i = 0; i < g; i++) Suspect(id: 's$i', name: suspectNames[i]),
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
  final vPos = victimPos;
  final vRoom = victimRoom;
  final murdererId = suspects
      .firstWhere((s) => vRoom.contains(solution[s.id]!))
      .id;

  // 4. objects on distinct random empty cells, distinct kinds.
  final occupied = solution.values.toSet();
  final emptyCells = [
    for (final room in rooms)
      for (final cell in room.cells)
        if (!occupied.contains(cell) && cell != victimPos) cell,
  ]..shuffle(rng);
  if (emptyCells.length < difficulty.objectCount) return null;
  final kinds = ObjectKind.values.toList()..shuffle(rng);
  final objects = [
    for (var i = 0; i < difficulty.objectCount; i++)
      ObjectDef(id: 'o$i', kind: kinds[i], pos: emptyCells[i]),
  ];

  // 5. clue pool: candidates true of the solution, per type capped at 10.
  final pool = _cluePool(difficulty, suspects, rooms, solution, victimPos, objects, rng);

  // 6. minimize to unique, then enforce the clue window.
  final minimized = _minimizeToUnique(pool, g, rooms, suspectIds(suspects),
      victimPos, objects);
  if (minimized == null) return null;
  final pruned = _prune(minimized, g, rooms, suspectIds(suspects), victimPos, objects);
  var picked = pruned;
  if (picked.length > maxClues) return null;
  if (picked.length < difficulty.minClues) {
    final remaining = pool.where((c) => !picked.contains(c)).toList();
    for (final clue in remaining) {
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
      if (manhattan(sp, obj.pos) == 1) {
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
