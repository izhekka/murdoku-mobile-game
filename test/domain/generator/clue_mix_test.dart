import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

/// Issue #111 clue-mix acceptance sweep: 100 seeds per difficulty must ship
/// at most two direction cards of any polarity, only solution-true cards,
/// exactly one solution, every suspect covered, no positive item card for a
/// victim's-room item, no negated direction card — and each new object-cell
/// kind must appear at least once in every difficulty's sweep.
void main() {
  for (final difficulty in Difficulty.values) {
    test('clue mix obeys the direction cap and the card rules '
        '($difficulty, issue #111)', () {
      final seenKinds = <String>{};
      for (var seed = 1; seed <= 100; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final victimRoom = roomOf(c.rooms, c.victimPos)!;
        final victimRoomObjectIds = {
          for (final o in c.objects)
            if (roomOf(c.rooms, o.pos) == victimRoom) o.id,
        };
        var directionCards = 0;
        for (final clue in c.clues) {
          seenKinds.add(clue.typeName);
          final reason =
              '$difficulty seed $seed ships bad card: ${clue.toJson()}';
          if (clue is DirectionClue) {
            directionCards++;
            expect(clue.negated, isFalse, reason: reason);
          }
          // Every shipped card is true of the solution.
          expect(
            evaluateClue(
              clue,
              placement: c.solution,
              victimPos: c.victimPos,
              rooms: c.rooms,
              objects: c.objects,
            ),
            isTrue,
            reason: reason,
          );
          // No positive item card for an item in the victim's room.
          final objectId = switch (clue) {
            BesideObject(:final objectId) => objectId,
            OnObject(:final objectId) => objectId,
            NearObject(:final objectId) => objectId,
            SoleNearObject(:final objectId) => objectId,
            _ => null,
          };
          if (objectId != null && !clue.negated) {
            expect(
              victimRoomObjectIds.contains(objectId),
              isFalse,
              reason: reason,
            );
          }
        }
        expect(
          directionCards,
          lessThanOrEqualTo(2),
          reason:
              '$difficulty seed $seed ships $directionCards direction cards',
        );
        // Exactly one solution.
        expect(
          countSolutions(
            gridSize: c.gridSize,
            rooms: c.rooms,
            clues: c.clues,
            suspectIds: c.suspects.map((s) => s.id).toList(),
            victimPos: c.victimPos,
            objects: c.objects,
          ),
          1,
          reason: '$difficulty seed $seed has more than one solution',
        );
        // Every suspect holds at least one card.
        final covered = c.clues.map((cl) => cl.suspectId).toSet();
        for (final s in c.suspects) {
          expect(
            covered.contains(s.id),
            isTrue,
            reason: '$difficulty seed $seed: ${s.id} has no card',
          );
        }
      }
      expect(
        seenKinds,
        containsAll(['onObject', 'nearObject', 'soleNearObject']),
        reason:
            '$difficulty sweep never shipped all object-cell kinds; '
            'seen: $seenKinds',
      );
    });
  }
}
