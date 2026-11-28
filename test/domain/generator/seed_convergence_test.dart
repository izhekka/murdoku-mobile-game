import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Pins the attempt-seed mapping of [generateCase]: each attempt derives its
/// rng seed from `(requested seed, attempt index)` (splitmix64 stream step +
/// finalizer), so failure basins measured under the old sequential mapping
/// (easy 1–4 → 5, standard 28–43 → 44, hard 26–44 → 45) are genuinely
/// removed (issue 61, landing §13's "hash the seed per attempt" option).
///
/// The table below pins the measured requested → stored mapping (seeds
/// 0..60, all difficulties). Measured 2026-11-27 for the issue-#93 interim
/// configuration (killer-naming exclusions + take-all pool + easy 5×5 /
/// standard 7×7 / hard 7×7 with pre-change knobs): every difficulty now
/// succeeds on attempt 0 across the whole pinned range — all three columns
/// are identical because the stored seed is the attempt-0 derivation, which
/// is difficulty-independent — and requested seed 0 maps to itself (the
/// derived seed of attempt 0 over requested 0 is 0). Update only together
/// with a fresh `dart run tool/probe_convergence.dart map` run (transcribe
/// its `map` output) — never by hand, and only in the same change as the
/// regenerated golden digests (§13).
///
/// Re-measured 2026-11-28 for issue #106 (deduction-chain gate): the table
/// is byte-identical — every pinned seed still converges on attempt 0, no
/// exhaust in 0..60 — so all values stand as transcribed above.
const _convergence = {
  'easy': {
    0: 0,
    1: 269157861,
    2: 975901834,
    3: 1662265584,
    4: 1951803668,
    5: 1052460508,
    6: 1886925676,
    7: 2065162004,
    8: 485206504,
    9: 2145213143,
    10: 691144057,
    11: 1966783341,
    12: 1461795772,
    13: 905478609,
    14: 1982840361,
    15: 887756089,
    16: 1285859517,
    17: 1914458558,
    18: 1990887537,
    19: 406976599,
    20: 1382288114,
    21: 1873750857,
    22: 872734075,
    23: 1046035621,
    24: 1535560376,
    25: 114556472,
    26: 2047477467,
    27: 858394364,
    28: 863116194,
    29: 666324818,
    30: 1775512178,
    31: 74379621,
    32: 1233104197,
    33: 34105543,
    34: 677652540,
    35: 113255102,
    36: 1834291426,
    37: 1870007832,
    38: 1712690030,
    39: 1204080003,
    40: 1890816805,
    41: 1001954597,
    42: 1416787490,
    43: 1201199306,
    44: 1745468151,
    45: 849014403,
    46: 2092071243,
    47: 591059996,
    48: 952627556,
    49: 1113770207,
    50: 1096836912,
    51: 2118185977,
    52: 635735079,
    53: 665525204,
    54: 818264924,
    55: 1938557595,
    56: 689942532,
    57: 1381736465,
    58: 913996152,
    59: 1823867422,
    60: 1403540709,
  },
  'standard': {
    0: 0,
    1: 269157861,
    2: 975901834,
    3: 1662265584,
    4: 1951803668,
    5: 1052460508,
    6: 1886925676,
    7: 2065162004,
    8: 485206504,
    9: 2145213143,
    10: 691144057,
    11: 1966783341,
    12: 1461795772,
    13: 905478609,
    14: 1982840361,
    15: 887756089,
    16: 1285859517,
    17: 1914458558,
    18: 1990887537,
    19: 406976599,
    20: 1382288114,
    21: 1873750857,
    22: 872734075,
    23: 1046035621,
    24: 1535560376,
    25: 114556472,
    26: 2047477467,
    27: 858394364,
    28: 863116194,
    29: 666324818,
    30: 1775512178,
    31: 74379621,
    32: 1233104197,
    33: 34105543,
    34: 677652540,
    35: 113255102,
    36: 1834291426,
    37: 1870007832,
    38: 1712690030,
    39: 1204080003,
    40: 1890816805,
    41: 1001954597,
    42: 1416787490,
    43: 1201199306,
    44: 1745468151,
    45: 849014403,
    46: 2092071243,
    47: 591059996,
    48: 952627556,
    49: 1113770207,
    50: 1096836912,
    51: 2118185977,
    52: 635735079,
    53: 665525204,
    54: 818264924,
    55: 1938557595,
    56: 689942532,
    57: 1381736465,
    58: 913996152,
    59: 1823867422,
    60: 1403540709,
  },
  'hard': {
    0: 0,
    1: 269157861,
    2: 975901834,
    3: 1662265584,
    4: 1951803668,
    5: 1052460508,
    6: 1886925676,
    7: 2065162004,
    8: 485206504,
    9: 2145213143,
    10: 691144057,
    11: 1966783341,
    12: 1461795772,
    13: 905478609,
    14: 1982840361,
    15: 887756089,
    16: 1285859517,
    17: 1914458558,
    18: 1990887537,
    19: 406976599,
    20: 1382288114,
    21: 1873750857,
    22: 872734075,
    23: 1046035621,
    24: 1535560376,
    25: 114556472,
    26: 2047477467,
    27: 858394364,
    28: 863116194,
    29: 666324818,
    30: 1775512178,
    31: 74379621,
    32: 1233104197,
    33: 34105543,
    34: 677652540,
    35: 113255102,
    36: 1834291426,
    37: 1870007832,
    38: 1712690030,
    39: 1204080003,
    40: 1890816805,
    41: 1001954597,
    42: 1416787490,
    43: 1201199306,
    44: 1745468151,
    45: 849014403,
    46: 2092071243,
    47: 591059996,
    48: 952627556,
    49: 1113770207,
    50: 1096836912,
    51: 2118185977,
    52: 635735079,
    53: 665525204,
    54: 818264924,
    55: 1938557595,
    56: 689942532,
    57: 1381736465,
    58: 913996152,
    59: 1823867422,
    60: 1403540709,
  },
};

void main() {
  test('pin: requested seeds 0..60 map to the measured derived attempt seeds (#61)', () {
    for (final entry in _convergence.entries) {
      final difficulty = DifficultyX.fromName(entry.key);
      final diverging = entry.value;
      for (var seed = 0; seed <= 60; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        expect(
          // Full table coverage: a missing entry fails here (the derived
          // mapping never stores the requested seed itself, so `?? seed`
          // would silently hide drift).
          diverging[seed]!,
          c.seed,
          reason: '${difficulty.name} seed $seed mapped differently',
        );
      }
    }
  });

  test('pin: requested seeds 0..5 each produce one distinct case per difficulty (#61)', () {
    // Issue 61's user story: nearby seeds must not collapse onto one
    // stored attempt seed. Basins measured under the old sequential
    // mapping put seeds 0..5 in one basin; the derived mapping must
    // produce one distinct stored seed AND one distinct case per seed.
    for (final entry in _convergence.entries) {
      final difficulty = DifficultyX.fromName(entry.key);
      final stored = <int>{};
      final jsons = <String>{};
      for (var seed = 0; seed <= 5; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        stored.add(c.seed);
        jsons.add(jsonEncode(c.toJson()));
      }
      expect(
        stored.length,
        6,
        reason:
            '${difficulty.name} seeds 0..5 must map to distinct '
            'attempt seeds',
      );
      expect(
        jsons.length,
        6,
        reason: '${difficulty.name} seeds 0..5 must produce distinct cases',
      );
    }
  });

  test(
    'pin: no two adjacent requested seeds 1..59 share a stored seed (#61)',
    () {
      for (final entry in _convergence.entries) {
        final difficulty = DifficultyX.fromName(entry.key);
        for (var seed = 1; seed <= 59; seed++) {
          final a = generateCase(difficulty: difficulty, seed: seed);
          final b = generateCase(difficulty: difficulty, seed: seed + 1);
          expect(
            a.seed == b.seed,
            isFalse,
            reason:
                '${difficulty.name} adjacent seeds $seed/${seed + 1} share '
                'stored seed ${a.seed} — a convergence basin survived',
          );
        }
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
