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

/// Golden digests captured from the pre-refactor generator (2026-11-23,
/// issue 35). Spaced seeds: consecutive seeds converge onto the same case
/// through the retry budget, so nearby seeds are not distinct goldens. The
/// set spans the clue window (easy 6-7, standard 8-10, hard 12-14), the
/// negated top-up caps (standard 1, hard 3) and distinct retry paths.
const golden = {
  'easy/1': '37deeb690fa7308b',
  'easy/101': 'bf31588bc989d610',
  'easy/201': '61ca1d912312dffb',
  'easy/301': '3f75aea3dbda84ac',
  'easy/11': '855c02491eb0ca87',
  'easy/17': '5460643094950c55',
  'easy/23': 'd635333a79d23874',
  'easy/29': '606b5183749aabbb',
  'standard/1': '0df0f25b3d2b2ecb',
  'standard/101': '9c38b1b9b1c08bf8',
  'standard/201': '5e202dae78af0985',
  'standard/301': '9fabc305524e4661',
  'standard/11': 'a2f5acdd11424e5f',
  'standard/211': '1522a26a8745728c',
  'standard/123': 'b3d3e328664db58c',
  'standard/129': '462878cefc512125',
  'hard/1': '84c3f237e01bdefd',
  'hard/101': '428c494fa6e5496a',
  'hard/201': '85f9c3ddcf61fc36',
  'hard/301': '2e15d9a98cf2655f',
  'hard/401': '7ec1c78a0630dc5e',
  'hard/11': '62e496e91904957b',
  'hard/111': 'b7fbb35bb14d30ed',
  'hard/211': 'bb55ff6c3e9aa786',
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
