import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/game_logic.dart' show Tool, boardSolved;
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/state/case_pool.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/case_pool_fixture.dart';
import '../support/legacy_case_fixture.dart';
import '../support/seeded_overrides.dart';

Pos p(int row, int col) => (row: row, col: col);

/// A deterministic easy case: same call the controller makes internally.
final CaseData fixedCase = generateCase(difficulty: Difficulty.easy, seed: 3);

Future<ProviderContainer> makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: seededOverrides(prefs));
}

/// Unpinned container (no forcedSeed): exercises the real pool path with a
/// stubbed batch seam. Records (difficulty, count) batch calls in order.
Future<(ProviderContainer, PrefsRepository, List<(Difficulty, int)>)>
makePoolContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = PrefsRepository(prefs);
  final calls = <(Difficulty, int)>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      casePoolBatchProvider.overrideWithValue((difficulty, count) async {
        calls.add((difficulty, count));
        return [for (var i = 0; i < count; i++) poolCase(difficulty, 1000 + i)];
      }),
    ],
  );
  return (container, repo, calls);
}

void main() {
  test('container pins the forced seed: unseeded startNewCase yields the '
      'seed-3 case (issue 36)', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);

    // No explicit seed: the container's forcedSeedProvider pin must supply 3,
    // so the case equals fixedCase instead of a Random()-fallback case.
    notifier.startNewCase(Difficulty.easy);
    expect(container.read(gameControllerProvider)!.caseData, fixedCase);
  });

  test('happy path: place all guests, accuse murderer, save cleared', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);

    expect(container.read(gameControllerProvider), isNull);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    final state = container.read(gameControllerProvider)!;
    expect(state.caseData, fixedCase);
    expect(state.phase, GamePhase.playing);

    for (final entry in fixedCase.solution.entries) {
      notifier.selectSuspect(entry.key);
      notifier.tapCell(entry.value);
    }
    var after = container.read(gameControllerProvider)!;
    expect(after.placed.length, 5);
    expect(boardSolved(fixedCase, after.placed), isTrue);

    // Save persisted mid-game.
    await Future<void>.delayed(Duration.zero);
    expect(repo.loadActiveGame(), isNotNull);

    final correct = notifier.accuse(fixedCase.murdererId);
    expect(correct, isTrue);
    after = container.read(gameControllerProvider)!;
    expect(after.phase, GamePhase.won);
    await Future<void>.delayed(Duration.zero);
    expect(repo.loadActiveGame(), isNull, reason: 'win clears the save');
  });

  test('wrong accusation increments mistakes and keeps playing', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);

    final innocent = fixedCase.suspects
        .map((s) => s.id)
        .firstWhere((id) => id != fixedCase.murdererId);
    final correct = notifier.accuse(innocent);
    expect(correct, isFalse);
    final state = container.read(gameControllerProvider)!;
    expect(state.phase, GamePhase.playing);
    expect(state.wrongAccusations, 1);
  });

  test('tapCell place/remove toggle and no-op rules', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);

    // No selection -> tap is a no-op.
    notifier.tapCell(p(0, 0));
    expect(container.read(gameControllerProvider)!.placed, isEmpty);

    // Place s0 at its solution cell.
    final s0 = fixedCase.solution['s0']!;
    notifier.selectSuspect('s0');
    notifier.tapCell(s0);
    expect(container.read(gameControllerProvider)!.placed['s0'], s0);

    // Tapping the suspect's own cell removes it (toggle).
    notifier.tapCell(s0);
    expect(
      container.read(gameControllerProvider)!.placed.containsKey('s0'),
      isFalse,
    );

    // Place s0 again, then try to place s1 onto the same cell -> no-op.
    notifier.tapCell(s0);
    expect(container.read(gameControllerProvider)!.placed['s0'], s0);
    notifier.selectSuspect('s1');
    notifier.tapCell(s0);
    expect(
      container.read(gameControllerProvider)!.placed.containsKey('s1'),
      isFalse,
    );
    expect(container.read(gameControllerProvider)!.placed['s0'], s0);

    // Victim cell cannot be placed on.
    notifier.tapCell(fixedCase.victimPos);
    expect(
      container.read(gameControllerProvider)!.placed.containsKey('s1'),
      isFalse,
    );
  });

  test('tapCell ignores input when phase is not playing', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    notifier.selectSuspect('s0');
    notifier.revealSolution();
    final before = container.read(gameControllerProvider)!;
    notifier.tapCell(fixedCase.solution['s0']!);
    final after = container.read(gameControllerProvider)!;
    expect(after.placed, before.placed);
  });

  test('X marks toggle with the markX tool (issue 107 removes the erase '
      'tool; tapping again clears)', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);

    notifier.setTool(Tool.markX);
    notifier.tapCell(p(4, 0));
    expect(container.read(gameControllerProvider)!.xMarks, {p(4, 0)});
    notifier.tapCell(p(4, 0));
    expect(container.read(gameControllerProvider)!.xMarks, isEmpty);
  });

  test('resume restores board, marks and elapsed time', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    notifier.selectSuspect('s0');
    notifier.tapCell(fixedCase.solution['s0']!);
    notifier.setTool(Tool.markX);
    notifier.tapCell(p(4, 0));
    for (var i = 0; i < 7; i++) {
      notifier.tick();
    }
    await Future<void>.delayed(Duration.zero);
    final saved = repo.loadActiveGame()!;

    notifier.resume(saved);
    final state = container.read(gameControllerProvider)!;
    expect(state.placed['s0'], fixedCase.solution['s0']);
    expect(state.xMarks, {p(4, 0)});
    expect(state.elapsed, const Duration(seconds: 7));
    expect(state.phase, GamePhase.playing);
  });

  test(
    'legacy 6x6 save resumes on its stored grid, not the new knob (issue #93)',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final repo = container.read(prefsRepositoryProvider);

      // A pre-change in-progress 6x6 case stamped difficulty.standard.
      await repo.saveActiveGame(
        SavedGame(
          caseData: legacyStandardCase,
          isDaily: false,
          dailyDate: '',
          board: BoardSnapshot(
            placed: {'s1': legacyStandardCase.solution['s1']!},
            xMarks: {},
            elapsed: const Duration(seconds: 5),
            hintsUsed: 0,
            wrongAccusations: 0,
          ),
        ),
      );

      final notifier = container.read(gameControllerProvider.notifier);
      notifier.resume(repo.loadActiveGame()!);
      final state = container.read(gameControllerProvider)!;
      expect(state.phase, GamePhase.playing);
      expect(state.caseData.gridSize, 6);
      expect(state.placed['s1'], legacyStandardCase.solution['s1']);

      // The restored board accepts moves across the whole stored 6x6 grid.
      notifier.selectSuspect('s2');
      notifier.tapCell(legacyStandardCase.solution['s2']!);
      expect(
        container.read(gameControllerProvider)!.placed['s2'],
        legacyStandardCase.solution['s2'],
      );
    },
  );

  test(
    'hints: placement locks a correct guest; third hint is a no-op',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);
      notifier.startNewCase(Difficulty.easy, seed: 3);

      notifier.hintPlacement();
      var state = container.read(gameControllerProvider)!;
      expect(state.hintsUsed, 1);
      final hintedSuspect = state.placed.keys.single;
      expect(state.placed[hintedSuspect], fixedCase.solution[hintedSuspect]);
      expect(state.lockedSuspects, {hintedSuspect});

      // Locked guest cannot be removed by tapping.
      notifier.selectSuspect(hintedSuspect);
      notifier.setTool(Tool.place);
      notifier.tapCell(state.placed[hintedSuspect]!);
      expect(
        container
            .read(gameControllerProvider)!
            .placed
            .containsKey(hintedSuspect),
        isTrue,
      );

      notifier.hintPlacement();
      notifier.hintPlacement();
      state = container.read(gameControllerProvider)!;
      expect(state.hintsUsed, 2, reason: 'only two hints per game');
    },
  );

  test(
    'hintEliminate never eliminates the murderer and consumes the budget',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);
      notifier.startNewCase(Difficulty.easy, seed: 3);

      // Two elimination hints (the full shared budget of 2).
      notifier.hintEliminate();
      var state = container.read(gameControllerProvider)!;
      expect(state.eliminatedSuspects, isNotEmpty);
      expect(state.eliminatedSuspects.contains(fixedCase.murdererId), isFalse);
      expect(state.hintsUsed, 1);
      final afterFirst = state.eliminatedSuspects.length;

      notifier.hintEliminate();
      state = container.read(gameControllerProvider)!;
      expect(state.hintsUsed, 2);
      expect(state.eliminatedSuspects.length, afterFirst + 1);

      // Budget exhausted: further hints are no-ops.
      notifier.hintEliminate();
      notifier.hintEliminate();
      state = container.read(gameControllerProvider)!;
      expect(state.hintsUsed, 2);
      expect(
        state.eliminatedSuspects.length,
        afterFirst + 1,
        reason: 'no elimination beyond the 2-hint budget',
      );
    },
  );

  test(
    'hintPlacement never double-occupies a cell held by a wrong guest',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);
      notifier.startNewCase(Difficulty.easy, seed: 3);

      // Wrongly place s1 on s0's solution cell.
      notifier.selectSuspect('s1');
      notifier.tapCell(fixedCase.solution['s0']!);
      expect(container.read(gameControllerProvider)!.placed.length, 1);

      notifier.hintPlacement();
      final state = container.read(gameControllerProvider)!;
      final positions = state.placed.values.toSet();
      expect(
        positions.length,
        state.placed.length,
        reason: 'no two suspects may share a cell',
      );
      expect(state.hintsUsed, 1);
      // The wrongly placed guest is untouched (no silent eviction).
      expect(state.placed['s1'], fixedCase.solution['s0']);
    },
  );

  test('daily: same UTC date yields the identical case', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startDaily('2026-11-19');
    final first = container.read(gameControllerProvider)!.caseData;
    notifier.quit();
    notifier.startDaily('2026-11-19');
    final second = container.read(gameControllerProvider)!.caseData;
    expect(second.toJson(), equals(first.toJson()));
    expect(container.read(gameControllerProvider)!.isDaily, isTrue);
    expect(container.read(gameControllerProvider)!.dailyDate, '2026-11-19');
  });

  test('revealSolution shows the truth and forfeits the save', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    notifier.selectSuspect('s0');
    notifier.tapCell(fixedCase.solution['s0']!);
    await Future<void>.delayed(Duration.zero);

    notifier.revealSolution();
    final state = container.read(gameControllerProvider)!;
    expect(state.phase, GamePhase.revealed);
    expect(state.placed, fixedCase.solution);
    await Future<void>.delayed(Duration.zero);
    expect(repo.loadActiveGame(), isNull);
  });

  test('quit clears state and save', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    await Future<void>.delayed(Duration.zero);
    notifier.quit();
    expect(container.read(gameControllerProvider), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(repo.loadActiveGame(), isNull);
  });

  test('selectSuspect(null) clears the selection (issue 44)', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);

    notifier.selectSuspect('s0');
    expect(container.read(gameControllerProvider)!.selectedSuspectId, 's0');

    notifier.selectSuspect(null);
    expect(
      container.read(gameControllerProvider)!.selectedSuspectId,
      isNull,
      reason: 're-tapping the selected card must deselect (issue 44)',
    );

    // Deselecting with nothing selected stays null (no toggle-off crash).
    notifier.selectSuspect(null);
    expect(container.read(gameControllerProvider)!.selectedSuspectId, isNull);
  });

  test(
    'selectSuspect is ignored when the phase is not playing (issue 44)',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);
      notifier.startNewCase(Difficulty.easy, seed: 3);
      notifier.revealSolution();
      // The reveal compose drops the selection; the guard must keep the state
      // untouched (same instance) for both routing branches afterwards.
      final before = container.read(gameControllerProvider)!;

      notifier.selectSuspect('s1');
      notifier.selectSuspect(null);

      expect(
        container.read(gameControllerProvider),
        same(before),
        reason: 'selection changes are ignored after the game ends',
      );
    },
  );

  test('clearSelection clears only the selection (issue 44)', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);

    notifier.selectSuspect('s0');
    notifier.tapCell(fixedCase.solution['s0']!);
    notifier.selectSuspect('s1');
    notifier.setTool(Tool.markX);
    final before = container.read(gameControllerProvider)!;
    expect(before.selectedSuspectId, 's1');
    expect(before.placed, containsPair('s0', fixedCase.solution['s0']));

    final cleared = before.clearSelection();
    expect(cleared.selectedSuspectId, isNull);
    expect(cleared.caseData, before.caseData);
    expect(cleared.phase, before.phase);
    expect(cleared.placed, before.placed);
    expect(cleared.xMarks, before.xMarks);
    expect(cleared.lockedSuspects, before.lockedSuspects);
    expect(cleared.tool, before.tool);
    expect(cleared.elapsed, before.elapsed);
    expect(cleared.hintsUsed, before.hintsUsed);
    expect(cleared.wrongAccusations, before.wrongAccusations);
    expect(cleared.isDaily, before.isDaily);
    expect(cleared.dailyDate, before.dailyDate);
    expect(cleared.eliminatedSuspects, before.eliminatedSuspects);

    // copyWith keeps every field for omitted and null args — only
    // clearSelection reaches a null selection (issue 44).
    expect(before.copyWith().selectedSuspectId, 's1');
    expect(before.copyWith().tool, before.tool);
    expect(before.copyWith().elapsed, before.elapsed);
    expect(before.copyWith().phase, before.phase);
    // Passing the null through a typed variable: the explicit-null call is
    // what the pin is about — copyWith treats it as "keep the old value".
    final String? noId = null;
    expect(
      before.copyWith(selectedSuspectId: noId).selectedSuspectId,
      's1',
      reason:
          'copyWith(null) keeps the old value; deselection is '
          'clearSelection()',
    );
    expect(before.copyWith(tool: Tool.place).tool, Tool.place);
    expect(
      before.copyWith(elapsed: const Duration(seconds: 9)).elapsed,
      const Duration(seconds: 9),
    );
    expect(
      before.copyWith(elapsed: const Duration(seconds: 9)).selectedSuspectId,
      's1',
    );
  });

  test('startNewCase resolves the former exhaust corridor hard seed 111 in window 0 (issue 45, interim #93)', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);

    // Under the pre-#93 cap-10 pool, hard 111 exhausted the whole widened
    // budget and this start exercised generateCaseWithRecovery's retry
    // path (recovered seed 1633640402). The issue-#93 take-all pool
    // dissolves that corridor: seed 111 generates directly in window 0
    // (stored seed 1237729143, map-probe measured 2026-11-27) and the
    // user path just plays it.
    notifier.startNewCase(Difficulty.hard, seed: 111);
    final state = container.read(gameControllerProvider)!;
    expect(state.phase, GamePhase.playing);
    expect(
      state.caseData.seed,
      1237729143,
      reason: 'the former corridor seed now plays its window-0 case',
    );
    expect(
      state.caseData.clues.length,
      inInclusiveRange(Difficulty.hard.minClues, Difficulty.hard.maxClues),
    );
  });

  test(
    'property: seeds across difficulties never crash the user path (issue 45)',
    () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);

      // Former derived-mapping exhausts 111/375 (§13, pre-#93 cap-10 pool)
      // now generate directly under the #93 take-all pool; the rest probe
      // normal and unknown ranges. Every start must yield a playable case,
      // never a StateError.
      for (final difficulty in Difficulty.values) {
        for (final seed in const [1, 3, 111, 375, 500, 99991]) {
          notifier.startNewCase(difficulty, seed: seed);
          final state = container.read(gameControllerProvider)!;
          expect(
            state.phase,
            GamePhase.playing,
            reason: '${difficulty.name} seed $seed',
          );
          notifier.quit();
        }
      }
    },
  );

  group('case pool integration (issue 108)', () {
    test('a pinned forced seed bypasses the pool entirely', () async {
      final container = await makeContainer();
      addTearDown(container.dispose);
      final repo = container.read(prefsRepositoryProvider);
      final stocked = poolCase(Difficulty.easy, 77);
      await repo.saveCasePool(
        CasePool(
          byDifficulty: {
            Difficulty.easy: [stocked],
          },
        ),
      );
      final notifier = container.read(gameControllerProvider.notifier);

      // forcedSeedProvider pins seed 3 (seededOverrides): the pool must
      // stay untouched and the start yield the deterministic seed-3 case.
      notifier.startNewCase(Difficulty.easy);
      expect(container.read(gameControllerProvider)!.caseData, fixedCase);
      expect(repo.loadCasePool().byDifficulty[Difficulty.easy], [stocked]);
    });

    test(
      'an unpinned start pops a pooled case into a fresh-board state',
      () async {
        final (container, repo, calls) = await makePoolContainer();
        addTearDown(container.dispose);
        final a = poolCase(Difficulty.easy, 1);
        final b = poolCase(Difficulty.easy, 2);
        await repo.saveCasePool(
          CasePool(
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
        final notifier = container.read(gameControllerProvider.notifier);

        notifier.startNewCase(Difficulty.easy);
        final state = container.read(gameControllerProvider)!;
        expect(state.caseData, anyOf(a, b));
        expect(state.phase, GamePhase.playing);
        expect(state.placed, isEmpty);
        expect(state.xMarks, isEmpty);
        expect(state.lockedSuspects, isEmpty);
        expect(state.eliminatedSuspects, isEmpty);
        expect(state.elapsed, Duration.zero);
        expect(state.hintsUsed, 0);
        expect(state.wrongAccusations, 0);
        expect(state.isDaily, isFalse);
        expect(state.dailyDate, isNull);

        await pumpEventQueue();
        // The pop left one easy case (< 5) → exactly one refill batch, and
        // the remainder persisted without the picked entry.
        expect(calls, [(Difficulty.easy, 10)]);
        final reloaded = repo.loadCasePool().byDifficulty[Difficulty.easy]!;
        expect(reloaded, hasLength(11));
        expect(reloaded, contains(state.caseData == a ? b : a));
      },
    );

    test('an empty pool falls back to sync generation and refills', () async {
      final (container, repo, calls) = await makePoolContainer();
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);

      notifier.startNewCase(Difficulty.easy);
      final state = container.read(gameControllerProvider)!;
      expect(state.phase, GamePhase.playing);
      expect(
        state.caseData.clues.length,
        inInclusiveRange(Difficulty.easy.minClues, Difficulty.easy.maxClues),
      );
      expect(
        calls.where((c) => c.$1 == Difficulty.easy),
        [(Difficulty.easy, 10)],
        reason:
            'background refill fired for the empty pool (all three '
            'pools are empty here, so each difficulty gets its own batch)',
      );

      await pumpEventQueue();
      expect(repo.loadCasePool().byDifficulty[Difficulty.easy], hasLength(10));
    });
  });
}
