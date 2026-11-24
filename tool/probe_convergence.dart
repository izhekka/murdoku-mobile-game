/// Probe for the §13 pin re-measure procedure (issue #62): measures
/// [generateCase]'s stored attempt seed per requested seed and prints the
/// mapping in a transcribable form.
///
/// Run: `dart run tool/probe_convergence.dart [mapping|map [<start> [<end>]]]`
/// - `mapping` (default) — rows `difficulty seed -> stored`; a budget
///   exhaust prints as `difficulty seed -> exhausts within the widened
///   budget`.
/// - `map` — the `_convergence` Dart map literal of
///   test/domain/generator/seed_convergence_test.dart, ready to transcribe;
///   exhaust notes go to stderr so stdout stays a clean literal.
///
/// A lone `<start>` only narrows within the 0..60 pin range (`<end>` stays
/// 60); pass `<start> <end>` to widen past it.
///
/// Read-only over the generator: every printed stored seed is measured
/// live from [generateCase] — never synthesized (§13: never hand-write the
/// table). Under the derived attempt-seed mapping (issue 61) nearby
/// requested seeds walk decorrelated streams, so the probe prints the FULL
/// map per difficulty and keeps the difficulty dimension: cross-difficulty
/// stored-seed collisions are real (easy/4 == standard/4 == 1647545034).
/// A requested seed whose whole widened budget exhausts has no stored seed
/// and is reported instead of fabricated (e.g. hard/111). Usage errors
/// exit 2 — the tool/flutter_test_lock.dart usage-error code.
library;

import 'dart:io';

import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Output form of the probe: row lines or the transcribable map literal.
enum ProbeMode { mapping, map }

/// The stored attempt seed for a requested [seed], or null when
/// [generateCase]'s whole widened budget exhausts for it (no unique case;
/// §13 corridor seam, e.g. hard/111 under the derived mapping).
int? storedSeedFor(Difficulty difficulty, int seed) {
  try {
    return generateCase(difficulty: difficulty, seed: seed).seed;
  } on StateError {
    return null;
  }
}

/// The measured requested → stored attempt-seed map: `difficulty.name` →
/// requested seed → stored seed, difficulties in [Difficulty.values] order
/// and seeds ascending; a null stored seed marks a budget exhaust. Default
/// range is the §13 pin domain: seeds 0..60.
Map<String, Map<int, int?>> measureMapping({int start = 0, int end = 60}) {
  final mapping = <String, Map<int, int?>>{};
  for (final difficulty in Difficulty.values) {
    final seeds = <int, int?>{};
    for (var seed = start; seed <= end; seed++) {
      seeds[seed] = storedSeedFor(difficulty, seed);
    }
    mapping[difficulty.name] = seeds;
  }
  return mapping;
}

/// One `difficulty seed -> stored` row per measured seed; an exhaust row
/// renders as `difficulty seed -> exhausts within the widened budget`.
/// Difficulties in [Difficulty.values] order, seeds ascending — the input
/// map's order does not matter.
String formatRows(Map<String, Map<int, int?>> mapping) {
  final rows = <String>[];
  for (final difficulty in Difficulty.values) {
    final seeds = mapping[difficulty.name];
    if (seeds == null) continue;
    final seedList = seeds.keys.toList()..sort();
    for (final seed in seedList) {
      final stored = seeds[seed];
      rows.add(
        stored == null
            ? '${difficulty.name} $seed -> exhausts within the widened budget'
            : '${difficulty.name} $seed -> $stored',
      );
    }
  }
  return rows.join('\n');
}

/// The `_convergence` map literal of test/domain/generator/
/// seed_convergence_test.dart, byte-shaped like the pin table:
/// `const _convergence = {` … `};` with one `'difficulty': {` block per
/// difficulty ([Difficulty.values] order, ascending seeds). Exhaust rows
/// (null stored seeds) are skipped so the emitted block stays strictly
/// seed-keyed — callers report exhausts separately instead.
String formatMapLiteral(Map<String, Map<int, int?>> mapping) {
  final lines = <String>['const _convergence = {'];
  for (final difficulty in Difficulty.values) {
    final seeds = mapping[difficulty.name];
    if (seeds == null) continue;
    final seedList = seeds.keys.where((seed) => seeds[seed] != null).toList()
      ..sort();
    lines.add("  '${difficulty.name}': {");
    for (final seed in seedList) {
      lines.add('    $seed: ${seeds[seed]},');
    }
    lines.add('  },');
  }
  lines.add('};');
  return lines.join('\n');
}

/// Parsed CLI usage: mode plus the inclusive `[start, end]` requested-seed
/// range, defaults `mapping` over 0..60 (the §13 pin domain) and a
/// mode-only invocation keeps the default end. Returns null on any
/// malformed usage: unknown mode, non-integer or negative seed, inverted
/// range, or more than mode plus two seeds.
({ProbeMode mode, int start, int end})? parseArgs(List<String> args) {
  if (args.isEmpty) {
    return (mode: ProbeMode.mapping, start: 0, end: 60);
  }
  if (args.length > 3) return null;
  final mode = switch (args.first) {
    'mapping' => ProbeMode.mapping,
    'map' => ProbeMode.map,
    _ => null,
  };
  if (mode == null) return null;
  final bounds = <int?>[for (final arg in args.skip(1)) int.tryParse(arg)];
  if (bounds.contains(null)) return null;
  final start = bounds.isEmpty ? 0 : bounds[0]!;
  final end = bounds.length < 2 ? 60 : bounds[1]!;
  if (start < 0 || end < 0 || start > end) return null;
  return (mode: mode, start: start, end: end);
}

void main(List<String> args) {
  final parsed = parseArgs(args);
  if (parsed == null) {
    stderr.writeln(
      'probe_convergence: usage: dart run tool/probe_convergence.dart '
      '[mapping|map [<start> [<end>]]]',
    );
    // Usage error — the tool/flutter_test_lock.dart convention.
    exitCode = 2;
    return;
  }
  final mapping = measureMapping(start: parsed.start, end: parsed.end);
  if (parsed.mode == ProbeMode.map) {
    for (final entry in mapping.entries) {
      final exhausted = entry.value.keys.where(
        (seed) => entry.value[seed] == null,
      );
      for (final seed in exhausted) {
        stderr.writeln('${entry.key} $seed exhausts within the widened budget');
      }
    }
    stdout.writeln(formatMapLiteral(mapping));
    return;
  }
  stdout.writeln(formatRows(mapping));
}
