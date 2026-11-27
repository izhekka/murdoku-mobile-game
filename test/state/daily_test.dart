import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/seeded_overrides.dart';

void main() {
  test('same UTC date yields the identical daily case', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: seededOverrides(prefs));
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);

    notifier.startDaily('2026-11-19');
    final first = container.read(gameControllerProvider)!.caseData;
    notifier.quit();
    notifier.startDaily('2026-11-19');
    final second = container.read(gameControllerProvider)!.caseData;
    expect(second.toJson(), equals(first.toJson()));
  });

  test('playing across midnight keeps the started date identity', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        ...seededOverrides(prefs),
        // Clock says the day AFTER the daily was started.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 1, 5)),
      ],
    );
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);

    notifier.startDaily('2026-11-19');
    final state = container.read(gameControllerProvider)!;
    expect(state.isDaily, isTrue);
    expect(
      state.dailyDate,
      '2026-11-19',
      reason: 'daily identity is the start date, not the wall clock',
    );

    // Solve the case: place everyone, accuse the murderer.
    for (final entry in state.caseData.solution.entries) {
      notifier.selectSuspect(entry.key);
      notifier.tapCell(entry.value);
    }
    expect(notifier.accuse(state.caseData.murdererId), isTrue);
    final won = container.read(gameControllerProvider)!;

    await container
        .read(statsControllerProvider.notifier)
        .recordWin(
          difficulty: won.caseData.difficulty,
          time: won.elapsed,
          mistakes: won.wrongAccusations,
          isDaily: won.isDaily,
          dailyDate: won.dailyDate!,
        );

    expect(
      repo.loadDailyState().lastCompletedDate,
      '2026-11-19',
      reason: 'completion is booked for the START date across midnight',
    );
    expect(repo.loadDailyState().streak, 1);
  });

  test('former corridor date-seeds now generate directly; daily replay stays deterministic (#60, interim #93)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: seededOverrides(prefs));
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);

    // Evidence re-measured 2026-11-27 (issue #93 interim configuration):
    // the pre-#93 cap-10 pool had exactly two failing date-seeds in
    // 2019-2060 (2031-09-28 and 2047-04-01, issues 60/61). The take-all
    // per-type pool dissolves both corridors — bare generateCase succeeds
    // in window 0 for each (stored seeds from the map probe:
    // 1243490650 / 1884598929), so the daily start no longer needs
    // recovery for these dates.
    final first = <String, int>{};
    for (final date in const ['2031-09-28', '2047-04-01']) {
      final bare = generateCase(
        difficulty: Difficulty.standard,
        seed: dailySeedFor(parseUtcDate(date)),
      );
      expect(
        bare.seed,
        date == '2031-09-28' ? 1243490650 : 1884598929,
        reason: '$date must generate in window 0 (former corridor date)',
      );
      first[date] = bare.seed;

      notifier.startDaily(date);
      final state = container.read(gameControllerProvider)!;
      expect(state.isDaily, isTrue);
      expect(state.dailyDate, date);
      expect(
        state.caseData.seed,
        first[date],
        reason: 'a window-0 date plays the bare case',
      );

      // Daily replay determinism: same date, same case.
      notifier.quit();
      notifier.startDaily(date);
      final second = container.read(gameControllerProvider)!.caseData;
      expect(
        second.toJson(),
        generateCaseWithRecovery(
          difficulty: Difficulty.standard,
          seed: dailySeedFor(parseUtcDate(date)),
        ).toJson(),
        reason: 'the daily path routes through the recovery-capable start',
      );
      expect(second.toJson(), bare.toJson());
      notifier.quit();
    }
  });

  test(
    'daily case for the fixed date is standard seed 20261120 (issue 49)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: seededOverrides(prefs));
      addTearDown(container.dispose);
      final notifier = container.read(gameControllerProvider.notifier);

      notifier.startDaily('2026-11-20');
      expect(
        container.read(gameControllerProvider)!.caseData.toJson(),
        generateCase(
          difficulty: Difficulty.standard,
          seed: dailySeedFor(parseUtcDate('2026-11-20')),
        ).toJson(),
        reason:
            'startDaily routes the fixed date through the standard generator '
            'with seed dailySeedFor(date)',
      );
    },
  );

  testWidgets('daily card shows no done marker when yesterday was completed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-19', streak: 2),
    );

    final container = ProviderContainer(
      overrides: [
        ...seededOverrides(prefs),
        clockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 20, 0, 30),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;

    expect(find.text(l10n.dailyCompleted), findsNothing);
  });

  testWidgets('daily card shows the done marker for today', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-20', streak: 3),
    );

    final container = ProviderContainer(
      overrides: [
        ...seededOverrides(prefs),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 8)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;

    expect(find.text(l10n.dailyCompleted), findsOneWidget);
  });
}
