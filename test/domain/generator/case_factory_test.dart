import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/clue_eval.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

void main() {
  test('property: 150 seeded cases are structurally valid, clue-true, unique, deterministic', () {
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final g = difficulty.gridSize;

        // 1. structure
        expect(c.rooms.length, g, reason: 'seed $seed/${difficulty.name}');
        expect(c.suspects.length, g);
        expect(
          c.objects.length,
          difficulty.objectCount,
          reason: 'seed $seed: furniture count',
        );
        expect(
          c.objects.where((o) => o.occupiable).length,
          difficulty.occupiableCount,
          reason: 'seed $seed: occupiable count',
        );
        // No furniture stacking; victim cell always bare.
        expect(
          c.objects.map((o) => o.pos).toSet().length,
          c.objects.length,
          reason: 'seed $seed: one item per cell',
        );
        for (final o in c.objects) {
          expect(
            o.pos,
            isNot(c.victimPos),
            reason: 'seed $seed: victim cell bare',
          );
          expect(
            kindOccupiable(o.kind),
            o.occupiable,
            reason: 'seed $seed: kind/occupiable consistency',
          );
        }
        for (final o in c.objects.where((o) => !o.occupiable)) {
          expect(
            c.solution.values.contains(o.pos),
            isFalse,
            reason: 'seed $seed: blocking furniture never under a guest',
          );
        }
        expect(
          c.solution.values.contains(c.victimPos),
          isFalse,
          reason: 'seed $seed: victim cell must be empty in solution',
        );
        expect(
          roomOf(c.rooms, c.victimPos),
          isNotNull,
          reason: 'seed $seed: victim in a room',
        );

        // suspect ids are s0..s(G-1); room ids r0..r(G-1)
        expect(
          c.suspects.map((s) => s.id).toList(),
          List.generate(g, (i) => 's$i'),
        );
        expect(
          c.rooms.map((r) => r.id).toSet(),
          Set.from(List.generate(g, (i) => 'r$i')),
        );

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
          reason: 'seed $seed/${difficulty.name}: room name/poolIndex mismatch',
        );

        // 2. solution validity: one guest per row / col / room
        expect(c.solution.values.map((p) => p.row).toSet().length, g);
        expect(c.solution.values.map((p) => p.col).toSet().length, g);
        final roomIds = c.solution.values
            .map((p) => roomOf(c.rooms, p)!)
            .toSet();
        expect(roomIds.length, g, reason: 'seed $seed: one guest per room');

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
        expect(
          murdererRoom,
          victimRoom,
          reason: 'seed $seed: murderer not with victim',
        );

        // 5b. every suspect has at least one clue (no empty cards)
        final suspectsWithClues = c.clues.map((cl) => cl.suspectId).toSet();
        for (final s in c.suspects) {
          expect(
            suspectsWithClues.contains(s.id),
            isTrue,
            reason: 'seed $seed: suspect ${s.id} has no clue',
          );
        }

        // 6. clue window
        expect(
          c.clues.length,
          greaterThanOrEqualTo(difficulty.minClues),
          reason: 'seed $seed: too few clues (${c.clues.length})',
        );
        expect(
          c.clues.length,
          lessThanOrEqualTo(difficulty.maxClues),
          reason: 'seed $seed: too many clues (${c.clues.length})',
        );

        // determinism (spot-check: same seed -> identical json)
        final again = generateCase(difficulty: difficulty, seed: seed);
        expect(
          again.toJson(),
          equals(c.toJson()),
          reason: 'seed $seed: generation not deterministic',
        );
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
            expect(
              guestRoom,
              isNot(roomOf(c.rooms, obj.pos)),
              reason:
                  'seed $seed/${difficulty.name}: '
                  'negated item clue must be false of the room: ${clue.toJson()}',
            );
          } else {
            expect(
              guestRoom,
              roomOf(c.rooms, obj.pos),
              reason:
                  'seed $seed/${difficulty.name}: '
                  'guest not in item room: ${clue.toJson()}',
            );
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
        for (final clue in c.clues.whereType<BesideObject>().where(
          (cl) => !cl.negated,
        )) {
          final guest = c.solution[clue.suspectId]!;
          final obj = c.objects.firstWhere((o) => o.id == clue.objectId);
          final d =
              (guest.row - obj.pos.row).abs() + (guest.col - obj.pos.col).abs();
          if (d != 1) nonAdjacent++;
        }
      }
    }
    expect(
      nonAdjacent,
      greaterThan(0),
      reason: 'same-room item clues never appear beyond Manhattan-1',
    );
  });

  test('property: negated clues obey difficulty caps and are true of the solution (#10)', () {
    for (final difficulty in Difficulty.values) {
      final atCap = <int>[];
      for (var seed = 1; seed <= 50; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final negated = c.clues.where((cl) => cl.negated).toList();
        // Cap: easy 0, standard ≤1, hard ≤3.
        expect(
          negated.length,
          lessThanOrEqualTo(difficulty.maxNegatedClues),
          reason: 'seed $seed/${difficulty.name}: negated cap exceeded',
        );
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
      // Issue #93 interim measurement: the wider take-all pool minimizes
      // later (13-16 clue sets), so fewer hard cases have room for all 3
      // negated cards before the maxClues window — measured 33/50
      // (2026-11-27); the threshold keeps headroom while proving the cap
      // is reached regularly.
      if (difficulty != Difficulty.easy) {
        expect(
          atCap.length,
          greaterThanOrEqualTo(25),
          reason:
              '${difficulty.name}: cap reached in only ${atCap.length}/50 cases',
        );
      }
    }
  });

  test('different seeds produce different cases (sanity)', () {
    // The stored case.seed is the first successful derived attempt, not
    // the requested one (issue 61) — so assert on determinism and
    // cross-seed difference instead.
    final a = generateCase(difficulty: Difficulty.easy, seed: 1);
    final a2 = generateCase(difficulty: Difficulty.easy, seed: 1);
    expect(a2.toJson(), equals(a.toJson()));
    // The derived attempt families of requested seeds 1 and 1000 are
    // decorrelated, so the results must differ.
    final c = generateCase(difficulty: Difficulty.easy, seed: 1000);
    expect(a.toJson() == c.toJson(), isFalse);
  });

  test('generated cases render Russian names from the pools (UX-1)', () {
    final c = generateCase(difficulty: Difficulty.easy, seed: 1);
    final names = NameForms.forLocale('ru', c);
    for (final r in c.rooms) {
      expect(
        names.roomPrep(r.id),
        ruRoomForms[r.poolIndex].$2,
        reason: 'room ${r.id} (${r.name}) prep phrase must come from the pool',
      );
      expect(
        names.roomPrep(r.id),
        isNot('в ${r.name}'),
        reason:
            'room ${r.id} (${r.name}) must not fall back to the stored name',
      );
    }
    for (final s in c.suspects) {
      expect(
        names.nom(s.id),
        ruSuspectForms[s.poolIndex].nom,
        reason: 'suspect ${s.id} (${s.name}) nom must come from the pool',
      );
      expect(
        names.nom(s.id),
        isNot(s.name),
        reason:
            'suspect ${s.id} (${s.name}) must not fall back to the stored name',
      );
    }
  });

  test('generated rooms draw from the whole pool, not constants (UX-1)', () {
    // Distribution is proven, not a specific seed's permutation: distinct
    // slots within a case, wide coverage across cases. (The plan pinned
    // seed 1 easy to poolIndex 1; the shipped permutation for that seed
    // changed again with the issue-61 attempt-seed remap, so no single
    // permutation is named here.) Requested seeds map to distinct stored
    // seeds since the remap, so the scan finds five distinct cases among
    // the first seeds — the bounded scan stays as a guard against any
    // future mapping change.
    final seen = <int>{};
    final distinctCases = <int>{};
    for (var seed = 1; seed <= 60 && distinctCases.length < 5; seed++) {
      final c = generateCase(difficulty: Difficulty.easy, seed: seed);
      if (!distinctCases.add(c.seed)) continue;
      final idx = c.rooms.map((r) => r.poolIndex).toSet();
      expect(
        idx.length,
        c.rooms.length,
        reason: 'case ${c.seed}: room poolIndex values repeat',
      );
      seen.addAll(idx);
    }
    expect(
      distinctCases.length,
      5,
      reason: 'bounded scan should find 5 distinct easy cases',
    );
    expect(
      seen.length,
      greaterThanOrEqualTo(10),
      reason: '5 cases only cover ${seen.length} of 16 pool slots',
    );
  });

  test(
    'interim: former #45 exhaust corridor hard/111 generates in window 0',
    () {
      // Issue #93 interim configuration: the take-all per-type pool dissolved
      // the historical budget-exhaustion corridors — seed 111, which exhausted
      // [generateCase]'s whole widened budget under the pre-#93 cap-10 pool
      // (issue 45 seams, re-measured 2026-11-24), now generates on the first
      // attempt (stored seed re-measured 2026-11-28 for issue #111's pool
      // change: 2074270045).
      // [generateCaseWithRecovery] therefore resolves it in window 0, and a
      // recovered start equals bare generation byte-for-byte.
      final bare = generateCase(difficulty: Difficulty.hard, seed: 111);
      expect(bare.seed, 2074270045);
      expect(
        bare.clues.length,
        inInclusiveRange(Difficulty.hard.minClues, Difficulty.hard.maxClues),
      );
      final recovered = generateCaseWithRecovery(
        difficulty: Difficulty.hard,
        seed: 111,
      );
      expect(
        recovered.toJson(),
        bare.toJson(),
        reason: 'window 0 succeeded, so recovery returns the bare case',
      );
    },
  );

  test(
    'recovery: same requested seed reproduces the same recovered case (#45)',
    () {
      // Determinism of the recovery path (issue 45): the same requested seed
      // restarts the same attempt-seed windows, so two recoveries agree.
      final a = generateCaseWithRecovery(
        difficulty: Difficulty.hard,
        seed: 375,
      );
      final b = generateCaseWithRecovery(
        difficulty: Difficulty.hard,
        seed: 375,
      );
      expect(b.toJson(), equals(a.toJson()));
      // The former multi-window corridor seed 375 (issue 45, measured
      // 2026-11-24: exhausts windows 0+1, recovers in window 2) also
      // generates directly (stored seed re-measured 2026-11-28 for issue
      // #111's pool change: 1840162272) — the stride machinery stands
      // ready but is not needed.
      expect(a.seed, 1840162272);
    },
  );
}
