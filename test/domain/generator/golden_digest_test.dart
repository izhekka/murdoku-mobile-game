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

/// Golden digests captured from the issue-61 derived attempt-seed mapping
/// (2026-11-24; originally captured 2026-11-23, issue 35, and regenerated
/// in the same change as the attempt-seed re-derivation — the digest test's
/// seeds list and values move together with any attempt-seed remap, §13).
/// The set spans the clue window (easy 6-7, standard 8-10, hard 12-14), the
/// negated top-up caps (standard 1, hard 3) and distinct derived retry
/// paths; nearby seeds now hash distinct cases (the pre-#61 mapping made
/// spaced seeds necessary). hard/111 exhausts the whole budget under the
/// derived mapping, so its slot moved to the generating neighbor 112.
const golden = {
  'easy/1': '9824ca8d10f6fd06',
  'easy/101': '9b771a2636e78992',
  'easy/201': 'a3cf5e480534c082',
  'easy/301': 'ac021d40f41f7bf3',
  'easy/11': 'fc60195ae391159f',
  'easy/17': 'cc3d3f4914a8d1d8',
  'easy/23': '4a130a34d2fc23ac',
  'easy/29': '8a1fa98db4590de8',
  'standard/1': '8c0ec46047c56cd1',
  'standard/101': 'a9d0c28bb65b45a3',
  'standard/201': '3123b4dfc683ad00',
  'standard/301': '925ebe072620a3e1',
  'standard/11': 'dfa48b224f6d95f6',
  'standard/211': '84824d886890ec84',
  'standard/123': '2bdb97cf8caa3043',
  'standard/129': '30293967f726e797',
  // 20261119/20261120 are dailySeedFor(2026-11-19) / (2026-11-20) — the UTC
  // dates pinned in the daily-card tests (issue 49). Under the derived
  // mapping the two consecutive dates generate distinct cases (issue 61),
  // so the digests differ.
  'standard/20261119': '780d586106bf65c6',
  'standard/20261120': 'd12db8c1fb581348',
  'hard/1': '88b269dfceb54844',
  'hard/101': 'e0f75bff9a81fec1',
  'hard/201': '392de78e2dc61cc7',
  'hard/301': '1132c97e7abaaefe',
  'hard/401': 'aac354a9898bf2bd',
  'hard/11': '6992d08c001592d5',
  'hard/112': '55ec51fcbf077c9c',
  'hard/211': '87c1dc1d64c500bb',
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
