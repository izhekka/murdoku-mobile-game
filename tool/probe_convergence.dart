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
/// Digest surface (issue #72), part of the same §13 re-pin procedure:
/// - `digests` — reprints the committed `golden` literal of
///   test/domain/generator/golden_digest_test.dart with freshly measured
///   digests: the exact values to transcribe at a re-pin. Exhaust entries
///   are reported and skipped (never fabricated); drift against the
///   committed bytes goes to stderr so stdout stays a clean literal.
/// - `daily [<yyyy-mm-dd> [<yyyy-mm-dd>]]` — the daily-date digest inputs:
///   per UTC date `yyyy-mm-dd seed -> digest`. No dates means the golden
///   file's date-shaped entries (the daily-card assertions' inputs); an
///   explicit single date or inclusive range sweeps difficulty `standard`.
/// - `check` — verifies every committed digest live; prints per-entry
///   `ok`/`drift`/`exhausts` lines and exits 1 on any drift or exhaust.
///
/// The digest surface is read-only over the generator and fully
/// deterministic (no wall-clock inputs): daily/check output is identical
/// across two consecutive runs. All modes are MANUAL invocation only —
/// never wired into `make quality` (same boundary as the #62 probe).
///
/// Read-only over the generator: every printed stored seed and digest is
/// measured live from [generateCase] — never synthesized (§13: never
/// hand-write the table). Under the derived attempt-seed mapping (issue 61)
/// nearby requested seeds walk decorrelated streams, so the probe prints
/// the FULL map per difficulty and keeps the difficulty dimension:
/// cross-difficulty stored-seed collisions are real (easy/4 ==
/// standard/4 == 1647545034). A requested seed whose whole widened budget
/// exhausts has no stored seed and is reported instead of fabricated
/// (e.g. hard/111). Usage errors exit 2 — the tool/flutter_test_lock.dart
/// usage-error code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Output form of the probe: mapping rows, the transcribable map literal,
/// or the golden-digest modes of issue #72.
enum ProbeMode { mapping, map, digests, daily, check }

/// The committed golden-digest file the digest modes read (repo-relative —
/// run the probe from the repo root, like the crap_check lcov defaults).
const goldenFileDefault = 'test/domain/generator/golden_digest_test.dart';

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

/// The live FNV-1a 64-bit digest of a generated case, byte-identical to
/// `digestCase` in test/domain/generator/golden_digest_test.dart. One
/// implementation per file — the test file imports flutter_test, which a
/// plain `dart run` tool cannot — so CHANGE BOTH TOGETHER (and the digest
/// test's own suite is the executable parity check: its literals are the
/// values pinned in test/tool/probe_convergence_test.dart).
String digestOf(CaseData c) {
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

/// [digestOf] over a measured generation; null marks a budget exhaust
/// (no case to digest — the digests/check modes report, never fabricate).
String? digestFor(Difficulty difficulty, int seed) {
  try {
    return digestOf(generateCase(difficulty: difficulty, seed: seed));
  } on StateError {
    return null;
  }
}

/// One parsed entry of the committed `golden` literal in
/// [goldenFileDefault]: key `<difficulty>/<seed>` and its committed digest.
class GoldenEntry {
  const GoldenEntry({
    required this.key,
    required this.difficulty,
    required this.seed,
    required this.committed,
  });

  final String key;
  final Difficulty difficulty;
  final int seed;
  final String committed;
}

/// Entry-line shape of the `const golden = { ... }` literal: `  'easy/1':
/// '9824ca8d10f6fd06',`. Comment lines, blanks and anything outside that
/// shape are skipped — the digests mode is a printer, not a validator.
final _goldenEntryPattern = RegExp(
  r'''^\s*'([A-Za-z]+)/(\d+)':\s*'([0-9a-f]{16})',\s*$''',
);

/// Parses every committed golden entry from [source] in file order.
List<GoldenEntry> parseGoldenEntries(String source) {
  final difficulties = {
    for (final difficulty in Difficulty.values) difficulty.name: difficulty,
  };
  final entries = <GoldenEntry>[];
  for (final line in source.split('\n')) {
    final match = _goldenEntryPattern.firstMatch(line);
    if (match == null) continue;
    final difficulty = difficulties[match.group(1)];
    if (difficulty == null) continue;
    final seed = int.parse(match.group(2)!);
    entries.add(
      GoldenEntry(
        key: '${difficulty.name}/$seed',
        difficulty: difficulty,
        seed: seed,
        committed: match.group(3)!,
      ),
    );
  }
  return entries;
}

/// Parses the committed golden file at [path]. `FileSystemException`
/// propagates — the CLI wrapper turns a missing file into exit 2.
List<GoldenEntry> readGoldenEntries(String path) =>
    parseGoldenEntries(File(path).readAsStringSync());

/// Last day of [month] in [year] — `DateTime.utc(y, m + 1, 0)` normalizes
/// past month 12, so December resolves to the year's final day.
int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// True when [seed] is a dailySeedFor-shaped UTC date (2019 onward — the
/// daily domain): month 1..12 and a day the month actually has. Ordinary
/// pin seeds (1, 101, 112, ...) are short, so they never read as dates.
bool isDailySeed(int seed) {
  if (seed < 20190101) return false;
  final year = seed ~/ 10000;
  if (year > 9999) return false;
  final month = seed ~/ 100 % 100;
  final day = seed % 100;
  return month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= daysInMonth(year, month);
}

/// yyyy-mm-dd (UTC), the daily identity format (state/clock.dart's
/// formatUtcDate — not importable from a plain `dart run` tool: it drags
/// flutter_riverpod in).
String formatDate(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

/// Calendar-valid parsing of a `yyyy-mm-dd` UTC date into a UTC-midnight
/// date: parts are decimal ints (padding is not enforced) and non-calendar
/// values (2026-02-30, month 13) are rejected — DateTime normalization
/// would silently roll them over, making a sweep non-deterministic against
/// its own date labels. Returns null on any malformed input.
DateTime? parseDateArg(String yyyyMmDd) {
  final parts = yyyyMmDd.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.contains(null)) return null;
  final year = parts[0]!;
  final month = parts[1]!;
  final day = parts[2]!;
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) {
    return null;
  }
  return DateTime.utc(year, month, day);
}

/// The daily-date digest surface (issue #72): one row per date. Two shapes:
/// - [fromGolden] — the golden file's date-shaped entries, the exact inputs
///   the daily-card digest assertions pin (dates derived from the seeds).
/// - [start] — an explicit inclusive UTC date range (`end` defaults to
///   [start]), at difficulty `standard`, the daily-path difficulty.
/// A null digest marks a bare-generation exhaust.
List<({String date, int seed, String? digest})> dailyRows({
  List<GoldenEntry>? fromGolden,
  DateTime? start,
  DateTime? end,
}) {
  if (fromGolden != null) {
    return [
      for (final entry in fromGolden.where((e) => isDailySeed(e.seed)))
        (
          date: formatDate(
            DateTime.utc(
              entry.seed ~/ 10000,
              entry.seed ~/ 100 % 100,
              entry.seed % 100,
            ),
          ),
          seed: entry.seed,
          digest: digestFor(entry.difficulty, entry.seed),
        ),
    ];
  }
  if (start == null) return const [];
  final stop = end ?? start;
  final rows = <({String date, int seed, String? digest})>[];
  for (
    var date = start;
    !date.isAfter(stop);
    date = date.add(const Duration(days: 1))
  ) {
    final seed = dailySeedFor(date);
    rows.add((
      date: formatDate(date),
      seed: seed,
      digest: digestFor(Difficulty.standard, seed),
    ));
  }
  return rows;
}

/// One `yyyy-mm-dd seed -> digest` row per daily date; an exhaust row
/// renders `yyyy-mm-dd seed -> exhausts`.
String formatDailyRows(List<({String date, int seed, String? digest})> rows) =>
    [
      for (final row in rows)
        '${row.date} ${row.seed} -> ${row.digest ?? 'exhausts'}',
    ].join('\n');

/// Per-entry verification of already-parsed committed digests, live from
/// [generateCase]: `ok <key>`, `drift <key> live=<live> committed=<that>`,
/// or `exhausts <key>` (the pin no longer generates — cannot verify).
({List<String> ok, List<String> drifted, List<String> exhausts})
checkGoldenEntries(List<GoldenEntry> entries) {
  final ok = <String>[];
  final drifted = <String>[];
  final exhausts = <String>[];
  for (final entry in entries) {
    final live = digestFor(entry.difficulty, entry.seed);
    if (live == null) {
      exhausts.add('exhausts ${entry.key}');
    } else if (live == entry.committed) {
      ok.add('ok ${entry.key}');
    } else {
      drifted.add('drift ${entry.key} live=$live committed=${entry.committed}');
    }
  }
  return (ok: ok, drifted: drifted, exhausts: exhausts);
}

/// [checkGoldenEntries] over the committed golden file at [path] — the
/// file is read exactly once here so callers that already hold the parsed
/// entries reuse them instead of a second unguarded read.
({List<String> ok, List<String> drifted, List<String> exhausts}) checkGolden(
  String path,
) => checkGoldenEntries(readGoldenEntries(path));

/// The transcribable `const golden = { ... }` literal of the resolved
/// entries (file order), byte-shaped like the pin file.
String formatDigestsLiteral(
  List<({GoldenEntry entry, String digest})> resolved,
) {
  final lines = <String>['const golden = {'];
  for (final one in resolved) {
    lines.add("  '${one.entry.key}': '${one.digest}',");
  }
  lines.add('};');
  return lines.join('\n');
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

/// Parsed CLI usage. `mapping`/`map` carry the inclusive `[start, end]`
/// requested-seed range, defaults `mapping` over 0..60 (the §13 pin
/// domain) and a mode-only invocation keeps the default end; `digests`/
/// `check` carry nothing; `daily` carries 0..2 strict `yyyy-mm-dd` dates
/// (none = golden-file default; one = a single date; two = an inclusive
/// range). Returns null on any malformed usage: unknown mode, non-integer
/// or negative seed, inverted range, invalid calendar date, or extra
/// arguments beyond the mode's surface.
({
  ProbeMode mode,
  int start,
  int end,
  DateTime? dailyStart,
  DateTime? dailyEnd,
})?
parseArgs(List<String> args) {
  ({
    ProbeMode mode,
    int start,
    int end,
    DateTime? dailyStart,
    DateTime? dailyEnd,
  })?
  bare(ProbeMode mode) =>
      (mode: mode, start: 0, end: 60, dailyStart: null, dailyEnd: null);
  if (args.isEmpty) {
    return bare(ProbeMode.mapping);
  }
  final mode = switch (args.first) {
    'mapping' => ProbeMode.mapping,
    'map' => ProbeMode.map,
    'digests' => ProbeMode.digests,
    'daily' => ProbeMode.daily,
    'check' => ProbeMode.check,
    _ => null,
  };
  if (mode == null) return null;
  if (mode == ProbeMode.digests || mode == ProbeMode.check) {
    if (args.length > 1) return null;
    return bare(mode);
  }
  if (mode == ProbeMode.daily) {
    final rest = args.skip(1).toList();
    if (rest.length > 2) return null;
    final dates = <DateTime>[];
    for (final arg in rest) {
      final date = parseDateArg(arg);
      if (date == null) return null;
      dates.add(date);
    }
    if (dates.length == 2 && dates[0].isAfter(dates[1])) return null;
    return (
      mode: mode,
      start: 0,
      end: 60,
      dailyStart: dates.isEmpty ? null : dates.first,
      dailyEnd: dates.isEmpty ? null : dates.last,
    );
  }
  final bounds = <int?>[for (final arg in args.skip(1)) int.tryParse(arg)];
  if (args.length > 3) return null;
  if (bounds.contains(null)) return null;
  final start = bounds.isEmpty ? 0 : bounds[0]!;
  final end = bounds.length < 2 ? 60 : bounds[1]!;
  if (start < 0 || end < 0 || start > end) return null;
  return (mode: mode, start: start, end: end, dailyStart: null, dailyEnd: null);
}

void main(List<String> args) {
  final parsed = parseArgs(args);
  if (parsed == null) {
    stderr.writeln(
      'probe_convergence: usage: dart run tool/probe_convergence.dart '
      '[mapping|map [<start> [<end>]]] | digests | '
      'daily [<yyyy-mm-dd> [<yyyy-mm-dd>]] | check',
    );
    // Usage error — the tool/flutter_test_lock.dart convention.
    exitCode = 2;
    return;
  }
  switch (parsed.mode) {
    case ProbeMode.mapping:
      stdout.writeln(
        formatRows(measureMapping(start: parsed.start, end: parsed.end)),
      );
    case ProbeMode.map:
      _printMapMode(start: parsed.start, end: parsed.end);
    case ProbeMode.digests:
      _printDigestsMode();
    case ProbeMode.daily:
      _printDailyMode(start: parsed.dailyStart, end: parsed.dailyEnd);
    case ProbeMode.check:
      _printCheckMode();
  }
}

/// A golden-file read that degrades to the usage-error exit — the digest
/// modes' only environmental failure (run from the repo root).
List<GoldenEntry>? readGoldenOrExit() {
  try {
    return readGoldenEntries(goldenFileDefault);
  } on FileSystemException {
    stderr.writeln(
      'probe_convergence: golden file not readable: $goldenFileDefault '
      '(run from the repo root)',
    );
    exitCode = 2;
    return null;
  }
}

void _printMapMode({required int start, required int end}) {
  final mapping = measureMapping(start: start, end: end);
  for (final entry in mapping.entries) {
    final exhausted = entry.value.keys.where(
      (seed) => entry.value[seed] == null,
    );
    for (final seed in exhausted) {
      stderr.writeln('${entry.key} $seed exhausts within the widened budget');
    }
  }
  stdout.writeln(formatMapLiteral(mapping));
}

void _printDigestsMode() {
  final entries = readGoldenOrExit();
  if (entries == null) return;
  final resolved = <({GoldenEntry entry, String digest})>[];
  for (final entry in entries) {
    final digest = digestFor(entry.difficulty, entry.seed);
    if (digest == null) {
      stderr.writeln('exhausts ${entry.key}');
      continue;
    }
    if (digest != entry.committed) {
      stderr.writeln(
        'drift ${entry.key} live=$digest committed=${entry.committed}',
      );
    }
    resolved.add((entry: entry, digest: digest));
  }
  stdout.writeln(formatDigestsLiteral(resolved));
}

void _printDailyMode({required DateTime? start, required DateTime? end}) {
  List<({String date, int seed, String? digest})>? rows;
  if (start != null) {
    rows = dailyRows(start: start, end: end);
  } else {
    final entries = readGoldenOrExit();
    if (entries == null) return;
    rows = dailyRows(fromGolden: entries);
  }
  stdout.writeln(formatDailyRows(rows));
}

void _printCheckMode() {
  final entries = readGoldenOrExit();
  if (entries == null) return;
  final report = checkGoldenEntries(entries);
  for (final line in report.ok) {
    stdout.writeln(line);
  }
  for (final line in report.drifted) {
    stdout.writeln(line);
  }
  for (final line in report.exhausts) {
    stdout.writeln(line);
  }
  if (report.drifted.isNotEmpty || report.exhausts.isNotEmpty) {
    // Verification failure, not a usage error: exit 1 like a failing check.
    exitCode = 1;
  }
}
