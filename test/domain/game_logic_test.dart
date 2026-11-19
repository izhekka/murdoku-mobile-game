import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/game_logic.dart';
import 'package:murdoku/domain/models.dart';

Pos p(int row, int col) => (row: row, col: col);

final CaseData caseData = CaseData(
  seed: 1,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(id: 'r0', name: 'Hall', cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)]),
    RoomDef(id: 'r1', name: 'Library', cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)]),
    RoomDef(id: 'r2', name: 'Kitchen', cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)]),
    RoomDef(id: 'r3', name: 'Cellar', cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)]),
    RoomDef(id: 'r4', name: 'Study', cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)]),
  ],
  objects: [],
  suspects: List.generate(5, (i) => Suspect(id: 's$i', name: 'Guest $i')),
  victimPos: p(2, 2),
  murdererId: 's2',
  clues: [],
  solution: {
    's0': p(0, 0),
    's1': p(1, 4),
    's2': p(2, 1),
    's3': p(3, 3),
    's4': p(4, 2),
  },
);

void main() {
  test('canPlace rejects occupied and victim cells, accepts free cells', () {
    final placed = {'s0': p(0, 0)};
    expect(canPlace(caseData, placed, 's1', p(1, 4)), isTrue);
    expect(canPlace(caseData, placed, 's1', p(0, 0)), isFalse, reason: 'occupied');
    expect(canPlace(caseData, placed, 's1', p(2, 2)), isFalse, reason: 'victim cell');
  });

  test('correctCount counts only exact solution matches', () {
    expect(correctCount(caseData, {}), 0);
    expect(correctCount(caseData, {'s0': p(0, 0)}), 1);
    expect(correctCount(caseData, {'s0': p(1, 4)}), 0, reason: 'wrong cell');
    final all = Map.of(caseData.solution);
    expect(correctCount(caseData, all), 5);
  });

  test('boardSolved is strict', () {
    final all = Map.of(caseData.solution);
    expect(boardSolved(caseData, all), isTrue);
    final partial = {'s0': p(0, 0)};
    expect(boardSolved(caseData, partial), isFalse);
    final wrong = Map.of(caseData.solution)..['s2'] = p(2, 0);
    expect(boardSolved(caseData, wrong), isFalse);
    expect(boardSolved(caseData, {}), isFalse);
  });
}
