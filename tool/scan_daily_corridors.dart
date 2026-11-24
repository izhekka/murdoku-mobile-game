/// Corridor scan for the daily date-seed path (issue #71): re-derives the
/// budget-exhaustion corridor evidence pinned in test/state/daily_test.dart
/// (issues 60/61) — the UTC date-seeds whose bare `generateCase` exhausts the
/// whole widened budget, and the stride seed where `generateCaseWithRecovery`
/// lands instead.
///
/// Run: `dart run tool/scan_daily_corridors.dart [<yyyy-from> <yyyy-to>] [--all]`
/// - default sweep: 2019–2060 (15,341 valid UTC dates) at standard
///   difficulty, ~3–4 minutes as measured;
/// - default output prints only the corridor rows plus a summary line;
///   `--all` prints one row per scanned date;
/// - usage errors exit 2 — the tool/flutter_test_lock.dart convention.
///
/// MANUAL INVOCATION ONLY — NEVER from `make quality` or CI: a minutes-long
/// generator sweep must not gate every commit.
library;

import 'dart:io';

import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

/// Recovery stride between windows. Copy of case_factory's private
/// `_retryBudget` (issue 45): if the factory ever changes it, this copy and
/// the corridor pins go stale together — pinned by the scan test, which ties
/// the recovered stride to `generateCaseWithRecovery`'s result byte-for-byte.
const stride = 40;

/// Extra recovery windows past the exhausted one. Copy of case_factory's
/// private `_recoveredWindows` (issue 45): the loop below mirrors
/// `generateCaseWithRecovery`'s `window <= recoveryWindows` semantics.
const recoveryWindows = 8;

/// One scanned date: the daily seed and how bare generation resolved.
class CorridorOutcome {
  const CorridorOutcome({
    required this.date,
    required this.seed,
    required this.recoveredStride,
    required this.recoveryExhausted,
  });

  /// The scanned UTC date (midnight).
  final DateTime date;

  /// `dailySeedFor(date)` — the bare `generateCase` input.
  final int seed;

  /// The stride seed the recovery found (`seed + window * stride`), or null
  /// when bare generation succeeded directly.
  final int? recoveredStride;

  /// True when the recovery loop itself exhausted every window (no unique
  /// case at all) — never observed so far.
  final bool recoveryExhausted;

  bool get isCorridor => recoveredStride != null || recoveryExhausted;
}

/// yyyy-mm-dd (UTC), the daily identity format of formatUtcDate (the tool
/// cannot import state/clock.dart: it drags flutter_riverpod into a plain
/// `dart run`).
String formatDate(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

/// Scans one date: bare `generateCase`, and on budget exhaust the recovery
/// stride loop mirroring `generateCaseWithRecovery` — first succeeding
/// `seed + window * stride` wins, all-windows-exhaust marks [CorridorOutcome.
/// recoveryExhausted].
CorridorOutcome scanDate(DateTime utcDate) {
  final seed = dailySeedFor(utcDate);
  int? recoveredStride;
  var recoveryExhausted = false;
  try {
    generateCase(difficulty: Difficulty.standard, seed: seed);
  } on StateError {
    for (var window = 0; window <= recoveryWindows; window++) {
      final attemptSeed = seed + window * stride;
      try {
        generateCase(difficulty: Difficulty.standard, seed: attemptSeed);
        recoveredStride = attemptSeed;
        break;
      } on StateError {
        if (window == recoveryWindows) recoveryExhausted = true;
      }
    }
  }
  return CorridorOutcome(
    date: utcDate,
    seed: seed,
    recoveredStride: recoveredStride,
    recoveryExhausted: recoveryExhausted,
  );
}

/// Scans every valid UTC date in the inclusive [fromUtc, toUtc] window in
/// ascending order — month lengths via `DateTime.utc(y, m + 1, 0).day`.
List<CorridorOutcome> scanDates(DateTime fromUtc, DateTime toUtc) {
  final rows = <CorridorOutcome>[];
  for (var year = fromUtc.year; year <= toUtc.year; year++) {
    for (var month = 1; month <= 12; month++) {
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      for (var day = 1; day <= lastDay; day++) {
        final date = DateTime.utc(year, month, day);
        if (date.isBefore(fromUtc) || date.isAfter(toUtc)) continue;
        rows.add(scanDate(date));
      }
    }
  }
  return rows;
}

/// Parsed CLI usage: inclusive year range plus the `--all` row-per-date
/// flag. Zero args default to the 2019–2060 sweep; a lone year narrows
/// within it (the end stays 2060 — the probe_convergence convention).
/// Returns null on any malformed usage: non-integer or negative year,
/// inverted range, more than two years, or an unknown flag.
({int from, int to, bool all})? parseArgs(List<String> args) {
  var from = 2019;
  var to = 2060;
  var all = false;
  final years = <int>[];
  for (final arg in args) {
    if (arg == '--all') {
      all = true;
    } else {
      final year = int.tryParse(arg);
      if (year == null || year < 0) return null;
      years.add(year);
    }
  }
  if (years.length > 2) return null;
  if (years.isNotEmpty) {
    from = years.first;
    if (years.length > 1) to = years.last;
  }
  if (from > to) return null;
  return (from: from, to: to, all: all);
}

/// One line per corridor row (bare exhaust): the recovery landing or the
/// all-windows-exhaust marker. Non-corridor rows stay out — the full
/// date surface is [formatDateRows].
String formatCorridorRows(List<CorridorOutcome> rows) =>
    rows.where((row) => row.isCorridor).map(_rowText).join('\n');

/// One line per scanned date, ascending: `-> ok` or the corridor text.
String formatDateRows(List<CorridorOutcome> rows) =>
    rows.map(_rowText).join('\n');

String _rowText(CorridorOutcome row) {
  final dateAndSeed = '${formatDate(row.date)} ${row.seed}';
  if (!row.isCorridor) return '$dateAndSeed -> ok';
  return row.recoveredStride == null
      ? '$dateAndSeed -> exhausts, recovery exhausted'
      : '$dateAndSeed -> exhausts, recovers at ${row.recoveredStride}';
}

/// The tail summary: scanned count, ok / corridor / unrecovered splits.
String formatSummary(List<CorridorOutcome> rows, int from, int to) {
  final corridor = rows.where((r) => r.isCorridor).length;
  final unrecovered = rows.where((r) => r.recoveryExhausted).length;
  return 'scanned ${rows.length} UTC dates $from-$to: '
      'ok=${rows.length - corridor}, corridor=$corridor, '
      'unrecovered=$unrecovered';
}

void main(List<String> args) {
  final parsed = parseArgs(args);
  if (parsed == null) {
    stderr.writeln(
      'scan_daily_corridors: usage: dart run tool/scan_daily_corridors.dart '
      '[<yyyy-from> <yyyy-to>] [--all]',
    );
    // Usage error — the tool/flutter_test_lock.dart convention.
    exitCode = 2;
    return;
  }
  final rows = scanDates(
    DateTime.utc(parsed.from),
    DateTime.utc(parsed.to, 12, 31),
  );
  final rowsText = parsed.all ? formatDateRows(rows) : formatCorridorRows(rows);
  if (rowsText.isNotEmpty) stdout.writeln(rowsText);
  stdout.writeln(formatSummary(rows, parsed.from, parsed.to));
}
