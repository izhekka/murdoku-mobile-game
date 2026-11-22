import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

Pos p(int row, int col) => (row: row, col: col);

final Map<String, Pos> solution = {
  's0': p(0, 4),
  's1': p(1, 0),
  's2': p(2, 1),
  's3': p(3, 3),
  's4': p(4, 2),
};

final List<RoomDef> rooms = [
  RoomDef(
    id: 'r0',
    name: 'Hall',
    cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)],
  ),
  RoomDef(
    id: 'r1',
    name: 'Library',
    cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)],
  ),
  RoomDef(
    id: 'r2',
    name: 'Kitchen',
    cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)],
  ),
  RoomDef(
    id: 'r3',
    name: 'Cellar',
    cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)],
  ),
  RoomDef(
    id: 'r4',
    name: 'Study',
    cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)],
  ),
];

final List<ObjectDef> objects = [
  ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 1)),
  ObjectDef(id: 'o1', kind: ObjectKind.clock, pos: p(4, 4)),
];

final Pos victim = p(2, 2);

/// Six-clue set proven unique (exactly 1 valid placement) by exhaustive
/// enumeration over this fixture.
final List<Clue> uniqueClues = [
  Beside(suspectId: 's2', targetId: 'V', negated: false),
  InRoom(suspectId: 's3', roomId: 'r3', negated: false),
  SameCol(suspectId: 's4', targetId: 'V', negated: false),
  DirectionClue(
    suspectId: 's3',
    targetId: 's0',
    direction: Direction.west,
    negated: false,
  ),
  InRoom(suspectId: 's4', roomId: 'r4', negated: false),
  DirectionClue(
    suspectId: 's1',
    targetId: 's0',
    direction: Direction.south,
    negated: false,
  ),
];

const List<String> suspectIds = ['s0', 's1', 's2', 's3', 's4'];

Map<String, Pos> run() => firstSolution(
  gridSize: 5,
  rooms: rooms,
  clues: uniqueClues,
  suspectIds: suspectIds,
  victimPos: victim,
  objects: objects,
)!;

int count({List<Clue>? clues, int cap = 2}) => countSolutions(
  gridSize: 5,
  rooms: rooms,
  clues: clues ?? uniqueClues,
  suspectIds: suspectIds,
  victimPos: victim,
  objects: objects,
  cap: cap,
);

void main() {
  test('unique clue set yields exactly one solution equal to the fixture', () {
    expect(count(), 1);
    expect(run(), equals(solution));
  });

  test('a two-clue subset has more than one solution (capped at 2)', () {
    expect(count(clues: uniqueClues.sublist(0, 2)), 2);
  });

  test('no clues on 5x5 saturates the cap', () {
    expect(count(clues: []), 2);
  });

  test('cap is respected', () {
    expect(count(cap: 1), 1);
  });

  test('firstSolution returns null when not unique', () {
    expect(
      firstSolution(
        gridSize: 5,
        rooms: rooms,
        clues: uniqueClues.sublist(0, 2),
        suspectIds: suspectIds,
        victimPos: victim,
        objects: objects,
      ),
      isNull,
    );
  });
}
