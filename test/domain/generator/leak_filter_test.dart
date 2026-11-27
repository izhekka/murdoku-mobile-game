import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Issue #93: the generator never ships a clue card that names the killer
/// or reads as a proximity accusation toward the victim. Exclusion rule
/// (owner-approved, re-scoped 2026-11-27):
/// 1. no positive `InRoom` naming the victim's room — including the
///    `_ensureCoverage` fallback (an uncovered murderer would get it);
/// 2. no positive `BesideObject` for an object standing in the victim's room
///    (only the murderer's own room equals the victim's room);
/// 3. no `SameCol(targetId: victimId)` in either polarity;
/// 4. no `Beside(targetId: victimId)` in either polarity.
///
/// Exonerating cards stay permitted: `InRoom(victim's room, negated: true)`
/// never names the killer. Permitted-ness is proven by PINNED seeds whose
/// shipped set actually contains one (the earlier count-based assertion
/// measured 0 exonerating cards among standard seeds 1-30 — the negated top
/// up picks 1-3 cards from a large negated pool, so occurrence counting over
/// a sweep is flaky and was replaced; see the pinned-seed test below).
void main() {
  test('no shipped card names the killer or targets the victim (100 seeds per difficulty, issue #93)', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 100; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final victimRoom = roomOf(c.rooms, c.victimPos)!;
        final victimRoomObjectIds = {
          for (final o in c.objects)
            if (roomOf(c.rooms, o.pos) == victimRoom) o.id,
        };
        for (final clue in c.clues) {
          final json = clue.toJson();
          final reason =
              '$difficulty seed $seed ships leak card: ${clue.toJson()}';
          // 1. positive InRoom naming the victim's room.
          if (clue is InRoom && !clue.negated) {
            expect(clue.roomId, isNot(victimRoom), reason: reason);
          }
          // 2. positive BesideObject for a victim's-room object.
          if (clue is BesideObject && !clue.negated) {
            expect(
              victimRoomObjectIds.contains(clue.objectId),
              isFalse,
              reason: reason,
            );
          }
          // 3./4. victim-target SameCol and Beside in both polarities.
          if (clue is SameCol || clue is Beside) {
            expect(json['targetId'], isNot(victimId), reason: reason);
          }
          // Defensive: victim-target cards must be exactly the permitted
          // kinds (SameRow positive/negated, DirectionClue positive/negated)
          // — never SameCol/Beside, never a positive victim's-room InRoom.
          if (json['targetId'] == victimId) {
            expect(
              clue,
              anyOf(isA<DirectionClue>(), isA<SameRow>()),
              reason: reason,
            );
          }
        }
      }
    }
  });

  test('pool carries none of the four excluded classes either (100 seeds per difficulty, issue #93)', () {
    // Pool-level witness (review round on #93): the leak rule lives at
    // the emit sites, so the rebuilt pool — what [_buildClueSet] fed into
    // the uniqueness machinery — must be as leak-free as the shipped set
    // the first test sweeps. The positive side is rng-independent (see
    // cluePoolFor's doc); the negated side is a capped shuffle-take from
    // the already-filtered negated list.
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 100; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final victimRoom = roomOf(c.rooms, c.victimPos)!;
        final victimRoomObjectIds = {
          for (final o in c.objects)
            if (roomOf(c.rooms, o.pos) == victimRoom) o.id,
        };
        for (final clue in cluePoolFor(c)) {
          final reason =
              '$difficulty seed $seed pool carries leak card: '
              '${clue.toJson()}';
          if (clue is InRoom && !clue.negated) {
            expect(clue.roomId, isNot(victimRoom), reason: reason);
          }
          if (clue is BesideObject && !clue.negated) {
            expect(
              victimRoomObjectIds.contains(clue.objectId),
              isFalse,
              reason: reason,
            );
          }
          if (clue is SameCol || clue is Beside) {
            expect(clue.toJson()['targetId'], isNot(victimId), reason: reason);
          }
        }
      }
    }
  });

  test(
    'coverage fallback never names the killer in any branch (issue #93)',
    () {
      // The _ensureCoverage orElse seam, pinned branch by branch (the orElse
      // never fires in generated cases because every suspect always holds a
      // pool candidate — see coverageFallbackClue's doc).
      Pos p(int row, int col) => (row: row, col: col);
      final rooms = [
        RoomDef(id: 'rv', name: 'Sitting', cells: [p(0, 0), p(0, 1), p(1, 0)]),
        RoomDef(id: 'rx', name: 'Other', cells: [p(1, 1)]),
      ];
      // Non-murderer: own-room InRoom stays the fallback shape.
      final plain = coverageFallbackClue('s0', p(1, 1), p(0, 1), 'rv', rooms);
      expect(plain, isA<InRoom>());
      expect((plain as InRoom).roomId, 'rx');
      expect(plain.negated, isFalse);
      // Murderer sharing the victim's row: SameRow(victim) positive.
      final sameRow = coverageFallbackClue('s1', p(0, 0), p(0, 1), 'rv', rooms);
      expect(
        sameRow,
        SameRow(suspectId: 's1', targetId: victimId, negated: false),
      );
      // Murderer strictly north of the victim: the north direction card.
      expect(
        coverageFallbackClue('s2', p(0, 0), p(1, 0), 'rv', rooms),
        DirectionClue(
          suspectId: 's2',
          targetId: victimId,
          direction: Direction.north,
          negated: false,
        ),
      );
      // Murderer strictly south: the south direction card.
      expect(
        coverageFallbackClue('s3', p(1, 0), p(0, 0), 'rv', rooms),
        DirectionClue(
          suspectId: 's3',
          targetId: victimId,
          direction: Direction.south,
          negated: false,
        ),
      );
    },
  );

  test('exonerating InRoom(victim room, negated) stays permitted — pinned seeds (issue #93)', () {
    // Pinned seeds chosen by sweep: each pair below is measured to SHIP an
    // exonerating card. Measured 2026-11-27 with a temporary probe script
    // sweeping standard seeds 1..120 and hard seeds 1..60 through
    // generateCase and filtering for InRoom(victim room, negated) in the
    // shipped set (occurrence-per-seed is rare — one of ~450 shuffled
    // negated candidates is a victim-room card — hence pins, not
    // counting). If a pin breaks, re-run that sweep to re-derive the seeds;
    // never re-pin from a leaked card: the sweep test above still guards
    // the exclusions. easy is absent by construction: its negated cap is 0,
    // so no negated card — exonerating or otherwise — can ship there.
    const pinnedExonerating = ['standard/80', 'hard/42', 'hard/47'];
    expect(pinnedExonerating, isNotEmpty);
    for (final pin in pinnedExonerating) {
      final parts = pin.split('/');
      final difficulty = DifficultyX.fromName(parts[0]);
      final seed = int.parse(parts[1]);
      final c = generateCase(difficulty: difficulty, seed: seed);
      final victimRoom = roomOf(c.rooms, c.victimPos)!;
      expect(
        c.clues.whereType<InRoom>().any(
          (cl) => cl.negated && cl.roomId == victimRoom,
        ),
        isTrue,
        reason:
            '$difficulty seed $seed must still ship an exonerating '
            'victim-room card (permits proof, issue #93)',
      );
    }
  });
}
