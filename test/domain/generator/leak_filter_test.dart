import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Issue #93: the generator never ships a clue card that names the killer
/// or reads as a proximity accusation toward the victim. Exclusion rule
/// (owner-approved, re-scoped 2026-11-27):
/// 1. no positive `InRoom` naming the victim's room (issue 111: a suspect
///    with no pool candidate fails the attempt — there is no fallback card);
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
          // 2. positive item card for a victim's-room object — BesideObject
          //    and the three object-cell kinds alike (issue #111).
          if (!clue.negated &&
              (clue is BesideObject ||
                  clue is OnObject ||
                  clue is NearObject ||
                  clue is SoleNearObject)) {
            expect(
              victimRoomObjectIds.contains(json['objectId']),
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
          if (!clue.negated &&
              (clue is BesideObject ||
                  clue is OnObject ||
                  clue is NearObject ||
                  clue is SoleNearObject)) {
            expect(
              victimRoomObjectIds.contains(clue.toJson()['objectId']),
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

  test('coverage: an uncovered suspect takes the first pool candidate; with '
      'no pool candidate the attempt fails (issue #111)', () {
    // The ensureCoverage seam, pinned branch by branch: in generated cases
    // only the murderer can lack a pool candidate (the direction cap removed
    // his guaranteed fallback), so the null return is the drop signal.
    final suspects = [
      const Suspect(id: 's0', name: 'A'),
      const Suspect(id: 's1', name: 'B'),
    ];
    final pool = <Clue>[
      const InRoom(suspectId: 's1', roomId: 'r0', negated: false),
      const SameRow(suspectId: 's0', targetId: victimId, negated: false),
      const SameRow(suspectId: 's0', targetId: 's1', negated: false),
    ];
    // An already-covered suspect keeps his card and gains no duplicate.
    final pruned = <Clue>[
      const InRoom(suspectId: 's1', roomId: 'r0', negated: false),
    ];
    final covered = ensureCoverage(pruned, pool, suspects);
    expect(covered, isNotNull);
    expect(
      covered!.where((cl) => cl.suspectId == 's1').length,
      1,
      reason: 'covered suspects are skipped',
    );
    // The uncovered suspect takes the FIRST pool candidate naming him.
    expect(
      covered.where((cl) => cl.suspectId == 's0').single,
      const SameRow(suspectId: 's0', targetId: victimId, negated: false),
    );
    // A suspect with no pool candidate at all: the attempt is dropped.
    final stranger = [
      const Suspect(id: 's0', name: 'A'),
      const Suspect(id: 's2', name: 'C'),
    ];
    expect(ensureCoverage(const [], pool, stranger), isNull);
  });

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
    // Re-measured 2026-11-28 for issue #111 (the negated pool no longer
    // carries direction candidates, so the negated top-up draws from a
    // smaller pool and different seeds ship the card): the sweep now
    // widens to standard 1..200 and hard 1..70; standard seeds 1..158 ship
    // none.
    const pinnedExonerating = ['standard/159', 'hard/13', 'hard/35'];
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
