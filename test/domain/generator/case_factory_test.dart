import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

void main() {
  test(
      'property: 150 seeded cases are structurally valid, clue-true, unique, deterministic',
      () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final g = difficulty.gridSize;

        // 1. structure
        expect(c.rooms.length, g, reason: 'seed $seed/${difficulty.name}');
        expect(c.suspects.length, g);
        expect(c.objects.length, difficulty.objectCount,
            reason: 'seed $seed: furniture count');
        expect(c.objects.where((o) => o.occupiable).length,
            difficulty.occupiableCount,
            reason: 'seed $seed: occupiable count');
        // No furniture stacking; victim cell always bare.
        expect(c.objects.map((o) => o.pos).toSet().length, c.objects.length,
            reason: 'seed $seed: one item per cell');
        for (final o in c.objects) {
          expect(o.pos, isNot(c.victimPos),
              reason: 'seed $seed: victim cell bare');
          expect(kindOccupiable(o.kind), o.occupiable,
              reason: 'seed $seed: kind/occupiable consistency');
        }
        for (final o in c.objects.where((o) => !o.occupiable)) {
          expect(c.solution.values.contains(o.pos), isFalse,
              reason: 'seed $seed: blocking furniture never under a guest');
        }
        expect(c.solution.values.contains(c.victimPos), isFalse,
            reason: 'seed $seed: victim cell must be empty in solution');
        expect(roomOf(c.rooms, c.victimPos), isNotNull,
            reason: 'seed $seed: victim in a room');

        // suspect ids are s0..s(G-1); room ids r0..r(G-1)
        expect(c.suspects.map((s) => s.id).toList(),
            List.generate(g, (i) => 's$i'));
        expect(c.rooms.map((r) => r.id).toSet(), Set.from(List.generate(g, (i) => 'r$i')));

        // 2. solution validity: one guest per row / col / room
        expect(c.solution.values.map((p) => p.row).toSet().length, g);
        expect(c.solution.values.map((p) => p.col).toSet().length, g);
        final roomIds = c.solution.values.map((p) => roomOf(c.rooms, p)!).toSet();
        expect(roomIds.length, g,
            reason: 'seed $seed: one guest per room');

        // 3. all clues true on the solution (throws on malformed ids)
        for (final clue in c.clues) {
          expect(
            evaluateClue(
              clue,
              placement: c.solution,
              victimPos: c.victimPos,
              rooms: c.rooms,
              objects: c.objects,
            ),
            isTrue,
            reason: 'seed $seed: clue not true: ${clue.toJson()}',
          );
        }

        // 4. uniqueness
        expect(
          countSolutions(
            gridSize: g,
            rooms: c.rooms,
            clues: c.clues,
            suspectIds: c.suspects.map((s) => s.id).toList(),
            victimPos: c.victimPos,
            objects: c.objects,
          ),
          1,
          reason: 'seed $seed: puzzle not unique',
        );
        expect(
          firstSolution(
            gridSize: g,
            rooms: c.rooms,
            clues: c.clues,
            suspectIds: c.suspects.map((s) => s.id).toList(),
            victimPos: c.victimPos,
            objects: c.objects,
          ),
          equals(c.solution),
        );

        // 5. murderer shares the victim's room
        final victimRoom = roomOf(c.rooms, c.victimPos);
        final murdererRoom = roomOf(c.rooms, c.solution[c.murdererId]!);
        expect(murdererRoom, victimRoom,
            reason: 'seed $seed: murderer not with victim');

        // 6. clue window
        expect(c.clues.length, greaterThanOrEqualTo(difficulty.minClues),
            reason: 'seed $seed: too few clues (${c.clues.length})');
        expect(c.clues.length, lessThanOrEqualTo(difficulty.maxClues),
            reason: 'seed $seed: too many clues (${c.clues.length})');

        // determinism (spot-check: same seed -> identical json)
        final again = generateCase(difficulty: difficulty, seed: seed);
        expect(again.toJson(), equals(c.toJson()),
            reason: 'seed $seed: generation not deterministic');
      }
    }
  });

  test('different seeds produce different cases (sanity)', () {
    // Under seed retry, case.seed is the successful seed, not the requested
    // one — so assert on determinism and cross-seed difference instead.
    final a = generateCase(difficulty: Difficulty.easy, seed: 1);
    final a2 = generateCase(difficulty: Difficulty.easy, seed: 1);
    expect(a2.toJson(), equals(a.toJson()));
    // Seed ranges 1..40 and 1000..1039 are disjoint retries, so the results
    // must differ.
    final c = generateCase(difficulty: Difficulty.easy, seed: 1000);
    expect(a.toJson() == c.toJson(), isFalse);
  });
}
