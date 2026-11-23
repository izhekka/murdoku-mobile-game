import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/models.dart';

Pos p(int row, int col) => (row: row, col: col);

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
  ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 2)),
];

final Pos victimPos = p(2, 2);

/// Rows/cols/rooms differ per suspect so targeted clue cases are expressible.
final Map<String, Pos> placement = {
  's0': p(0, 0), // r0, col 0
  's1': p(0, 4), // r1, col 4 (same row as s0)
  's2': p(2, 1), // r2, col 1 (same row as V)
  's3': p(3, 3), // r3
  's4': p(4, 2), // r4, col 2
};

bool eval(Clue clue, {Map<String, Pos>? at}) => evaluateClue(
  clue,
  placement: at ?? placement,
  victimPos: victimPos,
  rooms: rooms,
  objects: objects,
);

void main() {
  group('InRoom', () {
    test(
      'true when suspect is in that room, false otherwise; negation inverts',
      () {
        expect(
          eval(InRoom(suspectId: 's0', roomId: 'r0', negated: false)),
          isTrue,
        );
        expect(
          eval(InRoom(suspectId: 's0', roomId: 'r1', negated: false)),
          isFalse,
        );
        expect(
          eval(InRoom(suspectId: 's0', roomId: 'r0', negated: true)),
          isFalse,
        );
        expect(
          eval(InRoom(suspectId: 's0', roomId: 'r1', negated: true)),
          isTrue,
        );
      },
    );
    test('unknown room throws', () {
      expect(
        () => eval(InRoom(suspectId: 's0', roomId: 'r9', negated: false)),
        throwsArgumentError,
      );
    });
  });

  group('SameRow', () {
    test('true on equal rows against suspect target and victim target', () {
      expect(
        eval(SameRow(suspectId: 's0', targetId: 's1', negated: false)),
        isTrue,
      );
      expect(
        eval(SameRow(suspectId: 's2', targetId: 'V', negated: false)),
        isTrue,
      );
      expect(
        eval(SameRow(suspectId: 's0', targetId: 's2', negated: false)),
        isFalse,
      );
      expect(
        eval(SameRow(suspectId: 's2', targetId: 'V', negated: true)),
        isFalse,
      );
    });
  });

  group('SameCol', () {
    test('true on equal columns, false otherwise; negation inverts', () {
      // s4 (4,2) and victim (2,2) share column 2.
      expect(
        eval(SameCol(suspectId: 's4', targetId: 'V', negated: false)),
        isTrue,
      );
      expect(
        eval(SameCol(suspectId: 's0', targetId: 's2', negated: false)),
        isFalse,
      );
      expect(
        eval(SameCol(suspectId: 's4', targetId: 'V', negated: true)),
        isFalse,
      );
    });
  });

  group('DirectionClue', () {
    test('north is strict: strictly smaller row than target', () {
      expect(
        eval(
          DirectionClue(
            suspectId: 's0',
            targetId: 's2',
            direction: Direction.north,
            negated: false,
          ),
        ),
        isTrue,
      );
      // Same row is NOT strictly north.
      expect(
        eval(
          DirectionClue(
            suspectId: 's0',
            targetId: 's1',
            direction: Direction.north,
            negated: false,
          ),
        ),
        isFalse,
      );
      // South of the target is not north of it.
      expect(
        eval(
          DirectionClue(
            suspectId: 's3',
            targetId: 's2',
            direction: Direction.north,
            negated: false,
          ),
        ),
        isFalse,
      );
    });
    test('west is strict: strictly smaller column', () {
      expect(
        eval(
          DirectionClue(
            suspectId: 's0',
            targetId: 's2',
            direction: Direction.west,
            negated: false,
          ),
        ),
        isTrue,
      );
      expect(
        eval(
          DirectionClue(
            suspectId: 's4',
            targetId: 's0',
            direction: Direction.west,
            negated: true,
          ),
        ),
        isTrue,
      ); // 2 > 0, so NOT west -> negation true
    });
  });

  group('Beside', () {
    test('true only at Manhattan distance 1; diagonal is not beside', () {
      // (2,1) and victim (2,2): Manhattan 1.
      expect(
        eval(Beside(suspectId: 's2', targetId: 'V', negated: false)),
        isTrue,
      );
      // (3,3) and (4,2) are diagonal: Manhattan 2.
      expect(
        eval(Beside(suspectId: 's3', targetId: 's4', negated: false)),
        isFalse,
      );
      expect(
        eval(Beside(suspectId: 's3', targetId: 's4', negated: true)),
        isTrue,
      );
    });
    test('negated beside against the victim resolves to victimPos', () {
      expect(
        eval(Beside(suspectId: 's2', targetId: 'V', negated: true)),
        isFalse,
      );
    });
  });

  group('BesideObject', () {
    test('true when the guest is in the object room, even far from it', () {
      // s0 (0,0) and piano (0,2) share room r0.
      expect(
        eval(BesideObject(suspectId: 's0', objectId: 'o0', negated: false)),
        isTrue,
      );
      // (1,0) is also r0: same room, Manhattan 3 from the item — still true.
      expect(
        eval(
          BesideObject(suspectId: 's1', objectId: 'o0', negated: false),
          at: {...placement, 's1': p(1, 0)},
        ),
        isTrue,
      );
      // Sitting on the item's cell (occupiable item) is the same room too.
      expect(
        eval(
          BesideObject(suspectId: 's1', objectId: 'o0', negated: false),
          at: {...placement, 's1': p(0, 2)},
        ),
        isTrue,
      );
    });
    test('false in an adjacent cell of another room (behind the wall)', () {
      // (0,3) is r1: Manhattan 1 from piano (0,2) but through the wall.
      expect(
        eval(
          BesideObject(suspectId: 's1', objectId: 'o0', negated: false),
          at: {...placement, 's1': p(0, 3)},
        ),
        isFalse,
      );
      // (2,1) is r2: different room; negation inverts.
      expect(
        eval(BesideObject(suspectId: 's2', objectId: 'o0', negated: false)),
        isFalse,
      );
      expect(
        eval(BesideObject(suspectId: 's2', objectId: 'o0', negated: true)),
        isTrue,
      );
    });
    test('unknown object throws', () {
      expect(
        () =>
            eval(BesideObject(suspectId: 's0', objectId: 'o9', negated: false)),
        throwsArgumentError,
      );
    });
  });

  test('unknown suspect or target ids throw', () {
    expect(
      () => eval(InRoom(suspectId: 's9', roomId: 'r0', negated: false)),
      throwsArgumentError,
    );
    expect(
      () => eval(SameRow(suspectId: 's0', targetId: 's9', negated: false)),
      throwsArgumentError,
    );
  });

  test('clue referencing itself throws', () {
    expect(
      () => eval(SameRow(suspectId: 's0', targetId: 's0', negated: false)),
      throwsArgumentError,
    );
    expect(
      () => eval(SameCol(suspectId: 's0', targetId: 's0', negated: false)),
      throwsArgumentError,
    );
    expect(
      () => eval(
        DirectionClue(
          suspectId: 's0',
          targetId: 's0',
          direction: Direction.north,
          negated: false,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => eval(Beside(suspectId: 's1', targetId: 's1', negated: false)),
      throwsArgumentError,
    );
  });
}
