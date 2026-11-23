import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/crap_check.dart';

Entry entry(String file, String member, double crap) =>
    Entry(file: file, member: member, crap: crap);

Baseline baselineFrom(List<Entry> entries) =>
    Baseline.parse(encodeBaseline(entries, 5));

void main() {
  group('computeMetrics', () {
    test('complexity counts each decision node once', () {
      final src = r'''
String f(int x, bool a, bool b, List<int> xs, int y) {
  final sb = StringBuffer();
  if (x == 1) {
    sb.write('1');
  } else if (x == 2) {
    sb.write('2');
  }
  for (final i in xs) {
    sb.write(i);
  }
  while (a) {
    break;
  }
  do {
    x--;
  } while (x > 0);
  if (a && b) {
    sb.write('ab');
  }
  if (a || b) {
    sb.write('or');
  }
  sb.write(x > 0 ? 'p' : 'n');
  sb.write(y ?? 0);
  final parts = [if (a) 'a', for (final i in xs) '$i'];
  sb.write(parts.join());
  try {
    sb.write('t');
  } on StateError catch (e) {
    sb.write(e);
  } catch (e) {
    sb.write(e);
  }
  return sb.toString();
}
''';
      final metrics = computeMetrics('lib/t.dart', src);
      expect(metrics, hasLength(1));
      expect(metrics.single.file, 'lib/t.dart');
      expect(metrics.single.member, 'f');
      expect(metrics.single.startLine, 1);
      // 1 base + 2 if + for + while + do + if + && + if + || + ?: + ?? +
      // if-element + for-element + 2 catch clauses = 16.
      expect(metrics.single.complexity, 16);
    });

    test('switch cases count, default and wildcard do not', () {
      final src = r'''
String sw(int x) {
  switch (x) {
    case 1:
      return 'a';
    case 2:
      return 'b';
    default:
      return 'c';
  }
}

String swExpr(int x) {
  return switch (x) {
    1 => 'a',
    2 => 'b',
    _ => 'c',
  };
}
''';
      final metrics = computeMetrics('lib/t.dart', src);
      final byName = {for (final m in metrics) m.member: m.complexity};
      // 1 base + 2 statement cases; default is not a decision.
      expect(byName['sw'], 3);
      // 1 base + 2 expression arms; the `_` wildcard arm is not a decision.
      expect(byName['swExpr'], 3);
    });

    test('nested closures roll into the enclosing member', () {
      final src = r'''
class C {
  void m(bool a, bool b) {
    final cb = () {
      if (a) return;
      if (b) return;
    };
    cb();
  }
}
''';
      final metrics = computeMetrics('lib/t.dart', src);
      expect(metrics, hasLength(1));
      expect(metrics.single.member, 'C.m');
      expect(metrics.single.complexity, 3);
    });

    test(
      'member naming covers constructors, getters and top-level functions',
      () {
        final src = r'''
class Foo {
  Foo();
  Foo.named();
  bool get bar => true;
  void baz() {}
}

void topFn() {}
''';
        final metrics = computeMetrics('lib/t.dart', src);
        expect(
          metrics.map((m) => m.member),
          unorderedEquals(['Foo', 'Foo.named', 'Foo.bar', 'Foo.baz', 'topFn']),
        );
        for (final m in metrics) {
          expect(m.complexity, 1, reason: '${m.member} has no decisions');
        }
      },
    );

    test('duplicate member names are disambiguated in declaration order', () {
      final src = r'''
class D {
  void dup() {}
  void dup() {}
}
''';
      final metrics = computeMetrics('lib/t.dart', src);
      expect(metrics.map((m) => m.member).toList(), ['D.dup', 'D.dup#2']);
    });
  });

  group('LcovData', () {
    test('coverage within a member span', () {
      final lcov = LcovData.parse(
        'SF:lib/t.dart\nDA:2,1\nDA:3,0\nDA:5,1\nend_of_record\n',
      );
      expect(lcov.coverageFor('lib/t.dart', 2, 5), closeTo(2 / 3, 1e-9));
      expect(lcov.coverageFor('lib/t.dart', 6, 9), 0.0);
    });

    test('SF paths match by suffix', () {
      final lcov = LcovData.parse(
        'SF:/abs/repo/lib/t.dart\nDA:1,1\nDA:2,0\nend_of_record\n',
      );
      expect(lcov.coverageFor('lib/t.dart', 1, 2), closeTo(0.5, 1e-9));
    });

    test('tolerates foreign records and empty input', () {
      final lcov = LcovData.parse(
        'TN:tn\nSF:lib/t.dart\nFN:1,f\nFNDA:1,f\nBRDA:1,0,0,1\nDA:1,1\nend_of_record\n',
      );
      expect(lcov.coverageFor('lib/t.dart', 1, 1), 1.0);
      final empty = LcovData.parse('');
      expect(empty.coverageFor('lib/t.dart', 1, 9), 0.0);
    });
  });

  group('crapFor', () {
    test('implements comp^2 * (1-cov)^3 + comp', () {
      expect(crapFor(4, 1.0), 4.0);
      expect(crapFor(4, 0.0), 20.0);
      expect(crapFor(1, 0.0), 2.0);
      expect(crapFor(2, 0.5), 2.5);
    });
  });

  group('shouldMeasure', () {
    test('keeps lib dart files, drops generated and non-lib paths', () {
      expect(shouldMeasure('lib/x.dart'), isTrue);
      expect(shouldMeasure('lib/a/b.dart'), isTrue);
      expect(
        shouldMeasure('lib/l10n/generated/app_localizations.dart'),
        isFalse,
      );
      expect(shouldMeasure('test/x.dart'), isFalse);
      expect(shouldMeasure('tool/x.dart'), isFalse);
      expect(
        shouldMeasure('lib/l10n/generated/app_localizations_en.dart'),
        isFalse,
      );
    });
  });

  group('collectEntries', () {
    test('measures two files with mixed coverage', () {
      final srcA = r'''
class A {
  int m(int x) {
    if (x > 0) {
      return 1;
    }
    return 2;
  }
}
''';
      final srcB = r'''
int g(int x, int y) {
  if (x > 0) return 1;
  if (y > 0) return 2;
  if (x + y > 10) return 3;
  return 0;
}
''';
      final lcov = LcovData.parse(
        'SF:lib/a.dart\nDA:2,1\nDA:3,1\nDA:4,0\nDA:5,0\nend_of_record\n',
      );
      final entries = collectEntries({
        'lib/b.dart': srcB,
        'lib/a.dart': srcA,
      }, lcov);
      expect(
        entries.map((e) => '${e.file} ${e.member} ${e.crap}').toList(),
        // A.m: comp 2, cov 2/4 -> 4*0.125 + 2 = 2.5; g: comp 4, cov 0 -> 20.0.
        ['lib/a.dart A.m 2.5', 'lib/b.dart g 20.0'],
      );
    });

    test('null lcov means zero coverage everywhere', () {
      final srcC = r'''
void h(bool a) {
  if (a) print('x');
}
''';
      final entries = collectEntries({'lib/c.dart': srcC}, null);
      expect(entries.map((e) => '${e.file} ${e.member} ${e.crap}').toList(), [
        'lib/c.dart h 6.0',
      ]);
    });
  });

  group('evaluateGate', () {
    final violations = [
      entry('lib/a.dart', 'A.m', 12.0),
      entry('lib/b.dart', 'g', 20.0),
    ];

    test('passes on baseline state', () {
      final baseline = baselineFrom(violations);
      final result = evaluateGate(
        current: violations,
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isTrue);
      expect(result.newViolations, isEmpty);
      expect(result.worsenedViolations, isEmpty);
      expect(result.improved, isEmpty);
    });

    test('fails on a new over-threshold member', () {
      final baseline = baselineFrom(violations);
      final current = [...violations, entry('lib/c.dart', 'h', 72.0)];
      final result = evaluateGate(
        current: current,
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isFalse);
      expect(result.newViolations, hasLength(1));
      expect(result.newViolations.single, contains('lib/c.dart::h'));
    });

    test('fails on a worsened value', () {
      final baseline = baselineFrom(violations);
      final current = [
        entry('lib/a.dart', 'A.m', 13.0),
        entry('lib/b.dart', 'g', 20.0),
      ];
      final result = evaluateGate(
        current: current,
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isFalse);
      expect(result.worsenedViolations, hasLength(1));
      expect(result.worsenedViolations.single, contains('lib/a.dart::A.m'));
    });

    test('passes with an improvement hint when values drop or disappear', () {
      final baseline = baselineFrom(violations);
      final current = [entry('lib/a.dart', 'A.m', 11.0)];
      final result = evaluateGate(
        current: current,
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isTrue);
      expect(result.improved, hasLength(2));
    });

    test('treats under-threshold members as non-violations', () {
      final baseline = baselineFrom(violations);
      final current = [...violations, entry('lib/d.dart', 'k', 4.0)];
      final result = evaluateGate(
        current: current,
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isTrue);
      expect(result.newViolations, isEmpty);
    });
  });

  group('encodeBaseline', () {
    test('round-trip is sorted, deterministic and shape-stable', () {
      final entries = [
        entry('lib/b.dart', 'g', 20.0),
        entry('lib/a.dart', 'A.z', 4 / 3),
        entry('lib/a.dart', 'A.m', 12.0),
      ];
      final text1 = encodeBaseline(entries, 5);
      final text2 = encodeBaseline(entries, 5);
      expect(text1, text2);

      final baseline = Baseline.parse(text1);
      expect(baseline.threshold, 5);
      expect(baseline.entries.keys.toList(), [
        'lib/a.dart::A.m',
        'lib/a.dart::A.z',
        'lib/b.dart::g',
      ]);
      expect(baseline.entries['lib/a.dart::A.z'], 1.3333);

      final decoded = jsonDecode(text1) as Map<String, Object?>;
      expect(decoded.keys.toList(), ['threshold', 'entries']);
      final list = decoded['entries'] as List<Object?>;
      expect(list, hasLength(3));
      expect((list.first as Map<String, Object?>).keys.toList(), [
        'file',
        'member',
        'crap',
      ]);
      expect(text1.endsWith('\n'), isTrue);
    });
  });

  group('loadBaseline', () {
    test('parses an existing baseline file', () {
      final dir = Directory.systemTemp.createTempSync('crap_baseline_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/baseline.json';
      File(path).writeAsStringSync(
        encodeBaseline([entry('lib/a.dart', 'A.m', 12.0)], 5),
      );
      final baseline = loadBaseline(path, 5);
      expect(baseline.threshold, 5);
      expect(baseline.entries, {'lib/a.dart::A.m': 12.0});
    });

    test('missing baseline file means an empty ratchet (hard gate)', () {
      final baseline = loadBaseline('/nonexistent/dir/crap_baseline.json', 7);
      expect(baseline.threshold, 7);
      expect(baseline.entries, isEmpty);
    });

    test('an empty baseline turns every violation into a new one', () {
      final baseline = const Baseline(threshold: 5, entries: {});
      final result = evaluateGate(
        current: [entry('lib/a.dart', 'A.m', 12.0)],
        baseline: baseline,
        threshold: 5,
      );
      expect(result.passes, isFalse);
      expect(result.newViolations, hasLength(1));
    });
  });
}
