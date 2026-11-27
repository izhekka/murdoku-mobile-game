import 'package:murdoku/domain/models.dart';

Pos _pos(int row, int col) => (row: row, col: col);

/// Pre-change legacy save shape (issue #93): a 6×6 case stamped with
/// `Difficulty.standard`, which means 7×7 at generation time since the
/// board-size change. `CaseData.gridSize` must keep reporting 6 so
/// in-progress saves render on their stored grid (rooms.length ==
/// suspects.length == stored size always holds for generator output).
///
/// Rooms tile one grid row each; suspects sit on the diagonal; the victim
/// stands in r0's free cell (0, 5) with s0 the murderer (same room); clues
/// are minimal but true of the solution.
final CaseData legacyStandardCase = _buildLegacyCase();

CaseData _buildLegacyCase() {
  final rooms = [
    for (var r = 0; r < 6; r++)
      RoomDef(
        id: 'r$r',
        name: 'Room $r',
        cells: [for (var c = 0; c < 6; c++) _pos(r, c)],
      ),
  ];
  final suspects = [
    for (var i = 0; i < 6; i++) Suspect(id: 's$i', name: 'G$i'),
  ];
  return CaseData(
    seed: 7,
    difficulty: Difficulty.standard,
    rooms: rooms,
    objects: const [],
    suspects: suspects,
    victimPos: _pos(0, 5),
    murdererId: 's0',
    clues: [
      InRoom(suspectId: 's1', roomId: 'r1', negated: false),
      InRoom(suspectId: 's2', roomId: 'r2', negated: false),
      InRoom(suspectId: 's3', roomId: 'r3', negated: false),
      InRoom(suspectId: 's4', roomId: 'r4', negated: false),
      InRoom(suspectId: 's5', roomId: 'r5', negated: false),
      SameRow(suspectId: 's0', targetId: victimId, negated: false),
    ],
    solution: {for (var i = 0; i < 6; i++) 's$i': _pos(i, i)},
  );
}
