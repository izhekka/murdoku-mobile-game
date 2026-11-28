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
///
/// Re-pinned 2026-11-28 for issue #106 (deduction-chain gate): exactly
/// four easy digests moved (easy/101, /301, /23, /29 — the chain gate
/// picked a different clue set there); every other entry, the convergence
/// table and all stored attempt seeds measured unchanged.
/// Re-pinned 2026-11-28 for issue #111 (object-cell clue kinds join the
/// pool, positive direction candidates capped at 2, negated directions
/// removed): every digest regenerates.
const golden = {
  'easy/1': 'f5550abd10168a97',
  'easy/101': '9b8c43ef39db5f5a',
  'easy/201': '735ed0cdad0e2fd8',
  'easy/301': 'b84a6b77aee34eff',
  'easy/11': 'd7ef9a9dc8f6b6bb',
  'easy/17': 'cde76630bfdefe61',
  'easy/23': '4a4b3a4e86b8c632',
  'easy/29': 'b99f75365d83c832',
  'standard/1': 'bb533c374d6299fe',
  'standard/101': '1388cfb88b608dca',
  'standard/201': '77428ed5c3a002df',
  'standard/301': '46d208ccf8b78338',
  'standard/11': '7e4949321fea5783',
  'standard/211': 'e4bd30788ea360dc',
  'standard/123': '02f96a06d93421a6',
  'standard/129': '7c593e71f186d464',
  // 20261119/20261120 are dailySeedFor(2026-11-19) / (2026-11-20) — the UTC
  // dates pinned in the daily-card tests (issue 49).
  'standard/20261119': 'bdabdb853f0f917b',
  'standard/20261120': '309d07df497a0de2',
  'hard/1': '3ded47b6a543e9da',
  'hard/101': '500a773c4d6ac997',
  'hard/201': '67c1f6691c060fc6',
  'hard/301': 'b98ff450ad8ba998',
  'hard/401': 'a907741dfed8d1ac',
  'hard/11': '1cdc1e5f5a66e772',
  'hard/112': 'cd5df795cf366db3',
  'hard/211': '306838b2a3c2c9ac',
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
