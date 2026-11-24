/// lcov post-processor that drops excluded directories from a coverage
/// report (issue #37) and normalizes the section order of its output
/// (issue #53).
///
/// `flutter test --coverage` cannot filter source paths, and the generated
/// localization code under `lib/l10n/generated/**` jitters its lcov hit
/// counts between consecutive runs of identical code (observed during #33:
/// `DA:148` / `DA:150` in `app_localizations_ru.dart` flipped 1↔0), which
/// makes coverage output non-byte-deterministic. This tool rewrites the
/// lcov report in place, removing every `SF:…end_of_record` section whose
/// `SF:` path lives under `lib/l10n/`. Because the upstream writer's
/// `SF:`-section order also jitters between runs (observed during #37:
/// only SF-section reordering between two identical runs), the kept
/// sections are additionally re-emitted sorted by `SF:` path — preamble
/// bytes keep their relative order — so the whole filtered report hashes
/// stably. The CRAP gate (`tool/crap_check.dart`) already skips generated
/// paths itself, so neither behavior changes gate output.
library;

import 'dart:io';

/// lcov sections whose `SF:` path starts with one of these directories are
/// removed. Trailing slash required: matching is on directory boundaries,
/// so `lib/l10next/` is not excluded.
const List<String> coverageExcludePrefixes = ['lib/l10n/'];

/// True when [path] is inside an excluded directory: compared after
/// normalizing `\` to `/`, as a relative prefix or contained after any
/// `/` boundary (absolute lcov paths).
bool isExcludedPath(String path) {
  final p = path.replaceAll('\\', '/');
  for (final prefix in coverageExcludePrefixes) {
    if (p.startsWith(prefix) || p.contains('/$prefix')) return true;
  }
  return false;
}

/// Filters [lcov]: drops every section (`SF:` through `end_of_record`,
/// or through end-of-input when truncated) whose `SF:` path satisfies
/// [isExcludedPath], and re-emits the kept sections sorted by `SF:` path
/// (issue #53). Lines outside any `SF:` section keep their relative
/// order and stay in front of the sorted sections — including lines
/// sitting between records, which are hoisted to that preamble, so
/// tracefiles with inter-record data (e.g. genhtml-style `TN:`/`BRF:`
/// blocks) must be pre-stripped to preserve their per-record placement.
String filterLcov(String lcov) => filterLcovWithDropped(lcov).$1;

/// Same filtering and SF-path sorting as [filterLcov], additionally
/// returning the number of dropped `SF:` sections (per section, not per
/// line).
(String, int) filterLcovWithDropped(String lcov) {
  final endsWithNewline = lcov.endsWith('\n');
  final lines = lcov.split('\n');
  if (endsWithNewline && lines.isNotEmpty) lines.removeLast();

  // Preamble: lines outside any `SF:` section, in relative order. A
  // truncated kept section (no `end_of_record`) is closed implicitly by
  // the next `SF:` or end-of-input and stays kept, as before.
  final preamble = <String>[];
  final records = <(String, List<String>)>[];
  List<String>? current;
  var sfPath = '';
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      if (current != null) records.add((sfPath, current));
      sfPath = line.substring(3);
      current = <String>[line];
    } else if (current != null) {
      current.add(line);
      if (line == 'end_of_record') {
        records.add((sfPath, current));
        current = null;
      }
    } else {
      preamble.add(line);
    }
  }
  if (current != null) records.add((sfPath, current));

  final kept = records.where((r) => !isExcludedPath(r.$1)).toList()
    ..sort((a, b) {
      final byPath = a.$1.compareTo(b.$1);
      if (byPath != 0) return byPath;
      // Duplicate SF paths cannot occur in a valid report; the
      // tie-break just makes the sort a total order.
      return a.$2.join('\n').compareTo(b.$2.join('\n'));
    });
  final dropped = records.length - kept.length;

  final out = <String>[];
  out.addAll(preamble);
  for (final record in kept) {
    out.addAll(record.$2);
  }
  var text = out.join('\n');
  if (out.isNotEmpty && endsWithNewline) text += '\n';
  return (text, dropped);
}

void main(List<String> args) {
  var lcovPath = 'coverage/lcov.info';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--lcov') {
      if (i + 1 >= args.length) {
        stderr.writeln('coverage_filter: --lcov expects a value');
        exitCode = 1;
        return;
      }
      lcovPath = args[++i];
      continue;
    }
    stderr.writeln('coverage_filter: unknown argument "$arg"');
    exitCode = 1;
    return;
  }

  final file = File(lcovPath);
  if (!file.existsSync()) {
    stderr.writeln(
      'coverage_filter: no lcov report at $lcovPath — '
      'run `flutter test --coverage` first',
    );
    exitCode = 1;
    return;
  }
  final original = file.readAsStringSync();
  final (filtered, dropped) = filterLcovWithDropped(original);
  final kept = 'SF:'.allMatches(filtered).length;
  if (filtered != original) file.writeAsStringSync(filtered);
  stdout.writeln(
    'coverage_filter: dropped $dropped section(s), kept $kept '
    '(SF-sorted) in $lcovPath',
  );
}
