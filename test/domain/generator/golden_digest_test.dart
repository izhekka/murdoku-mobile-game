import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// FNV-1a 64-bit digest of the JSON-encoded case, printed as 16 hex digits
/// (high word then low word; avoids negative toRadixString output). The
/// generator output is pinned by digest so any refactor that changes the
/// generated content (e.g. a reordered RNG call during extraction) fails
/// loudly, even though the output would still be internally deterministic
/// (issue 35).
String digestCase(CaseData c) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(jsonEncode(c.toJson()))) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  final hi = (hash >> 32) & 0xFFFFFFFF;
  final lo = hash & 0xFFFFFFFF;
  return '${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}

/// Golden digests captured for the issue-#93 interim configuration
/// (2026-11-27): the four killer-naming/proximity-victim exclusion classes
/// removed at the emit sites, the take-all per-type pool (the historical
/// cap 10 starved the uniqueness search — see the cap comment in
/// `case_factory.dart`), easy at 5×5 with unchanged knobs, standard at the
/// new 7×7 with retuned knobs, and hard kept at 7×7 with its pre-change
/// knobs (the 9×9 leg is deferred to #98). Regenerated with
/// `dart run tool/probe_convergence.dart digests`. The digest-literal-copy
/// in test/tool/probe_convergence_test.dart moves together with this map.
const golden = {
  'easy/1': '4573f6db2f8b1c6c',
  'easy/101': '4a721ccb2f6b29c1',
  'easy/201': '5825c777b958015d',
  'easy/301': 'e10c88c0350a84f2',
  'easy/11': '07dedcdaabe48941',
  'easy/17': 'cc078c577799cbb5',
  'easy/23': 'd1499e9ea8ee1f2c',
  'easy/29': 'f70d1b2ebf04e4fe',
  'standard/1': 'f3d910d0baed9b76',
  'standard/101': 'e872ccda37f5b18f',
  'standard/201': '9cfaf0014587c3d1',
  'standard/301': '68eca9e05283ace3',
  'standard/11': 'b1f2d4adfe85d78f',
  'standard/211': 'b6d3954a69ec63b8',
  'standard/123': '11651f6f024f82a1',
  'standard/129': 'c48848b2f11762de',
  // 20261119/20261120 are dailySeedFor(2026-11-19) / (2026-11-20) — the UTC
  // dates pinned in the daily-card tests (issue 49).
  'standard/20261119': '51e2e3d18c366a4b',
  'standard/20261120': 'fc194dd2155e926d',
  'hard/1': '378e0f7f008c09ad',
  'hard/101': '5897daef6d5bc1fa',
  'hard/201': 'ce93a5d5b5465813',
  'hard/301': 'f4a857d6dacc4b24',
  'hard/401': '6e4e4620b00cfab0',
  'hard/11': 'a14859cda6a1f7a9',
  'hard/112': 'c226621083507342',
  'hard/211': 'ce40ff2c2ff50bb5',
};

void main() {
  test('seeded generator digests match the pinned goldens', () {
    for (final entry in golden.entries) {
      final parts = entry.key.split('/');
      final difficulty = DifficultyX.fromName(parts[0]);
      final seed = int.parse(parts[1]);
      final digest = digestCase(
        generateCase(difficulty: difficulty, seed: seed),
      );
      expect(
        digest,
        entry.value,
        reason: '$difficulty seed $seed drifted from the golden',
      );
    }
  });
}
