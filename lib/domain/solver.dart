import 'clue_eval.dart';
import 'models.dart';

/// Counts complete placements satisfying one guest per row/column/room
/// (victim cell excluded) plus all clues. Backtracking over rows; clues are
/// evaluated only at complete assignments since they may reference any
/// suspect.
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
}) {
  final placement = <String, Pos>{};
  final usedCols = List<bool>.filled(gridSize, false);
  final usedRooms = <String>{};
  var count = 0;

  void dfs(int row) {
    if (count >= cap) return;
    if (row == gridSize) {
      for (final clue in clues) {
        if (!evaluateClue(
          clue,
          placement: placement,
          victimPos: victimPos,
          rooms: rooms,
          objects: objects,
        )) {
          return;
        }
      }
      count++;
      return;
    }
    for (var col = 0; col < gridSize; col++) {
      if (usedCols[col]) continue;
      final cell = (row: row, col: col);
      if (cell == victimPos) continue;
      final roomId = roomOf(rooms, cell)!;
      if (usedRooms.contains(roomId)) continue;
      for (final suspect in suspectIds) {
        if (placement.containsKey(suspect)) continue;
        placement[suspect] = cell;
        usedCols[col] = true;
        usedRooms.add(roomId);
        dfs(row + 1);
        placement.remove(suspect);
        usedCols[col] = false;
        usedRooms.remove(roomId);
        if (count >= cap) return;
      }
    }
  }

  dfs(0);
  return count;
}

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
  final placement = <String, Pos>{};
  final usedCols = List<bool>.filled(gridSize, false);
  final usedRooms = <String>{};
  final first = <String, Pos>{};
  var count = 0;

  void dfs(int row) {
    if (count >= 2) return;
    if (row == gridSize) {
      for (final clue in clues) {
        if (!evaluateClue(
          clue,
          placement: placement,
          victimPos: victimPos,
          rooms: rooms,
          objects: objects,
        )) {
          return;
        }
      }
      count++;
      if (first.isEmpty) first.addAll(placement);
      return;
    }
    for (var col = 0; col < gridSize; col++) {
      if (usedCols[col]) continue;
      final cell = (row: row, col: col);
      if (cell == victimPos) continue;
      final roomId = roomOf(rooms, cell)!;
      if (usedRooms.contains(roomId)) continue;
      for (final suspect in suspectIds) {
        if (placement.containsKey(suspect)) continue;
        placement[suspect] = cell;
        usedCols[col] = true;
        usedRooms.add(roomId);
        dfs(row + 1);
        placement.remove(suspect);
        usedCols[col] = false;
        usedRooms.remove(roomId);
        if (count >= 2) return;
      }
    }
  }

  dfs(0);
  return count == 1 ? first : null;
}
