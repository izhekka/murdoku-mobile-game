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
  final g = gridSize;
  // roomId per cell, precomputed.
  final roomId = List.generate(
    g,
    (row) => List.generate(g, (col) => roomOf(rooms, (row: row, col: col))!),
  );

  // Bitmask of suspect indices each clue needs before it can be evaluated.
  final indexOf = {
    for (var i = 0; i < suspectIds.length; i++) suspectIds[i]: i,
  };
  String? targetOf(Clue clue) => switch (clue) {
    SameRow(:final targetId) => targetId,
    SameCol(:final targetId) => targetId,
    DirectionClue(:final targetId) => targetId,
    Beside(:final targetId) => targetId,
    _ => null,
  };

  int maskFor(Clue clue) {
    var mask = 0;
    void mark(String? id) {
      if (id == null || id == victimId) return;
      final i = indexOf[id];
      if (i != null) mask |= 1 << i;
    }

    mark(clue.suspectId);
    mark(targetOf(clue));
    return mask;
  }

  final clueMasks = clues.map(maskFor).toList();
  final checked = List<bool>.filled(clues.length, false);
  // Clue indices newly evaluated at each DFS depth, for undo on backtrack.
  final evaluatedAt = List.generate(g + 1, (_) => <int>[]);

  final placement = <String, Pos>{};
  final usedCols = List<bool>.filled(g, false);
  final usedRooms = <String>{};
  var placedMask = 0;
  var count = 0;

  // Evaluates newly-checkable clues; false when any fails (branch is dead).
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

  void uncheck(int depth) {
    for (final ci in evaluatedAt[depth]) {
      checked[ci] = false;
    }
    evaluatedAt[depth].clear();
  }

  void dfs(int row) {
    if (count >= cap) return;
    if (row == g) {
      count++;
      if (capture != null && capture.isEmpty) capture.add(Map.of(placement));
      return;
    }
    for (var col = 0; col < g; col++) {
      if (usedCols[col]) continue;
      final cell = (row: row, col: col);
      if (cell == victimPos) continue;
      final rid = roomId[row][col];
      if (usedRooms.contains(rid)) continue;
      if (objects.any((o) => !o.occupiable && o.pos == cell)) continue;
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
        if (count >= cap) return;
      }
    }
  }

  dfs(0);
  return count;
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
