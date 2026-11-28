import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/generator/case_factory.dart'
    show casePoolGeneratorTag;
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/state/case_pool.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/case_pool_fixture.dart';

/// Recorded batch-seam calls: (difficulty, count) in call order.
typedef CallLog = List<(Difficulty, int)>;

class Harness {
  Harness(this.container, this.repo, this.calls);

  final ProviderContainer container;
  final PrefsRepository repo;
  final CallLog calls;
}

/// Container with mock prefs and a stubbed batch seam (no forcedSeed pin —
/// the pinned path is covered in the game-controller suite).
Future<Harness> makeHarness({
  CasePool? stocked,
  bool pinForcedSeed = false,
  Future<List<CaseData>> Function(Difficulty difficulty, int count)? batch,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = PrefsRepository(prefs);
  if (stocked != null) await repo.saveCasePool(stocked);
  final calls = <(Difficulty, int)>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (pinForcedSeed) forcedSeedProvider.overrideWithValue(7),
      casePoolBatchProvider.overrideWithValue(
        batch ??
            (difficulty, count) async {
              calls.add((difficulty, count));
              return [
                for (var i = 0; i < count; i++) poolCase(difficulty, 1000 + i),
              ];
            },
      ),
    ],
  );
  return Harness(container, repo, calls);
}

/// All three pools stocked at 5 — only an explicitly deficient easy pool
/// (pass a smaller count) then draws a batch, keeping these tests focused
/// on one difficulty.
CasePool stockedPools(int easyCount) => CasePool(
  byDifficulty: {
    Difficulty.easy: [
      for (var i = 0; i < easyCount; i++) poolCase(Difficulty.easy, i),
    ],
    Difficulty.standard: [
      for (var i = 0; i < 5; i++) poolCase(Difficulty.standard, i),
    ],
    Difficulty.hard: [for (var i = 0; i < 5; i++) poolCase(Difficulty.hard, i)],
  },
);

void main() {
  test('build loads the persisted pool', () async {
    final stocked = stockedPools(2);
    final h = await makeHarness(stocked: stocked);
    addTearDown(h.container.dispose);
    expect(h.container.read(casePoolControllerProvider), stocked);
  });

  test(
    'take pops a stocked entry, persists the remainder and refills',
    () async {
      final a = poolCase(Difficulty.easy, 1);
      final b = poolCase(Difficulty.easy, 2);
      final h = await makeHarness(
        stocked: CasePool(
          byDifficulty: {
            Difficulty.easy: [a, b],
            Difficulty.standard: [
              for (var i = 0; i < 5; i++) poolCase(Difficulty.standard, i),
            ],
            Difficulty.hard: [
              for (var i = 0; i < 5; i++) poolCase(Difficulty.hard, i),
            ],
          },
        ),
      );
      addTearDown(h.container.dispose);
      final notifier = h.container.read(casePoolControllerProvider.notifier);

      final picked = notifier.take(Difficulty.easy);
      expect(picked, anyOf(a, b));
      // The controller holds round-tripped (fromJson) copies of the stored
      // cases, so the survivor is determined structurally, not by identity.
      final remaining = picked == a ? b : a;

      await pumpEventQueue();
      // The pop left 1 case (< 5) → exactly one background batch of 10.
      expect(h.calls, [(Difficulty.easy, 10)]);
      final reloaded = h.repo.loadCasePool().byDifficulty[Difficulty.easy]!;
      expect(reloaded, hasLength(11));
      expect(reloaded, contains(remaining));
      expect(
        h.container
            .read(casePoolControllerProvider)
            .byDifficulty[Difficulty.easy],
        reloaded,
      );
    },
  );

  test('take on an empty pool returns null without any batch', () async {
    final h = await makeHarness();
    addTearDown(h.container.dispose);
    final notifier = h.container.read(casePoolControllerProvider.notifier);

    expect(notifier.take(Difficulty.easy), isNull);
    await pumpEventQueue();
    expect(h.calls, isEmpty);
  });

  test('take on a single-entry pool empties it and refills 10', () async {
    final a = poolCase(Difficulty.easy, 1);
    final h = await makeHarness(
      stocked: CasePool(
        byDifficulty: {
          Difficulty.easy: [a],
          Difficulty.standard: [
            for (var i = 0; i < 5; i++) poolCase(Difficulty.standard, i),
          ],
          Difficulty.hard: [
            for (var i = 0; i < 5; i++) poolCase(Difficulty.hard, i),
          ],
        },
      ),
    );
    addTearDown(h.container.dispose);
    final notifier = h.container.read(casePoolControllerProvider.notifier);

    expect(notifier.take(Difficulty.easy), a);
    await pumpEventQueue();
    expect(h.calls, [(Difficulty.easy, 10)]);
    final reloaded = h.repo.loadCasePool().byDifficulty[Difficulty.easy]!;
    expect(reloaded, hasLength(10));
    expect(reloaded, isNot(contains(a)));
  });

  test('refill tops up a deficient pool with one batch of 10', () async {
    final h = await makeHarness(stocked: stockedPools(4));
    addTearDown(h.container.dispose);
    final notifier = h.container.read(casePoolControllerProvider.notifier);

    await notifier.maybeRefill();
    expect(h.calls, [(Difficulty.easy, 10)]);
    final reloaded = h.repo.loadCasePool().byDifficulty[Difficulty.easy]!;
    expect(reloaded, hasLength(14));
    expect(
      h.container
          .read(casePoolControllerProvider)
          .byDifficulty[Difficulty.easy],
      reloaded,
    );
  });

  test('a stocked pool triggers no batch', () async {
    final h = await makeHarness(stocked: stockedPools(5));
    addTearDown(h.container.dispose);
    await h.container.read(casePoolControllerProvider.notifier).maybeRefill();
    expect(h.calls, isEmpty);
  });

  test('each deficient difficulty gets its own batch of 10', () async {
    final h = await makeHarness(
      stocked: CasePool(
        byDifficulty: {
          Difficulty.easy: [
            poolCase(Difficulty.easy, 1),
            poolCase(Difficulty.easy, 2),
          ],
          Difficulty.standard: [
            for (var i = 0; i < 5; i++) poolCase(Difficulty.standard, i),
          ],
        },
      ),
    );
    addTearDown(h.container.dispose);
    await h.container.read(casePoolControllerProvider.notifier).maybeRefill();
    // Difficulty value order: easy deficient, standard stocked, hard empty.
    expect(h.calls, [(Difficulty.easy, 10), (Difficulty.hard, 10)]);
  });

  test(
    'concurrent refill checks never stack batches (single-flight)',
    () async {
      final gate = Completer<void>();
      final calls = <(Difficulty, int)>[];
      final h = await makeHarness(
        // Only easy is deficient; standard and hard are stocked.
        stocked: CasePool(
          byDifficulty: {
            Difficulty.standard: [
              for (var i = 0; i < 5; i++) poolCase(Difficulty.standard, i),
            ],
            Difficulty.hard: [
              for (var i = 0; i < 5; i++) poolCase(Difficulty.hard, i),
            ],
          },
        ),
        batch: (difficulty, count) {
          calls.add((difficulty, count));
          return gate.future.then(
            (_) => [
              for (var i = 0; i < count; i++) poolCase(difficulty, 1000 + i),
            ],
          );
        },
      );
      addTearDown(h.container.dispose);
      final notifier = h.container.read(casePoolControllerProvider.notifier);

      final first = notifier.maybeRefill();
      final second = notifier.maybeRefill();
      expect(calls, [(Difficulty.easy, 10)], reason: 'one batch, not two');

      gate.complete();
      await Future.wait([first, second]);
      expect(calls, [(Difficulty.easy, 10)]);
      expect(
        h.repo.loadCasePool().byDifficulty[Difficulty.easy],
        hasLength(10),
      );
    },
  );

  test(
    'a failed batch is swallowed and clears the flight (retry allowed)',
    () async {
      final calls = <(Difficulty, int)>[];
      final h = await makeHarness(
        stocked: stockedPools(1),
        batch: (difficulty, count) async {
          calls.add((difficulty, count));
          throw StateError('generation blew up');
        },
      );
      addTearDown(h.container.dispose);
      final notifier = h.container.read(casePoolControllerProvider.notifier);

      await notifier.maybeRefill(); // must not throw
      expect(
        h.repo.loadCasePool().byDifficulty[Difficulty.easy],
        hasLength(1),
        reason: 'pool unchanged after a failed batch',
      );

      await notifier.maybeRefill();
      expect(
        calls,
        [(Difficulty.easy, 10), (Difficulty.easy, 10)],
        reason: 'the in-flight flag cleared, so the retry started a new batch',
      );
    },
  );

  test('the forced-seed pin disables refill entirely', () async {
    final h = await makeHarness(pinForcedSeed: true);
    addTearDown(h.container.dispose);
    await h.container.read(casePoolControllerProvider.notifier).maybeRefill();
    expect(h.calls, isEmpty);
  });

  test('a foreign generator tag loads as the empty pool', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final envelope = CasePool(
      byDifficulty: {
        Difficulty.easy: [poolCase(Difficulty.easy, 1)],
      },
    ).toJson();
    envelope['gen'] = casePoolGeneratorTag + 1;
    await prefs.setString('murdoku.casePool', jsonEncode(envelope));

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(casePoolControllerProvider), CasePool.empty);
  });

  test('production batch seam generates one case via Isolate.run', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final cases = await container.read(casePoolBatchProvider)(
      Difficulty.easy,
      1,
    );
    expect(cases, hasLength(1));
    expect(cases.single.difficulty, Difficulty.easy);
  });
}
