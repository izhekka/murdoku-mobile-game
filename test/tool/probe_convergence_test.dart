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
      // (the golden-digest literal-copy style).
      expect(mapping['easy']![0], 565798388);
      expect(mapping['easy']![4], 1647545034); // == standard/4 (collision)
      expect(mapping['standard']![4], 1647545034);
      expect(mapping['hard']![60], 1403540709);
    });

    test('marks a pinned exhaust seam with a null stored seed (#62)', () {
      // hard/111 exhausts generateCase's whole widened budget (§13 corridor
      // seam; the rethrow is pinned in case_factory_test.dart), while
      // easy/111 generates — exhaust stays difficulty-scoped.
      final at111 = measureMapping(start: 111, end: 111);
      expect(at111['hard']![111], isNull);
      expect(at111['easy']![111], isNotNull);
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
  });
}
