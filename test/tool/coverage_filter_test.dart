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
