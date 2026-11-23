/// CRAP-index ratchet gate for Murdoku.
///
/// Hand-rolled quality gate (issue #33, decision record 0006): computes the
/// change-risk-per-method "CRAP" index from per-method cyclomatic complexity
/// and per-method test coverage, then enforces a ratchet against a committed
/// baseline so complexity-vs-coverage cannot silently regress.
///
/// - Complexity = 1 + decision points: `if` (statements and collection
///   elements), `for` (statements and elements), `while`, `do`, statement
///   `case` clauses, expression-switch arms with a pattern (`_` wildcard and
///   `default` are not decisions), `catch` clauses, `&&`, `||`, `?:`, `??`.
///   Nested closures and local functions roll into their enclosing member.
/// - Coverage per method comes from lcov `DA` records inside the member's
///   line span (`flutter test --coverage`); missing data means 0.
/// - CRAP = comp^2 * (1-cov)^3 + comp.
/// - No committed baseline anymore (issue 35): the gate is hard at
///   threshold 5. A baseline file is optional (see [loadBaseline]) —
///   present, it keeps the old ratchet semantics; absent, every
///   over-threshold member fails the run.
///
/// Scope: `lib/**` only, skipping `lib/l10n/generated/**` — `test/`, `tool/`
/// and `integration_test/` are formatted and linted but yield no coverage
/// data, so they are never measured.
///
/// Known limitations of this hand-rolled gate (documented on purpose):
/// decision points in top-level/field initializers and in `&&`/`||` inside
/// patterns are not counted.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// One measured method: span and cyclomatic complexity.
class MemberMetric {
  const MemberMetric({
    required this.file,
    required this.member,
    required this.startLine,
    required this.endLine,
    required this.complexity,
  });

  final String file;
  final String member;
  final int startLine;
  final int endLine;
  final int complexity;

  @override
  String toString() => '$file $member($startLine-$endLine) comp=$complexity';
}

/// Computes one [MemberMetric] per declared function-like member of [source]:
/// top-level functions; class/mixin/enum/extension methods, getters, setters
/// and constructors. Nested local functions and closures count into their
/// enclosing member (no separate entry). Duplicated member names in one file
/// are disambiguated with a `#2`, `#3`, ... suffix in declaration order.
List<MemberMetric> computeMetrics(String file, String source) {
  final result = parseString(content: source);
  final collector = _MemberCollector(lineInfo: result.lineInfo);
  result.unit.accept(collector);
  final seen = <String, int>{};
  return [
    for (final collected in collector.members)
      _buildMetric(
        file,
        collected,
        seen,
        _ComplexityVisitor()..visitCollected(collected),
      ),
  ];
}

MemberMetric _buildMetric(
  String file,
  _Collected collected,
  Map<String, int> seen,
  _ComplexityVisitor visitor,
) {
  final count = seen[collected.name] ?? 0;
  seen[collected.name] = count + 1;
  final memberName = count == 0
      ? collected.name
      : '${collected.name}#${count + 1}';
  final node = collected.node;
  final startLine = collected.lineInfo
      .getLocation(node.beginToken.offset)
      .lineNumber;
  final endLine = collected.lineInfo.getLocation(node.end - 1).lineNumber;
  return MemberMetric(
    file: file,
    member: memberName,
    startLine: startLine,
    endLine: endLine,
    complexity: visitor.complexity,
  );
}

/// True when [path] is inside the CRAP scope: `lib/**` Dart files minus the
/// generated localization code.
bool shouldMeasure(String path) {
  final p = path.replaceAll('\\', '/');
  if (!p.endsWith('.dart')) return false;
  if (!p.startsWith('lib/')) return false;
  return !p.startsWith('lib/l10n/generated/');
}

/// Coverage data parsed from an lcov report.
class LcovData {
  LcovData._(this._files);

  final Map<String, Map<int, int>> _files;

  /// Parses lcov text. Tolerates foreign records (`TN:`, `FN:`, `BRDA:`, ...)
  /// and empty input.
  static LcovData parse(String text) {
    final files = <String, Map<int, int>>{};
    String? current;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('SF:')) {
        current = line.substring(3).replaceAll('\\', '/');
        files[current] = <int, int>{};
      } else if (line.startsWith('DA:') && current != null) {
        final parts = line.substring(3).split(',');
        final lineNo = parts.isNotEmpty ? int.tryParse(parts[0].trim()) : null;
        final hits = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
        if (lineNo != null && hits != null) {
          files[current]![lineNo] = hits;
        }
      } else if (line.startsWith('end_of_record')) {
        current = null;
      }
    }
    return LcovData._(files);
  }

  /// Hit DA lines divided by instrumented DA lines within the inclusive span
  /// [startLine, endLine]. Missing file or span data means 0.0. SF paths match
  /// exactly or by `/`-separated suffix.
  double coverageFor(String file, int startLine, int endLine) {
    final da = _resolve(file);
    if (da == null) return 0.0;
    var total = 0;
    var hits = 0;
    for (final entry in da.entries) {
      if (entry.key >= startLine && entry.key <= endLine) {
        total++;
        if (entry.value > 0) hits++;
      }
    }
    if (total == 0) return 0.0;
    return hits / total;
  }

  Map<int, int>? _resolve(String file) {
    final direct = _files[file.replaceAll('\\', '/')];
    if (direct != null) return direct;
    for (final entry in _files.entries) {
      if (entry.key.endsWith('/$file')) return entry.value;
    }
    return null;
  }
}

/// CRAP index: `comp^2 * (1-cov)^3 + comp`.
double crapFor(int complexity, double coverage) {
  final miss = (1.0 - coverage).clamp(0.0, 1.0).toDouble();
  return complexity * complexity * miss * miss * miss + complexity;
}

/// Separator between file and member inside baseline keys: `<file>::<member>`.
const String entryKeySeparator = '::';

/// One ratchet-checked method with its current CRAP value.
class Entry {
  const Entry({required this.file, required this.member, required this.crap});

  final String file;
  final String member;
  final double crap;

  String get key => '$file$entryKeySeparator$member';
}

int _entryCompare(Entry a, Entry b) {
  final byFile = a.file.compareTo(b.file);
  return byFile != 0 ? byFile : a.member.compareTo(b.member);
}

/// Loads the ratchet baseline at [path]. A missing file means an empty
/// baseline: the gate runs hard with no escape hatch — every over-threshold
/// member is a new violation (issue 35).
Baseline loadBaseline(String path, int threshold) {
  final file = File(path);
  if (!file.existsSync()) {
    return Baseline(threshold: threshold, entries: const {});
  }
  return Baseline.parse(file.readAsStringSync());
}

/// Rounding used everywhere CRAP values are stored or compared, so the gate
/// is byte-stable and float-jitter-free.
double round4(double value) => (value * 10000).round() / 10000;

/// Measures every file in [files] (relative path -> source) against [lcov]
/// (null means zero coverage). Returns one [Entry] per member — ALL members,
/// not only violations — sorted by file then member, crap rounded to 4 dp.
List<Entry> collectEntries(Map<String, String> files, LcovData? lcov) {
  final entries = <Entry>[];
  for (final file in files.keys.toList()..sort()) {
    for (final metric in computeMetrics(file, files[file]!)) {
      final coverage =
          lcov?.coverageFor(metric.file, metric.startLine, metric.endLine) ??
          0.0;
      entries.add(
        Entry(
          file: metric.file,
          member: metric.member,
          crap: round4(crapFor(metric.complexity, coverage)),
        ),
      );
    }
  }
  return entries..sort(_entryCompare);
}

/// Outcome of one gate run.
class GateResult {
  const GateResult({
    required this.newViolations,
    required this.worsenedViolations,
    required this.improved,
  });

  /// Violations absent from the baseline, e.g. `lib/foo.dart::Foo.bar: crap=12.5 (new)`.
  final List<String> newViolations;

  /// Violations whose CRAP increased above the baseline value.
  final List<String> worsenedViolations;

  /// Baseline keys that are now clean or lower — the operator is hinted to
  /// refresh the baseline.
  final List<String> improved;

  /// The gate passes (exit 0) when there are no new or worsened violations.
  bool get passes => newViolations.isEmpty && worsenedViolations.isEmpty;
}

/// Ratchet comparison: violations are entries with `crap > threshold`; a
/// violation fails the gate when its key is new or its value increased.
/// Baseline keys that improved only produce a refresh hint.
GateResult evaluateGate({
  required List<Entry> current,
  required Baseline baseline,
  required int threshold,
}) {
  final violations = [
    for (final e in current)
      if (e.crap > threshold) e,
  ];
  final currentCrap = <String, double>{};
  final newViolations = <String>[];
  final worsenedViolations = <String>[];
  for (final violation in violations) {
    currentCrap[violation.key] = violation.crap;
    final baselineCrap = baseline.entries[violation.key];
    if (baselineCrap == null) {
      newViolations.add('${violation.key}: crap=${violation.crap} (new)');
    } else if (violation.crap > baselineCrap) {
      worsenedViolations.add(
        '${violation.key}: crap=${violation.crap} (baseline $baselineCrap)',
      );
    }
  }
  final improved = [
    for (final key in baseline.entries.keys)
      if (currentCrap[key] == null ||
          currentCrap[key]! < baseline.entries[key]!)
        key,
  ];
  return GateResult(
    newViolations: newViolations,
    worsenedViolations: worsenedViolations,
    improved: improved,
  );
}

/// The committed ratchet state: threshold used to produce it and the
/// previously accepted over-threshold entries.
class Baseline {
  const Baseline({required this.threshold, required this.entries});

  final int threshold;

  /// `<file>::<member>` -> CRAP value.
  final Map<String, double> entries;

  static Baseline parse(String json) {
    final decoded = jsonDecode(json) as Map<String, Object?>;
    final threshold = (decoded['threshold'] as num).toInt();
    final rawEntries = decoded['entries'] as List<Object?>;
    final entries = <String, double>{};
    for (final item in rawEntries) {
      final map = item as Map<String, Object?>;
      final file = map['file'] as String;
      final member = map['member'] as String;
      final crap = (map['crap'] as num).toDouble();
      entries['$file$entryKeySeparator$member'] = crap;
    }
    return Baseline(threshold: threshold, entries: entries);
  }
}

/// Encodes the baseline JSON deterministically: entries sorted by file then
/// member, fixed key order, crap rounded to 4 dp, single trailing newline.
/// Byte-stable across runs.
String encodeBaseline(List<Entry> entries, int threshold) {
  final sorted = [...entries]..sort(_entryCompare);
  final json = jsonEncode({
    'threshold': threshold,
    'entries': [
      for (final e in sorted)
        {'file': e.file, 'member': e.member, 'crap': round4(e.crap)},
    ],
  });
  return '$json\n';
}

class _Collected {
  const _Collected(this.name, this.node, this.lineInfo);

  final String name;
  final AstNode node;
  final LineInfo lineInfo;
}

/// Walks the compilation unit and collects declared members in source order.
class _MemberCollector extends RecursiveAstVisitor<void> {
  _MemberCollector({required this.lineInfo});

  final LineInfo lineInfo;
  final List<_Collected> members = [];
  String? _typeName;
  int _anonymousExtensions = 0;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    members.add(_Collected(node.name.lexeme, node, lineInfo));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _withType(
      node.namePart.typeName.lexeme,
      () => super.visitClassDeclaration(node),
    );
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _withType(node.name.lexeme, () => super.visitMixinDeclaration(node));
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _withType(
      node.namePart.typeName.lexeme,
      () => super.visitEnumDeclaration(node),
    );
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final name = node.name?.lexeme;
    final label = name ?? '<anonymous-extension-${_anonymousExtensions++}>';
    _withType(label, () => super.visitExtensionDeclaration(node));
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _withType(
      node.namePart.typeName.lexeme,
      () => super.visitExtensionTypeDeclaration(node),
    );
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    members.add(_Collected('$_typeName.${node.name.lexeme}', node, lineInfo));
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final ctorName = node.name?.lexeme;
    members.add(
      _Collected(
        ctorName == null ? '$_typeName' : '$_typeName.$ctorName',
        node,
        lineInfo,
      ),
    );
    super.visitConstructorDeclaration(node);
  }

  void _withType(String name, void Function() visit) {
    final previous = _typeName;
    _typeName = name;
    visit();
    _typeName = previous;
  }
}

/// Counts decision points inside one member.
class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  int complexity = 1;

  void visitCollected(_Collected collected) {
    collected.node.accept(this);
  }

  void _bump() => complexity++;

  @override
  void visitIfStatement(IfStatement node) {
    _bump();
    super.visitIfStatement(node);
  }

  @override
  void visitIfElement(IfElement node) {
    _bump();
    super.visitIfElement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    _bump();
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    _bump();
    super.visitForElement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _bump();
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    _bump();
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    _bump();
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    _bump();
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    if (node.guardedPattern.pattern is! WildcardPattern) _bump();
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    _bump();
    super.visitCatchClause(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final type = node.operator.type;
    if (type == TokenType.AMPERSAND_AMPERSAND ||
        type == TokenType.BAR_BAR ||
        type == TokenType.QUESTION_QUESTION) {
      _bump();
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _bump();
    super.visitConditionalExpression(node);
  }
}

/// CLI: `dart run tool/crap_check.dart [--lcov <path>] [--threshold <n>]
/// [--baseline <path>] [--update-baseline]`.
///
/// Defaults: `coverage/lcov.info`, threshold 5, `tool/crap_baseline.json`.
/// The committed baseline was removed with issue 35 — the gate is hard.
/// `--update-baseline` writes the current over-threshold members as a
/// (local, uncommitted) ratchet state; otherwise the gate runs and exits 0
/// when no member is over threshold beyond the baseline state, 1 on
/// new/worsened violations (or unusable input).
void main(List<String> args) {
  var lcovPath = 'coverage/lcov.info';
  var threshold = 5;
  var baselinePath = 'tool/crap_baseline.json';
  var updateBaseline = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--update-baseline') {
      updateBaseline = true;
      continue;
    }
    if (arg == '--lcov' || arg == '--threshold' || arg == '--baseline') {
      if (i + 1 >= args.length) {
        stderr.writeln('crap_check: $arg expects a value');
        exitCode = 1;
        return;
      }
      final value = args[++i];
      if (arg == '--lcov') {
        lcovPath = value;
      } else if (arg == '--baseline') {
        baselinePath = value;
      } else {
        final parsed = int.tryParse(value);
        if (parsed == null || parsed < 0) {
          stderr.writeln(
            'crap_check: --threshold expects a non-negative integer, got "$value"',
          );
          exitCode = 1;
          return;
        }
        threshold = parsed;
      }
      continue;
    }
    stderr.writeln('crap_check: unknown argument "$arg"');
    exitCode = 1;
    return;
  }

  final sources = _readLibSources();
  if (sources.isEmpty) {
    stderr.writeln(
      'crap_check: no lib/**/*.dart sources found — run from the package root',
    );
    exitCode = 1;
    return;
  }

  final lcovFile = File(lcovPath);
  final lcov = lcovFile.existsSync()
      ? LcovData.parse(lcovFile.readAsStringSync())
      : null;
  final entries = collectEntries(sources, lcov);

  if (updateBaseline) {
    final violations = [
      for (final e in entries)
        if (e.crap > threshold) e,
    ];
    File(baselinePath).writeAsStringSync(encodeBaseline(violations, threshold));
    stdout.writeln(
      'crap_check: baseline written to $baselinePath '
      '(${violations.length} over-threshold members, threshold $threshold)',
    );
    return;
  }

  final baseline = loadBaseline(baselinePath, threshold);
  if (baseline.entries.isEmpty) {
    stdout.writeln(
      'crap_check: no baseline at $baselinePath — the gate runs hard',
    );
  }
  final result = evaluateGate(
    current: entries,
    baseline: baseline,
    threshold: threshold,
  );

  for (final line in result.newViolations) {
    stdout.writeln('OVER   $line');
  }
  for (final line in result.worsenedViolations) {
    stdout.writeln('OVER   $line');
  }
  for (final key in result.improved) {
    stdout.writeln(
      'HINT   $key improved — refresh the baseline with --update-baseline',
    );
  }
  final violationCount =
      result.newViolations.length + result.worsenedViolations.length;
  stdout.writeln(
    'crap_check: ${entries.length} members measured, threshold $threshold, '
    '$violationCount violation(s), ${result.improved.length} improved',
  );
  if (!result.passes) {
    stderr.writeln('crap_check: CRAP ratchet failed');
    exitCode = 1;
  }
}

/// Reads `lib/**` from the current directory, keeping only paths accepted by
/// [shouldMeasure].
Map<String, String> _readLibSources() {
  final sources = <String, String>{};
  final libDir = Directory('lib');
  if (!libDir.existsSync()) return sources;
  final entities = libDir.listSync(recursive: true, followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entities) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (!shouldMeasure(path)) continue;
    sources[path] = entity.readAsStringSync();
  }
  return sources;
}
