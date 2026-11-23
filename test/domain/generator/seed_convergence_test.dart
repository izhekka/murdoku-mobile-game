import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Pins the deliberate retry-convergence behavior of [generateCase]
/// (issue 46): the loop returns the first successful attempt seed at or
/// after the requested one, so every requested seed inside one failure
/// basin gets the same case — nearby seeds return identical puzzles.
///
/// The choice for issue 46 was to document + pin this (see
/// `docs/code-guidelines.md` §13): re-mapping attempt seeds (a wider
/// stride, or hashing the seed per attempt) would drift the pinned
/// golden digests in `golden_digest_test.dart`, which include retry-path
/// seeds (easy/1 → attempt 5, easy/11 → 12, hard/1 → 6, standard/1 → 5)
/// and are frozen by the issue's acceptance criteria.
///
/// Measured 2026-11-24 over requested seeds 1..60 per difficulty.
/// Update only together with a fresh probe run (temporary test, run and
/// transcribe) — never by hand.
const _convergence = {
  'easy': {
    1: 5,
    2: 5,
    3: 5,
    4: 5,
    6: 7,
    9: 12,
    10: 12,
    11: 12,
    15: 20,
    16: 20,
    17: 20,
    18: 20,
    19: 20,
    22: 23,
    24: 25,
    26: 30,
    27: 30,
    28: 30,
    29: 30,
    31: 32,
    34: 36,
    35: 36,
    38: 39,
    40: 41,
    44: 45,
    46: 49,
    47: 49,
    48: 49,
    50: 52,
    51: 52,
    53: 54,
    56: 57,
    59: 60,
  },
  'standard': {
    1: 5,
    2: 5,
    3: 5,
    4: 5,
    6: 10,
    7: 10,
    8: 10,
    9: 10,
    12: 19,
    13: 19,
    14: 19,
    15: 19,
    16: 19,
    17: 19,
    18: 19,
    21: 24,
    22: 24,
    23: 24,
    25: 27,
    26: 27,
    28: 44,
    29: 44,
    30: 44,
    31: 44,
    32: 44,
    33: 44,
    34: 44,
    35: 44,
    36: 44,
    37: 44,
    38: 44,
    39: 44,
    40: 44,
    41: 44,
    42: 44,
    43: 44,
    46: 50,
    47: 50,
    48: 50,
    49: 50,
    51: 59,
    52: 59,
    53: 59,
    54: 59,
    55: 59,
    56: 59,
    57: 59,
    58: 59,
  },
  'hard': {
    1: 6,
    2: 6,
    3: 6,
    4: 6,
    5: 6,
    7: 17,
    8: 17,
    9: 17,
    10: 17,
    11: 17,
    12: 17,
    13: 17,
    14: 17,
    15: 17,
    16: 17,
    18: 25,
    19: 25,
    20: 25,
    21: 25,
    22: 25,
    23: 25,
    24: 25,
    26: 45,
    27: 45,
    28: 45,
    29: 45,
    30: 45,
    31: 45,
    32: 45,
    33: 45,
    34: 45,
    35: 45,
    36: 45,
    37: 45,
    38: 45,
    39: 45,
    40: 45,
    41: 45,
    42: 45,
    43: 45,
    44: 45,
    46: 48,
    47: 48,
    49: 58,
    50: 58,
    51: 58,
    52: 58,
    53: 58,
    54: 58,
    55: 58,
    56: 58,
    57: 58,
    59: 77,
    60: 77,
  },
};

void main() {
  test('pin: requested seeds 1..60 map to the measured first-success attempt seeds (#46)', () {
    for (final entry in _convergence.entries) {
      final difficulty = DifficultyX.fromName(entry.key);
      final diverging = entry.value;
      for (var seed = 1; seed <= 60; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        expect(
          c.seed,
          diverging[seed] ?? seed,
          reason: '${difficulty.name} seed $seed converged differently',
        );
      }
    }
  });

  test(
    'pin: seeds 1..5 converge to one identical case per difficulty (#46)',
    () {
      // The issue's headline observation: requested seeds through seed 5
      // sit in one basin — the stored attempt seed alone decides the case.
      for (final entry in _convergence.entries) {
        final difficulty = DifficultyX.fromName(entry.key);
        final stored = <int>{};
        final jsons = <String>{};
        for (var seed = 1; seed <= 5; seed++) {
          final c = generateCase(difficulty: difficulty, seed: seed);
          stored.add(c.seed);
          jsons.add(jsonEncode(c.toJson()));
        }
        expect(
          stored.length,
          1,
          reason: '${difficulty.name} seeds 1..5 must share one attempt seed',
        );
        expect(
          jsons.length,
          1,
          reason: '${difficulty.name} seeds 1..5 must produce one case',
        );
      }
    },
  );

  test('pin: stored seed identifies the generated case over 1..60 (#46)', () {
    // The convergence pin assumes two different stored attempt seeds never
    // produce identical non-seed content; otherwise a stored-seed table
    // would mask a real variety change.
    for (final entry in _convergence.entries) {
      final difficulty = DifficultyX.fromName(entry.key);
      final stored = <int>{};
      final contents = <String>{};
      for (var seed = 1; seed <= 60; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final json = c.toJson()..remove('seed');
        if (stored.add(c.seed)) contents.add(jsonEncode(json));
      }
      expect(
        contents.length,
        stored.length,
        reason:
            '${difficulty.name}: two stored seeds produced identical '
            'non-seed content over seeds 1..60',
      );
    }
  });
}
