import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/models.dart';

/// Core backtracking search shared by [countSolutions] and [firstSolution].
///
/// Assigns suspects to (row, col) cells row by row with room pruning, and
/// checks each clue incrementally — a clue is evaluated as soon as every
/// suspect it references is placed, so branches die long before the leaf.
/// The victim id `V` never blocks evaluation (always resolvable).
///
/// Returns the number of solutions found, capped: stops once [cap] solutions
/// exist. [capture] receives the first solution found.
int _search({
  required int gridSize,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> suspectIds,
  required Pos victimPos,
  required List<ObjectDef> objects,
  required int cap,
  List<Map<String, Pos>>? capture,
}) {
  // roomId per cell, precomputed.
  final roomId = _roomIdGrid(gridSize, rooms);
  final indexOf = {
    for (var i = 0; i < suspectIds.length; i++) suspectIds[i]: i,
  };
  final clueMasks = clues.map((clue) => _clueMaskFor(clue, indexOf)).toList();
  final state = _SearchState(
    gridSize: gridSize,
    rooms: rooms,
    clues: clues,
    suspectIds: suspectIds,
    victimPos: victimPos,
    objects: objects,
    cap: cap,
    clueMasks: clueMasks,
    indexOf: indexOf,
    roomId: roomId,
  )..capture = capture;
  state.dfs(0);
  return state.count;
}

/// Mutable state of one backtracking search run: config fields are
/// read-only, the search fields mutate in place (issue 35 decomposition).
class _SearchState {
  _SearchState({
    required this.gridSize,
    required this.rooms,
    required this.clues,
    required this.suspectIds,
    required this.victimPos,
    required this.objects,
    required this.cap,
    required this.clueMasks,
    required this.indexOf,
    required this.roomId,
  }) : checked = List<bool>.filled(clues.length, false),
       evaluatedAt = List.generate(gridSize + 1, (_) => <int>[]),
       placement = <String, Pos>{},
       usedCols = List<bool>.filled(gridSize, false),
       usedRooms = <String>{};

  // Search configuration.
  final int gridSize;
  final List<RoomDef> rooms;
  final List<Clue> clues;
  final List<String> suspectIds;
  final Pos victimPos;
  final List<ObjectDef> objects;
  final int cap;
  final List<int> clueMasks;
  final Map<String, int> indexOf;
  final List<List<String>> roomId;

  // Mutable search state.
  final List<bool> checked;
  final List<List<int>> evaluatedAt;
  final Map<String, Pos> placement;
  final List<bool> usedCols;
  final Set<String> usedRooms;
  int placedMask = 0;
  int count = 0;

  /// Receives the first solution found; null when the caller does not want
  /// it.
  List<Map<String, Pos>>? capture;

  /// The search's row-expansion loop: cap check, leaf recording, then the
  /// column sweep. Returns early once [cap] solutions exist.
  void dfs(int row) {
    if (count >= cap) return;
    if (row == gridSize) {
      _recordSolution();
      return;
    }
    for (var col = 0; col < gridSize; col++) {
      if (_tryColumn(row, col)) return;
    }
  }

  /// Places each unplaced suspect into the free column cell and recurses.
  /// Returns true when the solution cap was reached and the caller (an
  /// ancestor dfs frame) must stop.
  bool _trySuspects(int row, int col, Pos cell, String rid) {
    for (final suspect in suspectIds) {
      if (placement.containsKey(suspect)) continue;
      placement[suspect] = cell;
      usedCols[col] = true;
      usedRooms.add(rid);
      placedMask |= 1 << indexOf[suspect]!;
      if (checkNewClues(row)) {
        dfs(row + 1);
      }
      uncheck(row);
      placedMask &= ~(1 << indexOf[suspect]!);
      placement.remove(suspect);
      usedCols[col] = false;
      usedRooms.remove(rid);
      if (count >= cap) return true;
    }
    return false;
  }

  /// One column of the row sweep: skip unusable cells, then try every
  /// unplaced suspect in it. Returns true when the cap was reached.
  bool _tryColumn(int row, int col) {
    if (usedCols[col]) return false;
    final cell = (row: row, col: col);
    if (cell == victimPos) return false;
    final rid = roomId[row][col];
    if (usedRooms.contains(rid)) return false;
    if (_blockedByObject(cell)) return false;
    return _trySuspects(row, col, cell, rid);
  }

  /// True when [cell] holds furniture a guest may not share.
  bool _blockedByObject(Pos cell) =>
      objects.any((o) => !o.occupiable && o.pos == cell);

  /// Evaluates newly-checkable clues; false when any fails (branch is dead).
  bool checkNewClues(int depth) {
    for (var ci = 0; ci < clues.length; ci++) {
      if (checked[ci]) continue;
      if (placedMask & clueMasks[ci] != clueMasks[ci]) continue;
      checked[ci] = true;
      evaluatedAt[depth].add(ci);
      if (!evaluateClue(
        clues[ci],
        placement: placement,
        victimPos: victimPos,
        rooms: rooms,
        objects: objects,
      )) {
        return false;
      }
    }
    return true;
  }

  /// Undoes [checkNewClues]'s evaluations at this depth, for backtrack.
  void uncheck(int depth) {
    for (final ci in evaluatedAt[depth]) {
      checked[ci] = false;
    }
    evaluatedAt[depth].clear();
  }

  /// Counts one complete placement and captures the first one requested.
  void _recordSolution() {
    count++;
    final capture = this.capture;
    if (capture != null && capture.isEmpty) capture.add(Map.of(placement));
  }
}

/// roomId per cell of a G×G grid, precomputed once per search.
List<List<String>> _roomIdGrid(int g, List<RoomDef> rooms) => List.generate(
  g,
  (row) => List.generate(g, (col) => roomOf(rooms, (row: row, col: col))!),
);

/// The id a target-bearing clue compares against; null for the room- and
/// object-anchored kinds.
String? _clueTargetOf(Clue clue) => switch (clue) {
  SameRow(:final targetId) => targetId,
  SameCol(:final targetId) => targetId,
  DirectionClue(:final targetId) => targetId,
  Beside(:final targetId) => targetId,
  _ => null,
};

/// Bitmask of suspect indices each clue needs before it can be evaluated.
int _clueMaskFor(Clue clue, Map<String, int> indexOf) {
  var mask = 0;
  void mark(String? id) {
    if (id == null || id == victimId) return;
    final i = indexOf[id];
    if (i != null) mask |= 1 << i;
  }

  mark(clue.suspectId);
  mark(_clueTargetOf(clue));
  return mask;
}

/// Counts complete placements satisfying one guest per row/column/room
/// (victim cell excluded) plus all clues.
///
/// Returns `min(actualCount, cap)`: a result equal to [cap] means "at least
/// [cap] solutions exist", `1` means the clue set is unique, `0` impossible.
int countSolutions({
  required int gridSize,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> suspectIds,
  required Pos victimPos,
  required List<ObjectDef> objects,
  int cap = 2,
}) => _search(
  gridSize: gridSize,
  rooms: rooms,
  clues: clues,
  suspectIds: suspectIds,
  victimPos: victimPos,
  objects: objects,
  cap: cap,
);

/// Returns the single solution when the clue set is unique, null otherwise
/// (zero or multiple solutions).
Map<String, Pos>? firstSolution({
  required int gridSize,
  required List<RoomDef> rooms,
  required List<Clue> clues,
  required List<String> suspectIds,
  required Pos victimPos,
  required List<ObjectDef> objects,
}) {
  final capture = <Map<String, Pos>>[];
  final count = _search(
    gridSize: gridSize,
    rooms: rooms,
    clues: clues,
    suspectIds: suspectIds,
    victimPos: victimPos,
    objects: objects,
    cap: 2,
    capture: capture,
  );
  return count == 1 ? capture.first : null;
}
