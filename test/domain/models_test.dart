import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/models.dart';

Pos p(int row, int col) => (row: row, col: col);

/// Hand-written 5x5 fixture covering every [Clue] subtype, positive and
/// negated. Structurally valid: one guest per row/col/room, victim cell
/// empty, murderer shares the victim's room.
CaseData fixture() {
  Pos p(int row, int col) => (row: row, col: col);
  return CaseData(
    seed: 42,
    difficulty: Difficulty.easy,
    rooms: [
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
    ],
    objects: [
      ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 1)),
      ObjectDef(id: 'o1', kind: ObjectKind.clock, pos: p(4, 4)),
    ],
    suspects: [
      Suspect(id: 's0', name: 'Ash'),
      Suspect(id: 's1', name: 'Blair'),
      Suspect(id: 's2', name: 'Casey'),
      Suspect(id: 's3', name: 'Drew'),
      Suspect(id: 's4', name: 'Ellis'),
    ],
    victimPos: p(2, 2),
    murdererId: 's2',
    clues: [
      InRoom(suspectId: 's0', roomId: 'r0', negated: false),
      InRoom(suspectId: 's1', roomId: 'r1', negated: true),
      SameRow(suspectId: 's2', targetId: 'V', negated: false),
      SameRow(suspectId: 's0', targetId: 's4', negated: true),
      SameCol(suspectId: 's1', targetId: 's3', negated: false),
      SameCol(suspectId: 's2', targetId: 'V', negated: true),
      DirectionClue(
        suspectId: 's3',
        targetId: 'V',
        direction: Direction.north,
        negated: false,
      ),
      DirectionClue(
        suspectId: 's4',
        targetId: 's0',
        direction: Direction.west,
        negated: true,
      ),
      Beside(suspectId: 's0', targetId: 's1', negated: false),
      Beside(suspectId: 's3', targetId: 's4', negated: true),
      BesideObject(suspectId: 's2', objectId: 'o0', negated: false),
      BesideObject(suspectId: 's4', objectId: 'o1', negated: true),
    ],
    solution: {
      's0': p(0, 0),
      's1': p(1, 4),
      's2': p(2, 1),
      's3': p(3, 3),
      's4': p(4, 2),
    },
  );
}

void main() {
  test('difficulty extension values match the spec table', () {
    expect(Difficulty.easy.gridSize, 5);
    expect(Difficulty.standard.gridSize, 6);
    expect(Difficulty.hard.gridSize, 7);
    // Amended by the furniture addendum: 3+5 / 4+6 / 5+9 items.
    expect(Difficulty.easy.objectCount, 8);
    expect(Difficulty.standard.objectCount, 10);
    expect(Difficulty.hard.objectCount, 14);
    expect(Difficulty.easy.minClues, 6);
    expect(Difficulty.standard.minClues, 8);
    expect(Difficulty.hard.minClues, 10);
    expect(Difficulty.easy.maxClues, 9);
    expect(Difficulty.standard.maxClues, 12);
    expect(Difficulty.hard.maxClues, 14);
    // Issue #10: negated clues per case, gated by difficulty.
    expect(Difficulty.easy.maxNegatedClues, 0);
    expect(Difficulty.standard.maxNegatedClues, 1);
    expect(Difficulty.hard.maxNegatedClues, 3);
  });

  test('occupiable kinds are chairs and sofas only', () {
    expect(kindOccupiable(ObjectKind.chair), isTrue);
    expect(kindOccupiable(ObjectKind.sofa), isTrue);
    expect(kindOccupiable(ObjectKind.table), isFalse);
    expect(kindOccupiable(ObjectKind.piano), isFalse);
    expect(kindOccupiable(ObjectKind.flowers), isFalse);
  });

  test('furniture counts per difficulty', () {
    expect(Difficulty.easy.occupiableCount, 3);
    expect(Difficulty.easy.blockingCount, 5);
    expect(Difficulty.standard.occupiableCount, 4);
    expect(Difficulty.standard.blockingCount, 6);
    expect(Difficulty.hard.occupiableCount, 5);
    expect(Difficulty.hard.blockingCount, 9);
    expect(Difficulty.easy.objectCount, 8);
    expect(Difficulty.standard.objectCount, 10);
    expect(Difficulty.hard.objectCount, 14);
  });

  test('ObjectDef occupiable flag round-trips', () {
    final o = ObjectDef(
      id: 'o0',
      kind: ObjectKind.chair,
      pos: p(0, 1),
      occupiable: true,
    );
    final restored = ObjectDef.fromJson(o.toJson());
    expect(restored, equals(o));
    expect(restored.occupiable, isTrue);
  });

  test('CaseData json round-trip preserves every clue subtype', () {
    final c = fixture();
    final restored = CaseData.fromJson(c.toJson());
    expect(restored, equals(c));
    expect(restored.toJson(), equals(c.toJson()));
  });

  test('value equality distinguishes different cases', () {
    final a = fixture();
    final b = fixture().copyWith(murdererId: 's3');
    expect(a, equals(fixture()));
    expect(a, isNot(equals(b)));
  });

  test('copyWith replaces only the given field', () {
    final c = fixture();
    final copy = c.copyWith(seed: 7);
    expect(copy.seed, 7);
    expect(copy.copyWith(seed: c.seed), equals(c));
  });

  test('unknown clue type throws FormatException (issue 35)', () {
    final json = fixture().toJson();
    (json['clues'] as List<Object?>).add({
      'type': 'unknown',
      'suspectId': 's0',
      'negated': false,
    });
    expect(
      () => CaseData.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('unknown clue type'),
        ),
      ),
    );
  });

  test('BoardSnapshot equality compares every field (issue 35)', () {
    BoardSnapshot snap({
      Map<String, Pos>? placed,
      Set<Pos>? xMarks,
      Duration elapsed = const Duration(seconds: 10),
      int hintsUsed = 1,
      int wrongAccusations = 2,
      Set<String> eliminated = const {'s1'},
    }) => BoardSnapshot(
      placed: placed ?? {'s0': p(0, 0)},
      xMarks: xMarks ?? {p(3, 3)},
      elapsed: elapsed,
      hintsUsed: hintsUsed,
      wrongAccusations: wrongAccusations,
      eliminatedSuspects: eliminated,
    );

    final base = snap();
    expect(base, snap());
    expect(base.hashCode, snap().hashCode);
    expect(base, isNot(equals(Object())));

    // Placed map: same content, different order is equal; extra entry is not.
    expect(base, snap(placed: {'s0': p(0, 0)}));
    expect(base, isNot(snap(placed: {'s0': p(0, 0), 's1': p(1, 1)})));
    expect(base, isNot(snap(placed: {'s1': p(0, 0)})));

    // X marks set: same content equal; different content or size is not.
    expect(base, isNot(snap(xMarks: {p(4, 4)})));
    expect(base, isNot(snap(xMarks: {p(3, 3), p(4, 4)})));

    expect(base, isNot(snap(elapsed: const Duration(seconds: 11))));
    expect(base, isNot(snap(hintsUsed: 2)));
    expect(base, isNot(snap(wrongAccusations: 3)));
    expect(base, isNot(snap(eliminated: {'s2'})));
    expect(base, isNot(snap(eliminated: {})));
  });
}
