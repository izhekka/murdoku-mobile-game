import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

import '../../tool/scan_daily_corridors.dart';

void main() {
  group('parseArgs', () {
    test('defaults to the 2019-2060 sweep (#71)', () {
      final parsed = parseArgs(const []);
      expect(parsed!.from, 2019);
      expect(parsed.to, 2060);
      expect(parsed.all, isFalse);
    });

    test('parses years and the --all flag in any position (#71)', () {
      expect(parseArgs(const ['2031', '2032'])!.from, 2031);
      expect(parseArgs(const ['2031', '2032'])!.to, 2032);
      expect(parseArgs(const ['--all', '2031'])!.all, isTrue);
      expect(parseArgs(const ['2031', '--all'])!.all, isTrue);
      // A flag-only invocation keeps the default sweep.
      expect(parseArgs(const ['--all'])!.from, 2019);
      expect(parseArgs(const ['--all'])!.to, 2060);
      // A lone year narrows within the default sweep: the end stays 2060
      // (the probe_convergence mode-only convention).
      expect(parseArgs(const ['2031'])!.to, 2060);
    });

    test('rejects malformed usage (#71)', () {
      expect(parseArgs(const ['x']), isNull);
      expect(parseArgs(const ['2031', '2030']), isNull); // inverted
      expect(parseArgs(const ['2031', '--verbose']), isNull); // unknown flag
      expect(parseArgs(const ['2031', '2032', '2033', '--all']), isNull);
    });
  });

  group('scanning', () {
    test('inverts dailySeedFor over a bounded inclusive window (#71)', () {
      // Inclusive endpoints and real month lengths (2032 is a leap year):
      // Dec 30-31 (2) + Jan 31 + Feb 29 + Mar 1 = 63 rows.
      final rows = scanDates(DateTime.utc(2031, 12, 30), DateTime.utc(2032, 3));
      expect(rows.length, 63);
      expect(rows.first.date, DateTime.utc(2031, 12, 30));
      expect(rows.last.date, DateTime.utc(2032, 3));
    });

    test('a generating date maps request -> ok (#71)', () {
      final row = scanDate(DateTime.utc(2026, 11, 19));
      expect(row.seed, 20261119);
      expect(row.recoveredStride, isNull);
      expect(row.recoveryExhausted, isFalse);
    });

    test('the pinned corridor date maps request -> window-1 stride (#71)', () {
      // Post-#61 corridor pin (test/state/daily_test.dart): bare
      // generateCase(standard, 20310928) throws; recovery strides +40.
      final row = scanDate(DateTime.utc(2031, 9, 28));
      expect(row.seed, 20310928);
      expect(row.recoveredStride, 20310968);
      expect(row.recoveryExhausted, isFalse);
      // Stride-copy staleness guard (Review Focus 4): generation from the
      // recovered stride must equal the shipped recovery result.
      expect(
        generateCaseWithRecovery(
          difficulty: Difficulty.standard,
          seed: 20310928,
        ).toJson(),
        generateCase(difficulty: Difficulty.standard, seed: 20310968).toJson(),
      );
    });

    test('corridor rows are reported exactly once each (#71)', () {
      final rows = scanDates(
        DateTime.utc(2031, 9, 27),
        DateTime.utc(2031, 9, 29),
      );
      expect(rows.where((r) => r.recoveredStride != null).length, 1);
      expect(rows.singleWhere((r) => r.recoveredStride != null).seed, 20310928);
    });
  });

  group('formatting', () {
    test(
      'formatCorridorRows prints only bare-exhaust dates with stride (#71)',
      () {
        final rows = scanDates(
          DateTime.utc(2031, 9, 27),
          DateTime.utc(2031, 9, 29),
        );
        expect(
          formatCorridorRows(rows),
          '2031-09-28 20310928 -> exhausts, recovers at 20310968',
        );
      },
    );

    test('formatDateRows prints one line per date (#71)', () {
      final rows = scanDates(
        DateTime.utc(2026, 11, 19),
        DateTime.utc(2026, 11, 20),
      );
      expect(
        formatDateRows(rows),
        '2026-11-19 20261119 -> ok\n2026-11-20 20261120 -> ok',
      );
    });

    test('formatSummary counts ok/corridor/unrecovered (#71)', () {
      final rows = scanDates(
        DateTime.utc(2031, 9, 27),
        DateTime.utc(2031, 9, 29),
      );
      expect(
        formatSummary(rows, 2031, 2031),
        'scanned 3 UTC dates 2031-2031: ok=2, corridor=1, unrecovered=0',
      );
    });
  });
}
