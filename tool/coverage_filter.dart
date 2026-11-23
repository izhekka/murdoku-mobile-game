/// lcov post-processor that drops excluded directories from a coverage
/// report (issue #37).
///
/// `flutter test --coverage` cannot filter source paths, and the generated
/// localization code under `lib/l10n/generated/**` jitters its lcov hit
/// counts between consecutive runs of identical code (observed during #33:
/// `DA:148` / `DA:150` in `app_localizations_ru.dart` flipped 1↔0), which
/// makes coverage output non-byte-deterministic. This tool rewrites the
/// lcov report in place, removing every `SF:…end_of_record` section whose
/// `SF:` path lives under `lib/l10n/`. The CRAP gate
/// (`tool/crap_check.dart`) already skips generated paths itself, so the
/// removal does not change gate behavior.
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
/// [isExcludedPath]. Kept bytes — preamble, neighbor sections, trailing
/// newline — are byte-identical to the input.
String filterLcov(String lcov) => filterLcovWithDropped(lcov).$1;

/// Same filtering as [filterLcov], additionally returning the number of
/// dropped `SF:` sections (per section, not per line).
(String, int) filterLcovWithDropped(String lcov) {
  final lines = lcov.split('\n');
  final out = <String>[];
  String? currentSf;
  var dropping = false;
  var dropped = 0;
  var lastKeptIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('SF:')) {
      currentSf = line.substring(3);
      dropping = isExcludedPath(currentSf);
      if (dropping) dropped++;
      if (!dropping) {
        out.add(line);
        lastKeptIndex = i;
      }
      continue;
    }
    if (line == 'end_of_record') {
      final hasOpenSection = currentSf != null;
      currentSf = null;
      if (hasOpenSection && dropping) continue;
    } else if (currentSf != null && dropping) {
      continue;
    }
    out.add(line);
    lastKeptIndex = i;
  }
  // `split('\n')`/`join('\n')` reproduction is byte-exact except for the
  // terminator of the last kept element when everything after it is
  // dropped — `join` only emits separators between kept elements, so that
  // trailing '\n' must be restored explicitly.
  var text = out.join('\n');
  if (lastKeptIndex != -1 && lastKeptIndex < lines.length - 1) text += '\n';
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
    'coverage_filter: dropped $dropped section(s), kept $kept in $lcovPath',
  );
}
