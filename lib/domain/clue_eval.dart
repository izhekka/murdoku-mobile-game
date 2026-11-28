import 'package:murdoku/domain/models.dart';

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
  final suspectPos =
      placement[clue.suspectId] ??
      (throw ArgumentError('unknown suspect id: ${clue.suspectId}'));
  final raw = _holds(
    clue,
    suspectPos,
    placement: placement,
    victimPos: victimPos,
    rooms: rooms,
    objects: objects,
  );
  return clue.negated ? !raw : raw;
}

/// Dispatches the raw (pre-negation) predicate per clue family: the room-
/// and object-anchored kinds resolve their anchor by id, the target-bearing
/// kinds resolve the target's position (issue 35 decomposition).
bool _holds(
  Clue clue,
  Pos suspectPos, {
  required Map<String, Pos> placement,
  required Pos victimPos,
  required List<RoomDef> rooms,
  required List<ObjectDef> objects,
}) {
  if (clue is InRoom) return _roomHolds(clue.roomId, suspectPos, rooms);
  if (clue is BesideObject) {
    // UX-8 / ADR 0004: the item clue means the guest shares the item's
    // room, not Manhattan-adjacency through a wall.
    final item = _objectById(clue.objectId, objects);
    return roomOf(rooms, suspectPos) == roomOf(rooms, item.pos);
  }
  if (clue is Beside) {
    return _manhattan(
          suspectPos,
          _targetPos(clue.targetId, clue.suspectId, placement, victimPos),
        ) ==
        1;
  }
  // Issue 111 object-cell kinds anchor on the item, not on a target.
  final objectCell = _objectCellHolds(
    clue,
    suspectPos,
    placement: placement,
    objects: objects,
  );
  if (objectCell != null) return objectCell;
  return _targetHolds(
    clue,
    suspectPos,
    placement: placement,
    victimPos: victimPos,
    rooms: rooms,
  );
}

/// The issue-111 object-cell kinds' raw predicate; null when [clue] is none
/// of them, so the caller falls through to the target-bearing kinds.
bool? _objectCellHolds(
  Clue clue,
  Pos suspectPos, {
  required Map<String, Pos> placement,
  required List<ObjectDef> objects,
}) {
  if (clue is OnObject) {
    return suspectPos == _objectById(clue.objectId, objects).pos;
  }
  if (clue is NearObject) {
    return _manhattan(suspectPos, _objectById(clue.objectId, objects).pos) <= 1;
  }
  if (clue is SoleNearObject) {
    return _soleNearHolds(clue, suspectPos, placement, objects);
  }
  return null;
}

/// SoleNearObject: the card's guest is near the item AND every OTHER guest
/// is farther than distance 1 (checked over the full [placement]).
bool _soleNearHolds(
  SoleNearObject clue,
  Pos suspectPos,
  Map<String, Pos> placement,
  List<ObjectDef> objects,
) {
  final itemPos = _objectById(clue.objectId, objects).pos;
  if (_manhattan(suspectPos, itemPos) > 1) return false;
  for (final entry in placement.entries) {
    if (entry.key == clue.suspectId) continue;
    if (_manhattan(entry.value, itemPos) <= 1) return false;
  }
  return true;
}

/// The raw predicate for the positional target-bearing clue kinds (row,
/// column and direction; [Beside] is handled in [_holds]).
bool _targetHolds(
  Clue clue,
  Pos suspectPos, {
  required Map<String, Pos> placement,
  required Pos victimPos,
  required List<RoomDef> rooms,
}) => switch (clue) {
  SameRow(:final targetId) =>
    suspectPos.row ==
        _targetPos(targetId, clue.suspectId, placement, victimPos).row,
  SameCol(:final targetId) =>
    suspectPos.col ==
        _targetPos(targetId, clue.suspectId, placement, victimPos).col,
  DirectionClue(:final targetId, :final direction) => _directionHolds(
    direction,
    suspectPos,
    _targetPos(targetId, clue.suspectId, placement, victimPos),
  ),
  _ => throw ArgumentError('no target-bearing predicate for: $clue'),
};

/// True when [suspectPos] lies strictly in [direction] of [targetPos].
bool _directionHolds(Direction direction, Pos suspectPos, Pos targetPos) =>
    switch (direction) {
      Direction.north => suspectPos.row < targetPos.row,
      Direction.south => suspectPos.row > targetPos.row,
      Direction.west => suspectPos.col < targetPos.col,
      Direction.east => suspectPos.col > targetPos.col,
    };

/// Resolves a clue's target position: the victim cell for `V`, otherwise the
/// suspect's placement. Self-referencing and unknown ids throw.
Pos _targetPos(
  String targetId,
  String suspectId,
  Map<String, Pos> placement,
  Pos victimPos,
) {
  if (targetId == suspectId) {
    throw ArgumentError('clue references its own suspect: $targetId');
  }
  if (targetId == victimId) return victimPos;
  return placement[targetId] ??
      (throw ArgumentError('unknown target id: $targetId'));
}

/// True when [suspectPos] is inside the room with id [roomId].
bool _roomHolds(String roomId, Pos suspectPos, List<RoomDef> rooms) {
  final room = rooms.firstWhere(
    (r) => r.id == roomId,
    orElse: () => throw ArgumentError('unknown room id: $roomId'),
  );
  return room.contains(suspectPos);
}

/// The furniture item with id [objectId]; unknown ids throw.
ObjectDef _objectById(String objectId, List<ObjectDef> objects) =>
    objects.firstWhere(
      (o) => o.id == objectId,
      orElse: () => throw ArgumentError('unknown object id: $objectId'),
    );
