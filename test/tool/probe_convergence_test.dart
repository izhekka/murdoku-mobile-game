import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';

import '../../tool/probe_convergence.dart';

void main() {
  late final Map<String, Map<int, int?>> mapping;
  setUpAll(() {
    mapping = measureMapping();
  });

  group('measureMapping', () {
    test('covers the current pin domain: difficulties x seeds 0..60 (#62)', () {
      expect(mapping.keys.toList(), Difficulty.values.map((d) => d.name));
      for (final seeds in mapping.values) {
        expect(seeds.keys.toList(), List<int>.generate(61, (i) => i));
      }
    });

    test('wiring: storedSeedFor records the live generateCase seed (#62)', () {
      // Representative subset per difficulty — a full-range re-run would
      // re-measure generateCase against generateCase (the pin test owns
      // generator vs table); this pins only the probe's delegation.
      for (final d in Difficulty.values) {
        for (var seed = 0; seed <= 2; seed++) {
          expect(
            storedSeedFor(d, seed),
            generateCase(difficulty: d, seed: seed).seed,
            reason: '${d.name} seed $seed measured differently',
          );
        }
      }
    });

    test('spot-equals the committed pin table (convergence test, #62)', () {
      // Values copied verbatim from test/domain/generator/
      // seed_convergence_test.dart — when that table is re-pinned, update
      // these in the same change. Deliberate literal copy: independent of
      // that table, the values also witness transcription drift in it
      // (the golden-digest literal-copy style). Re-pinned 2026-11-27 for
      // the issue-#93 interim configuration; re-measured 2026-11-28 for
      // issue #111's pool change.
      expect(mapping['easy']![0], 0);
      expect(mapping['easy']![4], 1951803668); // == standard/4 (attempt-0 map)
      expect(mapping['standard']![4], 1951803668);
      expect(mapping['hard']![60], 295270247);
    });

    test('no pinned exhaust seam remains in the measured range (#62)', () {
      // Pre-#93, hard/111 exhausted generateCase's whole widened budget
      // (§13 corridor seam, rethrow pinned via recovery tests). The
      // take-all per-type pool dissolved the corridor: hard/111 still
      // generates in window 0 (stored seeds re-measured 2026-11-28 for
      // issue #111's pool change) alongside easy/111.
      final at111 = measureMapping(start: 111, end: 111);
      expect(at111['hard']![111], 2074270045);
      expect(at111['easy']![111], 1237729143);
    });
  });

  group('formatRows', () {
    test(
      'prints rows in difficulty/seed order regardless of input order (#62)',
      () {
        final rows = formatRows({
          'hard': {2: 3},
          'easy': {0: 1},
        });
        expect(rows, 'easy 0 -> 1\nhard 2 -> 3');
      },
    );

    test('prints an exhaust row for a null stored seed (#62)', () {
      final rows = formatRows({
        'hard': {2: null},
        'easy': {0: 1},
      });
      expect(rows, 'easy 0 -> 1\nhard 2 -> exhausts within the widened budget');
    });
  });

  group('formatMapLiteral', () {
    test('emits the exact pin-test map literal shape (#62)', () {
      final literal = formatMapLiteral({
        'easy': {0: 123, 1: 124},
        'hard': {5: 99},
      });
      expect(
        literal,
        'const _convergence = {\n'
        "  'easy': {\n"
        '    0: 123,\n'
        '    1: 124,\n'
        '  },\n'
        "  'hard': {\n"
        '    5: 99,\n'
        '  },\n'
        '};',
      );
    });

    test(
      'skips exhaust rows, keeping the literal strictly seed-keyed (#62)',
      () {
        final literal = formatMapLiteral({
          'easy': {0: 123, 1: null},
          'hard': {5: 99},
        });
        expect(literal, contains('    0: 123,'));
        expect(literal, isNot(contains('null')));
        expect(literal, isNot(contains('    1:')));
      },
    );
  });

  group('parseArgs', () {
    test('defaults to mapping over the pin range 0..60 (#62)', () {
      final args = parseArgs(const []);
      expect(args, isNotNull);
      expect(args!.mode, ProbeMode.mapping);
      expect(args.start, 0);
      expect(args.end, 60);
    });

    test('parses mode and explicit ranges (#62)', () {
      expect(parseArgs(const ['map', '10', '20'])!.mode, ProbeMode.map);
      expect(parseArgs(const ['map', '10', '20'])!.start, 10);
      expect(parseArgs(const ['map', '10', '20'])!.end, 20);
      final open = parseArgs(const ['mapping', '55'])!;
      expect(open.mode, ProbeMode.mapping);
      expect(open.start, 55);
      expect(open.end, 60);
    });

    test('rejects malformed usage (#62)', () {
      expect(parseArgs(const ['bogus']), isNull);
      expect(parseArgs(const ['map', 'x']), isNull);
      expect(parseArgs(const ['map', '20', '10']), isNull); // inverted
      expect(parseArgs(const ['map', '1', '2', '3']), isNull); // extra
      expect(parseArgs(const ['map', '-1', '5']), isNull); // negative
      // A lone start only narrows within 0..60 (end stays 60), so a start
      // past the default end is the inverted-range rejection, not a
      // widening (§13 wording; reviewed on this branch).
      expect(parseArgs(const ['mapping', '61']), isNull);
    });

    test('parses the digest modes without extra args (#72)', () {
      expect(parseArgs(const ['digests'])!.mode, ProbeMode.digests);
      expect(parseArgs(const ['digests', 'x']), isNull);
      expect(parseArgs(const ['check'])!.mode, ProbeMode.check);
      expect(parseArgs(const ['check', 'y']), isNull);
    });

    test('parses daily dates strictly (#72)', () {
      final none = parseArgs(const ['daily']);
      expect(none!.dailyStart, isNull);
      expect(none.dailyEnd, isNull);
      final single = parseArgs(const ['daily', '2026-11-19']);
      expect(single!.dailyStart, DateTime.utc(2026, 11, 19));
      expect(single.dailyEnd, DateTime.utc(2026, 11, 19));
      final range = parseArgs(const ['daily', '2026-11-19', '2026-11-20']);
      expect(range!.dailyStart, DateTime.utc(2026, 11, 19));
      expect(range.dailyEnd, DateTime.utc(2026, 11, 20));
      expect(parseArgs(const ['daily', '2026-02-30']), isNull); // no such day
      expect(parseArgs(const ['daily', '20261119']), isNull); // missing dashes
      expect(
        parseArgs(const ['daily', '2026-11-20', '2026-11-19']),
        isNull, // inverted
      );
      expect(parseArgs(const ['daily', 'a', 'b', 'c']), isNull); // extra
    });
  });

  group('digestOf', () {
    test('spot-equals the committed golden digests (#72)', () {
      // Literal copies of test/domain/generator/golden_digest_test.dart —
      // deliberate: independent of that file, the copies also witness drift
      // in it (the golden-digest literal-copy style; update in the same
      // change as any digest re-pin). Regenerated 2026-11-27 for the
      // issue-#93 interim configuration.
      expect(
        digestOf(generateCase(difficulty: Difficulty.easy, seed: 1)),
        'f5550abd10168a97',
      );
      expect(
        digestOf(generateCase(difficulty: Difficulty.hard, seed: 112)),
        'cd5df795cf366db3',
      );
      expect(
        digestOf(generateCase(difficulty: Difficulty.standard, seed: 20261119)),
        'bdabdb853f0f917b',
      );
    });

    test('deterministic across repeated calls over a fixed entry (#72)', () {
      final first = digestOf(
        generateCase(difficulty: Difficulty.standard, seed: 20261119),
      );
      final second = digestOf(
        generateCase(difficulty: Difficulty.standard, seed: 20261119),
      );
      expect(first, second);
    });
  });

  group('golden entries', () {
    test('parseGoldenEntries skips comments, blanks and stray lines (#72)', () {
      final entries = parseGoldenEntries(
        '// preamble comment\n'
        '\n'
        'const golden = {\n'
        "  'easy/1': '9824ca8d10f6fd06',\n"
        '  // mid-map comment\n'
        "  'hard/112': '55ec51fcbf077c9c',\n"
        '};\n'
        'trailing prose\n',
      );
      expect(entries.map((e) => e.key), ['easy/1', 'hard/112']);
      expect(entries.first.committed, '9824ca8d10f6fd06');
      expect(entries.first.difficulty, Difficulty.easy);
      expect(entries.first.seed, 1);
    });

    test(
      'the committed golden file parses with unique 16-hex entries (#72)',
      () {
        final entries = readGoldenEntries(goldenFileDefault);
        expect(entries, isNotEmpty);
        expect(entries.map((e) => e.key).toSet().length, entries.length);
        for (final entry in entries) {
          expect(entry.committed, matches(RegExp(r'^[0-9a-f]{16}$')));
        }
        expect(
          entries.map((e) => e.key),
          containsAll(<String>[
            'easy/1',
            'standard/20261119',
            'standard/20261120',
          ]),
        );
      },
    );

    test('isDailySeed selects valid daily-date shapes (#72)', () {
      expect(isDailySeed(20261119), isTrue);
      expect(isDailySeed(20261120), isTrue);
      expect(isDailySeed(20261301), isFalse); // month 13
      expect(isDailySeed(20261131), isFalse); // Nov has 30 days
      expect(isDailySeed(1234567), isFalse); // short
      expect(isDailySeed(11212), isFalse); // short
    });
  });

  group('daily rows', () {
    test(
      'the golden-driven default reproduces the daily-date inputs (#72)',
      () {
        final rows = dailyRows(
          fromGolden: readGoldenEntries(goldenFileDefault),
        );
        expect(rows.length, 2);
        expect(rows[0].date, '2026-11-19');
        expect(rows[0].seed, 20261119);
        expect(rows[0].digest, 'bdabdb853f0f917b');
        expect(rows[1].date, '2026-11-20');
        expect(rows[1].seed, 20261120);
        expect(rows[1].digest, '309d07df497a0de2');
      },
    );

    test('an explicit single date prints the live digest (#72)', () {
      final rows = dailyRows(start: DateTime.utc(2026, 11, 19));
      expect(rows.single.digest, 'bdabdb853f0f917b');
    });

    test('an explicit range is inclusive across a month boundary (#72)', () {
      final rows = dailyRows(
        start: DateTime.utc(2026, 11, 30),
        end: DateTime.utc(2026, 12),
      );
      expect(rows.map((r) => r.date), ['2026-11-30', '2026-12-01']);
      expect(rows.map((r) => r.seed), [20261130, 20261201]);
      expect(rows.where((r) => r.digest != null).length, 2);
    });

    test('formatDailyRows shapes the date digest lines (#72)', () {
      final rows = dailyRows(fromGolden: readGoldenEntries(goldenFileDefault));
      expect(
        formatDailyRows(rows),
        '2026-11-19 20261119 -> bdabdb853f0f917b\n'
        '2026-11-20 20261120 -> 309d07df497a0de2',
      );
    });
  });

  group('checkGolden', () {
    test('the committed digests verify live with nothing to report (#72)', () {
      final entries = readGoldenEntries(goldenFileDefault);
      final result = checkGolden(goldenFileDefault);
      expect(result.drifted, isEmpty);
      expect(result.exhausts, isEmpty);
      expect(result.ok.length, entries.length);
    });

    test('a drifted committed value is reported with both sides (#72)', () {
      final dir = Directory.systemTemp.createTempSync('probe_digest_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}golden.dart';
      File(path).writeAsStringSync(
        'const golden = {\n'
        "  'easy/1': 'deadbeefdeadbeef',\n"
        '};\n',
      );
      final result = checkGolden(path);
      expect(
        result.drifted.single,
        'drift easy/1 live=f5550abd10168a97 committed=deadbeefdeadbeef',
      );
      expect(result.ok, isEmpty);
    });
  });
}
