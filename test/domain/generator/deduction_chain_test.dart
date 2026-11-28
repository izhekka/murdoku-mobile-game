import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/deducer.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

/// Issue #106: every generated case must be verified solvable by a human
/// chain of deductions. 100-seed sweep per difficulty, mirroring
/// leak_filter_test.dart: the shipped clue set fully solves under the
/// difficulty's tier, the trace places all guests on the stored solution,
/// uniqueness still holds (soundness cross-check), easy solves tier-1-only,
/// and the unchanged difficulty knobs are respected.
void main() {
  test('every generated case solves by a full deduction chain (100 seeds per difficulty, issue #106)', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 100; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final g = difficulty.gridSize;
        final ids = c.suspects.map((s) => s.id).toList();
        final reason = '$difficulty seed $seed';

        // 1. chain found: the shipped set solves under the difficulty tier.
        final trace = Deducer(
          gridSize: g,
          rooms: c.rooms,
          clues: c.clues,
          suspectIds: ids,
          victimPos: c.victimPos,
          objects: c.objects,
          tier: deduceTierFor(difficulty),
        ).solve();
        expect(trace, isNotNull, reason: '$reason: no deduction chain');

        // 2. trace complete and equal to the stored solution (soundness).
        final placed = {for (final step in trace!) step.guestId: step.cell};
        expect(placed.length, g, reason: '$reason: incomplete trace');
        expect(placed, c.solution, reason: '$reason: trace ≠ solution');

        // 3. uniqueness cross-check on the shipped set.
        expect(
          countSolutions(
            gridSize: g,
            rooms: c.rooms,
            clues: c.clues,
            suspectIds: ids,
            victimPos: c.victimPos,
            objects: c.objects,
          ),
          1,
          reason: '$reason: shipped set not unique',
        );

        // 4. easy additionally solves without the uniqueness probes.
        if (difficulty == Difficulty.easy) {
          final tier1 = Deducer(
            gridSize: g,
            rooms: c.rooms,
            clues: c.clues,
            suspectIds: ids,
            victimPos: c.victimPos,
            objects: c.objects,
            tier: DeduceTier.singles,
          ).solve();
          expect(tier1, isNotNull, reason: '$reason: easy not tier-1-solvable');
        }

        // 5. unchanged knobs: clue window (attempts may widen max by up to
        // +3), negated cap, per-suspect coverage.
        expect(
          c.clues.length,
          inInclusiveRange(difficulty.minClues, difficulty.maxClues + 3),
          reason: '$reason: clue count ${c.clues.length} out of window',
        );
        expect(
          c.clues.where((cl) => cl.negated).length,
          lessThanOrEqualTo(difficulty.maxNegatedClues),
          reason: '$reason: negated cap exceeded',
        );
        final covered = c.clues.map((cl) => cl.suspectId).toSet();
        for (final s in c.suspects) {
          expect(
            covered.contains(s.id),
            isTrue,
            reason: '$reason: suspect ${s.id} has no clue',
          );
        }
      }
    }
  });

  test('ensureChainSolvable: passes a shipped set, throws on a dead set', () {
    final c = generateCase(difficulty: Difficulty.easy, seed: 1);
    final ids = c.suspects.map((s) => s.id).toList();
    expect(
      () => ensureChainSolvable(
        g: c.gridSize,
        rooms: c.rooms,
        clues: c.clues,
        ids: ids,
        victimPos: c.victimPos,
        objects: c.objects,
        tier: deduceTierFor(Difficulty.easy),
      ),
      returnsNormally,
    );
    // Two exclusive room pins for s0 — no chain can ever place it.
    final dead = [
      InRoom(suspectId: 's0', roomId: c.rooms.first.id, negated: false),
      InRoom(suspectId: 's0', roomId: c.rooms.last.id, negated: false),
    ];
    expect(
      () => ensureChainSolvable(
        g: c.gridSize,
        rooms: c.rooms,
        clues: dead,
        ids: ids,
        victimPos: c.victimPos,
        objects: c.objects,
        tier: deduceTierFor(Difficulty.easy),
      ),
      throwsStateError,
    );
  });
}
