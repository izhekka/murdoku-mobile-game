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
  final allCells = [
    for (var row = 0; row < g; row++)
      for (var col = 0; col < g; col++) (row: row, col: col),
  ];

  // One distinct seed cell per room.
  final seeds = [...allCells]..shuffle(rng);
  final roomCells = List.generate(g, (i) => <Pos>[seeds[i]]);
  final owner = <Pos, int>{};
  for (var i = 0; i < g; i++) {
    owner[seeds[i]] = i;
  }

  bool inGrid(Pos p) => p.row >= 0 && p.row < g && p.col >= 0 && p.col < g;

  Set<Pos> frontier(int roomIndex) {
    final out = <Pos>{};
    for (final cell in roomCells[roomIndex]) {
      for (final (dr, dc) in _directions) {
        final next = (row: cell.row + dr, col: cell.col + dc);
        if (inGrid(next) && !owner.containsKey(next)) out.add(next);
      }
    }
    return out;
  }

  // Simultaneous round growth: every room expands one cell per round
  // (smallest first), which keeps sizes close and discourages enclosure.
  var remaining = g * g - g;
  while (remaining > 0) {
    final order = List.generate(g, (i) => i)
      ..sort(
        (a, b) => roomCells[a].length != roomCells[b].length
            ? roomCells[a].length - roomCells[b].length
            : rng.nextInt(3) - 1,
      );
    var grew = false;
    for (final ri in order) {
      if (remaining == 0) break;
      final f = frontier(ri).toList()..shuffle(rng);
      if (f.isEmpty) continue;
      final cell = f.first;
      owner[cell] = ri;
      roomCells[ri].add(cell);
      remaining--;
      grew = true;
    }
    // A connected grid always leaves at least one room with a frontier while
    // unassigned cells remain, so each round makes progress.
    if (!grew) break;
  }

  return [
    for (var i = 0; i < g; i++)
      RoomDef(id: 'r$i', name: 'r$i', cells: roomCells[i]),
  ];
}
