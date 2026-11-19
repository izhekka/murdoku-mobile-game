import 'models.dart';

int _manhattan(Pos a, Pos b) => (a.row - b.row).abs() + (a.col - b.col).abs();

/// Evaluates a clue against a candidate placement. [placement] maps suspectId
/// -> Pos for ALL suspects. The target id `V` resolves to [victimPos].
/// Throws ArgumentError if the clue references an unknown id or has
/// suspectId == targetId.
bool evaluateClue(
  Clue clue, {
  required Map<String, Pos> placement,
  required Pos victimPos,
  required List<RoomDef> rooms,
  required List<ObjectDef> objects,
}) {
  final suspectPos = placement[clue.suspectId] ??
      (throw ArgumentError('unknown suspect id: ${clue.suspectId}'));

  Pos posOf(String id) {
    if (id == victimId) return victimPos;
    return placement[id] ?? (throw ArgumentError('unknown target id: $id'));
  }

  RoomDef roomById(String roomId) => rooms
      .firstWhere((r) => r.id == roomId,
          orElse: () => throw ArgumentError('unknown room id: $roomId'));

  ObjectDef objectById(String objectId) => objects
      .firstWhere((o) => o.id == objectId,
          orElse: () => throw ArgumentError('unknown object id: $objectId'));

  bool raw;
  switch (clue) {
    case InRoom(:final roomId):
      raw = roomById(roomId).contains(suspectPos);
    case SameRow(:final targetId):
      if (targetId == clue.suspectId) {
        throw ArgumentError('clue references its own suspect: $targetId');
      }
      raw = suspectPos.row == posOf(targetId).row;
    case SameCol(:final targetId):
      if (targetId == clue.suspectId) {
        throw ArgumentError('clue references its own suspect: $targetId');
      }
      raw = suspectPos.col == posOf(targetId).col;
    case DirectionClue(:final targetId, :final direction):
      if (targetId == clue.suspectId) {
        throw ArgumentError('clue references its own suspect: $targetId');
      }
      final t = posOf(targetId);
      raw = switch (direction) {
        Direction.north => suspectPos.row < t.row,
        Direction.south => suspectPos.row > t.row,
        Direction.west => suspectPos.col < t.col,
        Direction.east => suspectPos.col > t.col,
      };
    case Beside(:final targetId):
      if (targetId == clue.suspectId) {
        throw ArgumentError('clue references its own suspect: $targetId');
      }
      raw = _manhattan(suspectPos, posOf(targetId)) == 1;
    case BesideObject(:final objectId):
      raw = _manhattan(suspectPos, objectById(objectId).pos) == 1;
  }
  return clue.negated ? !raw : raw;
}
