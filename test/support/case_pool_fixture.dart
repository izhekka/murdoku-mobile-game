import 'package:murdoku/domain/models.dart';

Pos _pos(int row, int col) => (row: row, col: col);

/// Compact deterministic pool fixture (issue 108 tests): a 5x5 case for
/// [difficulty] whose [seed] makes distinct cases distinct (`==` compares
/// the seed). Shape mirrors the storage test fixture; pool tests exercise
/// transport and controller logic, not generation.
CaseData poolCase(Difficulty difficulty, int seed) {
  final rooms = [
    for (var r = 0; r < 5; r++)
      RoomDef(
        id: 'r$r',
        name: 'Room $r',
        cells: [for (var c = 0; c < 5; c++) _pos(r, c)],
      ),
  ];
  return CaseData(
    seed: seed,
    difficulty: difficulty,
    rooms: rooms,
    objects: const [],
    suspects: [for (var i = 0; i < 5; i++) Suspect(id: 's$i', name: 'G$i')],
    victimPos: _pos(0, 4),
    murdererId: 's0',
    clues: [
      InRoom(suspectId: 's1', roomId: 'r1', negated: false),
      InRoom(suspectId: 's2', roomId: 'r2', negated: false),
      InRoom(suspectId: 's3', roomId: 'r3', negated: false),
      InRoom(suspectId: 's4', roomId: 'r4', negated: false),
    ],
    solution: {for (var i = 0; i < 5; i++) 's$i': _pos(i, i)},
  );
}
