import 'package:flutter_test/flutter_test.dart';

import '../../tool/coverage_filter.dart';

void main() {
  group('isExcludedPath', () {
    test('matches lib/l10n sections in relative, absolute and \\ forms', () {
      expect(
        isExcludedPath('lib/l10n/generated/app_localizations_ru.dart'),
        isTrue,
      );
      expect(isExcludedPath('lib/l10n/app.dart'), isTrue);
      expect(isExcludedPath('/abs/root/lib/l10n/generated/app.dart'), isTrue);
      expect(isExcludedPath(r'lib\l10n\generated\app.dart'), isTrue);
    });

    test('does not match lookalikes or out-of-scope paths', () {
      expect(isExcludedPath('lib/l10next/app.dart'), isFalse);
      expect(isExcludedPath('lib/ui/screens/home_screen.dart'), isFalse);
      expect(isExcludedPath('lib/l10n'), isFalse);
      expect(isExcludedPath('app_localizations_ru.dart'), isFalse);
    });
  });

  group('filterLcov', () {
    const l10nSection =
        'SF:lib/l10n/generated/app.dart\nDA:148,1\nDA:150,0\n'
        'LF:2\nLH:1\nend_of_record\n';
    const keptSection =
        'SF:lib/ui/screens/home_screen.dart\nDA:1,1\nLF:1\nLH:1\n'
        'end_of_record\n';

    test('drops the whole l10n section and keeps neighbors byte-identical', () {
      expect(filterLcov(l10nSection + keptSection), keptSection);
      expect(filterLcov(keptSection + l10nSection), keptSection);
    });

    test('passes through input with no l10n sections byte-identical', () {
      expect(filterLcov(keptSection), keptSection);
    });

    test('passes through empty input and bare preamble untouched', () {
      expect(filterLcov(''), '');
      expect(filterLcov('TN:a test\n'), 'TN:a test\n');
    });

    test('drops a truncated final l10n section with no end_of_record', () {
      const truncated = 'SF:lib/l10n/generated/app.dart\nDA:1,0\n';
      expect(filterLcov(keptSection + truncated), keptSection);
    });

    test('keeps preamble before the first SF section', () {
      expect(filterLcov('TN:coverage\n$l10nSection'), 'TN:coverage\n');
    });

    test('sorts kept SF sections by path (issue #53)', () {
      const b = 'SF:lib/b.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n';
      const a = 'SF:lib/a.dart\nDA:2,1\nLF:1\nLH:1\nend_of_record\n';
      final sorted = a + b;
      // Input order must not matter: whole-report bytes are canonical.
      expect(filterLcov(b + a), sorted);
      expect(filterLcov(a + b), sorted);
    });

    test('drops l10n sections from anywhere and keeps the rest sorted', () {
      const a = 'SF:lib/a.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n';
      const z = 'SF:lib/z.dart\nDA:9,1\nLF:1\nLH:1\nend_of_record\n';
      expect(filterLcov('$z$l10nSection$a'), a + z);
    });

    test('already filtered output is byte-identical when re-filtered', () {
      const b = 'SF:lib/b.dart\nDA:5,0\nLF:1\nLH:0\nend_of_record\n';
      const a = 'SF:lib/a.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n';
      final once = filterLcov(b + a);
      expect(filterLcov(once), once);
    });

    test('keeps a preamble in front of the sorted sections', () {
      const b = 'SF:lib/b.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n';
      const a = 'SF:lib/a.dart\nDA:2,1\nLF:1\nLH:1\nend_of_record\n';
      expect(filterLcov('TN:cov\n$b$a'), 'TN:cov\n$a$b');
    });

    test('input without trailing newline stays newline-less when sorted', () {
      expect(
        filterLcov(
          'SF:lib/b.dart\nend_of_record\nSF:lib/a.dart\nend_of_record',
        ),
        'SF:lib/a.dart\nend_of_record\nSF:lib/b.dart\nend_of_record',
      );
    });
  });

  group('filterLcovWithDropped', () {
    const l10nSection =
        'SF:lib/l10n/generated/app.dart\nDA:148,1\nDA:150,0\n'
        'LF:2\nLH:1\nend_of_record\n';
    const keptSection =
        'SF:lib/ui/screens/home_screen.dart\nDA:1,1\nLF:1\nLH:1\n'
        'end_of_record\n';

    test('counts dropped SF sections, agrees with filterLcov text', () {
      final (text, dropped) = filterLcovWithDropped(l10nSection + keptSection);
      expect(dropped, 1);
      expect(text, filterLcov(l10nSection + keptSection));

      final (_, noneDropped) = filterLcovWithDropped(keptSection);
      expect(noneDropped, 0);
    });
  });
}
