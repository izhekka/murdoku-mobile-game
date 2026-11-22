import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
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

        // 1b. poolIndex: names must resolve through the localized pools
        // (UX-1). -1 would render English names in the ru UI.
        expect(
          c.suspects.every((s) => s.poolIndex >= 0 && s.poolIndex < 16),
          isTrue,
          reason:
              'seed $seed/${difficulty.name}: suspect poolIndex out of pool range',
        );
        expect(
          c.rooms.every((r) => r.poolIndex >= 0 && r.poolIndex < 16),
          isTrue,
          reason:
              'seed $seed/${difficulty.name}: room poolIndex out of pool range',
        );
        // name and poolIndex must agree: poolIndex points at the pool slot
        // holding this entry's name, so en and ru show the same identity.
        expect(
          c.suspects.every((s) => suspectNamePool[s.poolIndex] == s.name),
          isTrue,
          reason:
              'seed $seed/${difficulty.name}: suspect name/poolIndex mismatch',
        );
        expect(
          c.rooms.every((r) => roomNamePool[r.poolIndex] == r.name),
          isTrue,
          reason:
              'seed $seed/${difficulty.name}: room name/poolIndex mismatch',
        );

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

        // 5b. every suspect has at least one clue (no empty cards)
        final suspectsWithClues = c.clues.map((cl) => cl.suspectId).toSet();
        for (final s in c.suspects) {
          expect(suspectsWithClues.contains(s.id), isTrue,
              reason: 'seed $seed: suspect ${s.id} has no clue');
        }

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

  test('property: every generated BesideObject clue has the guest in the item room (UX-8)', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        for (final clue in c.clues.whereType<BesideObject>()) {
          final obj = c.objects.firstWhere((o) => o.id == clue.objectId);
          final guestRoom = roomOf(c.rooms, c.solution[clue.suspectId]!);
          if (clue.negated) {
            // Issue #10: a negated item clue means the guest is NOT in the
            // item's room — the mirror of the UX-8 property.
            expect(guestRoom, isNot(roomOf(c.rooms, obj.pos)),
                reason: 'seed $seed/${difficulty.name}: '
                    'negated item clue must be false of the room: ${clue.toJson()}');
          } else {
            expect(guestRoom, roomOf(c.rooms, obj.pos),
                reason: 'seed $seed/${difficulty.name}: '
                    'guest not in item room: ${clue.toJson()}');
          }
        }
      }
    }
  });

  test('property: generation uses the full same-room relation for item clues (UX-8)', () {
    // The candidate pool must propose same-room candidates, not only
    // Manhattan-1 ones: across 150 cases at least one item clue pairs a
    // guest with an item in its room but NOT adjacent to it (ADR 0004:
    // generation changes together with evaluation).
    int nonAdjacent = 0;
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        for (final clue in
            c.clues.whereType<BesideObject>().where((cl) => !cl.negated)) {
          final guest = c.solution[clue.suspectId]!;
          final obj = c.objects.firstWhere((o) => o.id == clue.objectId);
          final d = (guest.row - obj.pos.row).abs() + (guest.col - obj.pos.col).abs();
          if (d != 1) nonAdjacent++;
        }
      }
    }
    expect(nonAdjacent, greaterThan(0),
        reason: 'same-room item clues never appear beyond Manhattan-1');
  });

  test('property: negated clues obey difficulty caps and are true of the solution (#10)', () {
    for (final difficulty in Difficulty.values) {
      final atCap = <int>[];
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final negated = c.clues.where((cl) => cl.negated).toList();
        // Cap: easy 0, standard ≤1, hard ≤3.
        expect(negated.length, lessThanOrEqualTo(difficulty.maxNegatedClues),
            reason: 'seed $seed/${difficulty.name}: negated cap exceeded');
        if (difficulty == Difficulty.easy) {
          expect(negated, isEmpty, reason: 'seed $seed: easy must have none');
        }
        // A card clue is always a true statement — negated included.
        for (final clue in negated) {
          expect(
            evaluateClue(
              clue,
              placement: c.solution,
              victimPos: c.victimPos,
              rooms: c.rooms,
              objects: c.objects,
            ),
            isTrue,
            reason: 'seed $seed: negated clue not true: ${clue.toJson()}',
          );
        }
        if (negated.length == difficulty.maxNegatedClues) atCap.add(seed);
      }
      // Non-vacuous: the caps are actually reached on standard/hard.
      if (difficulty != Difficulty.easy) {
        expect(atCap.length, greaterThanOrEqualTo(40),
            reason:
                '${difficulty.name}: cap reached in only ${atCap.length}/50 cases');
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

  test('generated cases render Russian names from the pools (UX-1)', () {
    final c = generateCase(difficulty: Difficulty.easy, seed: 1);
    final names = NameForms.forLocale('ru', c);
    for (final r in c.rooms) {
      expect(names.roomPrep(r.id), ruRoomForms[r.poolIndex].$2,
          reason: 'room ${r.id} (${r.name}) prep phrase must come from the pool');
      expect(names.roomPrep(r.id), isNot('в ${r.name}'),
          reason:
              'room ${r.id} (${r.name}) must not fall back to the stored name');
    }
    for (final s in c.suspects) {
      expect(names.nom(s.id), ruSuspectForms[s.poolIndex].nom,
          reason: 'suspect ${s.id} (${s.name}) nom must come from the pool');
      expect(names.nom(s.id), isNot(s.name),
          reason:
              'suspect ${s.id} (${s.name}) must not fall back to the stored name');
    }
  });

  test('generated rooms draw from the whole pool, not constants (UX-1)', () {
    // The plan pinned seed 1 easy to poolIndex 1, but the shipped name
    // permutation for that seed is [10,15,5,9,7] — distribution is proven
    // instead: distinct slots within a case, wide coverage across cases.
    // Same-room item clues (UX-8) made uniqueness retries frequent, so
    // several requested seeds can return the same successful seed; sample
    // until 5 DISTINCT cases (bounded scan) rather than 5 requested seeds.
    final seen = <int>{};
    final distinctCases = <int>{};
    for (var seed = 1; seed <= 60 && distinctCases.length < 5; seed++) {
      final c = generateCase(difficulty: Difficulty.easy, seed: seed);
      if (!distinctCases.add(c.seed)) continue;
      final idx = c.rooms.map((r) => r.poolIndex).toSet();
      expect(idx.length, c.rooms.length,
          reason: 'case ${c.seed}: room poolIndex values repeat');
      seen.addAll(idx);
    }
    expect(distinctCases.length, 5,
        reason: 'bounded scan should find 5 distinct easy cases');
    expect(seen.length, greaterThanOrEqualTo(10),
        reason: '5 cases only cover ${seen.length} of 16 pool slots');
  });
}
