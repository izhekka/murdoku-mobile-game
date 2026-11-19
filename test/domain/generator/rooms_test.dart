import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/rooms.dart';
import 'package:murdoku/domain/models.dart';

bool contiguous(RoomDef room) {
  final cells = room.cells.toSet();
  final start = room.cells.first;
  final visited = <Pos>{start};
  final queue = <Pos>[start];
  while (queue.isNotEmpty) {
    final cur = queue.removeAt(0);
    for (final d in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
      final next = (row: cur.row + d.$1, col: cur.col + d.$2);
      if (cells.contains(next) && !visited.contains(next)) {
        visited.add(next);
        queue.add(next);
      }
    }
  }
  return visited.length == cells.length;
}

void main() {
  test('generates G contiguous, balanced, fully covering rooms for 100 seeds',
      () {
    for (final g in [5, 6, 7]) {
      for (var seed = 1; seed <= 100; seed++) {
        final rooms = generateRooms(gridSize: g, rng: Random(seed));

        expect(rooms.length, g, reason: 'seed $seed g $g: room count');

        // Full coverage, no overlap, no empty rooms.
        final ownership = <Pos, String>{};
        for (final room in rooms) {
          expect(room.cells, isNotEmpty, reason: 'seed $seed g $g: empty room');
          for (final cell in room.cells) {
            expect(ownership.containsKey(cell), isFalse,
                reason: 'seed $seed g $g: cell $cell in two rooms');
            ownership[cell] = room.id;
          }
        }
        expect(ownership.length, g * g,
            reason: 'seed $seed g $g: coverage incomplete');

        // Orthogonal contiguity.
        for (final room in rooms) {
          expect(contiguous(room), isTrue,
              reason: 'seed $seed g $g: room ${room.id} not contiguous');
        }

        // Soft balance: max room size at most min + 3.
        final sizes = rooms.map((r) => r.cells.length).toList();
        expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(3),
            reason: 'seed $seed g $g: sizes $sizes unbalanced');

        // Unique room ids.
        expect(rooms.map((r) => r.id).toSet().length, g,
            reason: 'seed $seed g $g: duplicate room ids');
      }
    }
  });
}
