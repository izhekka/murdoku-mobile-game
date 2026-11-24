import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Pins the attempt-seed mapping of [generateCase]: each attempt derives its
/// rng seed from `(requested seed, attempt index)` (splitmix64 stream step +
/// finalizer), so failure basins measured under the old sequential mapping
/// (easy 1–4 → 5, standard 28–43 → 44, hard 26–44 → 45) are genuinely
/// removed — nearby requested seeds no longer collapse onto one stored seed
/// (issue 61, landing §13's "hash the seed per attempt" option).
///
/// The table below pins the measured requested → stored mapping (seeds
/// 0..60, all difficulties). Measured 2026-11-24 over the derived mapping;
/// update only together with a fresh probe run (temporary test, run and
/// transcribe) — never by hand, and only in the same change as the
/// regenerated golden digests (§13).
const _convergence = {
  'easy': {
    0: 565798388,
    1: 269157861,
    2: 201072194,
    3: 1662265584,
    4: 1647545034,
    5: 596231002,
    6: 1461135984,
    7: 2065162004,
    8: 485206504,
    9: 2145213143,
    10: 691144057,
    11: 1966783341,
    12: 796882670,
    13: 792109169,
    14: 1982840361,
    15: 887756089,
    16: 1233478731,
    17: 1914458558,
    18: 638846681,
    19: 406976599,
    20: 1382288114,
    21: 1873750857,
    22: 914179662,
    23: 1046035621,
    24: 1535560376,
    25: 1892136713,
    26: 2047477467,
    27: 1501628042,
    28: 863116194,
    29: 134336368,
    30: 1920077262,
    31: 127920874,
    32: 1233104197,
    33: 1042421928,
    34: 445755009,
    35: 1905496626,
    36: 1834291426,
    37: 266932680,
    38: 583017877,
    39: 1204080003,
    40: 1890816805,
    41: 1001954597,
    42: 803958421,
    43: 1800400776,
    44: 697979987,
    45: 849014403,
    46: 943464469,
    47: 1501354885,
    48: 1980235555,
    49: 1841473880,
    50: 2045141623,
    51: 1317486696,
    52: 258929363,
    53: 665525204,
    54: 818264924,
    55: 1938557595,
    56: 1385470105,
    57: 1381736465,
    58: 58162078,
    59: 2057509952,
    60: 295270247,
  },
  'standard': {
    0: 607567,
    1: 1849870603,
    2: 2145908324,
    3: 1526829037,
    4: 1647545034,
    5: 628934311,
    6: 1886925676,
    7: 1732127179,
    8: 2131474435,
    9: 9333758,
    10: 173551562,
    11: 1966783341,
    12: 434016003,
    13: 778752663,
    14: 635718904,
    15: 1660181831,
    16: 980914695,
    17: 786658147,
    18: 638846681,
    19: 156087121,
    20: 880243823,
    21: 779188571,
    22: 872734075,
    23: 1503966089,
    24: 1878557717,
    25: 114556472,
    26: 2047477467,
    27: 1501628042,
    28: 661062661,
    29: 1618976026,
    30: 1920077262,
    31: 74379621,
    32: 2023635428,
    33: 175103428,
    34: 832841459,
    35: 1605021787,
    36: 1480678066,
    37: 1870007832,
    38: 380927664,
    39: 1413884065,
    40: 211915026,
    41: 1378504331,
    42: 319790930,
    43: 778044235,
    44: 1918749909,
    45: 164260894,
    46: 116433452,
    47: 1177696270,
    48: 1980235555,
    49: 606314889,
    50: 811644344,
    51: 2118185977,
    52: 635735079,
    53: 361675542,
    54: 818264924,
    55: 1423753265,
    56: 689942532,
    57: 2119914330,
    58: 805855186,
    59: 819116092,
    60: 1778269306,
  },
  'hard': {
    0: 524628705,
    1: 1463172261,
    2: 479680206,
    3: 811354239,
    4: 1851393414,
    5: 110751531,
    6: 1405041736,
    7: 2065162004,
    8: 1199405057,
    9: 389111904,
    10: 1745764648,
    11: 2058377230,
    12: 1254822303,
    13: 1741265682,
    14: 1900373939,
    15: 737497093,
    16: 1951536959,
    17: 1491364279,
    18: 1142938966,
    19: 1472649530,
    20: 476470136,
    21: 937960903,
    22: 914179662,
    23: 1570979062,
    24: 1043353066,
    25: 1809021843,
    26: 2112612905,
    27: 858394364,
    28: 1846860506,
    29: 1310381705,
    30: 420790252,
    31: 885541809,
    32: 878315235,
    33: 175103428,
    34: 1171057327,
    35: 84173749,
    36: 326744860,
    37: 1040744996,
    38: 991683712,
    39: 807778937,
    40: 3516187,
    41: 1001954597,
    42: 803958421,
    43: 90724455,
    44: 105396679,
    45: 163621601,
    46: 263882868,
    47: 1265858728,
    48: 1123840120,
    49: 928480153,
    50: 2045141623,
    51: 1714975233,
    52: 258929363,
    53: 1612738422,
    54: 1775498101,
    55: 1187393398,
    56: 1385470105,
    57: 1480665456,
    58: 535188786,
    59: 1660219416,
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
