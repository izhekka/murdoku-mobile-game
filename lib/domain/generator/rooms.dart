import 'dart:math';

import 'package:murdoku/domain/models.dart';

const _directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];

/// Grows G contiguous rooms on a G×G grid from random seed cells using
/// frontier expansion, always expanding the currently-smallest room so sizes
/// stay balanced. All randomness comes from [rng].
///
/// Room names are placeholders (equal to the room id); the case factory
/// assigns themed names.
List<RoomDef> generateRooms({required int gridSize, required Random rng}) {
  // Occasional rooms get enclosed too early and end up undersized; a
  // deterministic bounded retry (same rng stream) yields a balanced layout.
  for (var attempt = 0; attempt < 40; attempt++) {
    final rooms = _growOnce(gridSize: gridSize, rng: rng);
    final sizes = rooms.map((r) => r.cells.length).toList();
    final spread = sizes.reduce(max) - sizes.reduce(min);
    if (spread <= 3) return rooms;
  }
  return _growOnce(gridSize: gridSize, rng: rng);
}

List<RoomDef> _growOnce({required int gridSize, required Random rng}) {
  final g = gridSize;
  final allCells = _gridCells(g);

  // One distinct seed cell per room.
  final seeds = [...allCells]..shuffle(rng);
  final roomCells = List.generate(g, (i) => <Pos>[seeds[i]]);
  final owner = <Pos, int>{};
  for (var i = 0; i < g; i++) {
    owner[seeds[i]] = i;
  }

  _growRounds(roomCells, owner, rng);

  return [
    for (var i = 0; i < g; i++)
      RoomDef(id: 'r$i', name: 'r$i', cells: roomCells[i]),
  ];
}

/// Every cell of the G×G grid in row-major order.
List<Pos> _gridCells(int g) => [
  for (var row = 0; row < g; row++)
    for (var col = 0; col < g; col++) (row: row, col: col),
];

/// True when [p] is on the G×G grid.
bool _inGrid(Pos p, int g) =>
    p.row >= 0 && p.row < g && p.col >= 0 && p.col < g;

/// The unowned in-grid cells orthogonally adjacent to room [roomIndex].
Set<Pos> _frontier(
  int roomIndex,
  List<List<Pos>> roomCells,
  Map<Pos, int> owner,
) {
  final out = <Pos>{};
  for (final cell in roomCells[roomIndex]) {
    for (final (dr, dc) in _directions) {
      final next = (row: cell.row + dr, col: cell.col + dc);
      if (_inGrid(next, roomCells.length) && !owner.containsKey(next)) {
        out.add(next);
      }
    }
  }
  return out;
}

/// Tie-break comparator: smaller rooms first, pure-rng jitter between
/// equally-sized rooms.
int _roomOrderCompare(int a, int b, List<List<Pos>> roomCells, Random rng) =>
    roomCells[a].length != roomCells[b].length
    ? roomCells[a].length - roomCells[b].length
    : rng.nextInt(3) - 1;

/// Simultaneous round growth: every room expands one cell per round
/// (smallest first), which keeps sizes close and discourages enclosure.
/// The rng call order matches the original inline loop exactly (issue 35).
void _growRounds(List<List<Pos>> roomCells, Map<Pos, int> owner, Random rng) {
  final g = roomCells.length;
  var remaining = g * g - g;
  while (remaining > 0) {
    final order = List.generate(g, (i) => i)
      ..sort((a, b) => _roomOrderCompare(a, b, roomCells, rng));
    final grown = _growRound(order, roomCells, owner, remaining, rng);
    // A connected grid always leaves at least one room with a frontier while
    // unassigned cells remain, so each round makes progress.
    if (grown == 0) break;
    remaining -= grown;
  }
}

/// One growth round: attempts every room once while [budget] cells remain.
/// Returns the number of cells actually grown.
int _growRound(
  List<int> order,
  List<List<Pos>> roomCells,
  Map<Pos, int> owner,
  int budget,
  Random rng,
) {
  var grown = 0;
  for (final ri in order) {
    if (grown >= budget) break;
    final f = _frontier(ri, roomCells, owner).toList()..shuffle(rng);
    if (f.isEmpty) continue;
    final cell = f.first;
    owner[cell] = ri;
    roomCells[ri].add(cell);
    grown++;
  }
  return grown;
}
