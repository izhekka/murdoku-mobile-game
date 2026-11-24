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

  test('corridor date-seed recovers instead of crashing the daily start (#60)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: seededOverrides(prefs));
    addTearDown(container.dispose);
    final notifier = container.read(gameControllerProvider.notifier);

    // Evidence the pinned date really sits in a budget-exhaustion corridor:
    // bare generateCase (the pre-#60 daily call) throws for standard seed
    // 20310928. Under the derived mapping (issue 61) the decorrelated
    // failures shifted the corridor set: the 2019-2060 scan measured
    // exactly two failing date-seeds, 2031-09-28 and 2047-04-01 — both
    // pinned below; the pre-#61 corridor 2055-12-25 (20551225) now
    // generates directly.
    for (final date in const ['2031-09-28', '2047-04-01']) {
      expect(
        () => generateCase(
          difficulty: Difficulty.standard,
          seed: dailySeedFor(parseUtcDate(date)),
        ),
        throwsStateError,
        reason:
            'corridor moved or vanished — re-verify the failing date-seed '
            'scan and re-pin date/stride ($date)',
      );
    }

    // The daily start must not crash: recovery strides to seed 20310968.
    notifier.startDaily('2031-09-28');
    final first = container.read(gameControllerProvider)!;
    expect(first.isDaily, isTrue);
    expect(first.dailyDate, '2031-09-28');
    expect(
      first.caseData.seed,
      895059595,
      reason:
          'recovery must land on the window-1 stride seed '
          '(generateCase(standard, 20310968).seed)',
    );
    expect(
      first.caseData.toJson(),
      generateCaseWithRecovery(
        difficulty: Difficulty.standard,
        seed: dailySeedFor(parseUtcDate('2031-09-28')),
      ).toJson(),
      reason: 'a corridor date-seed recovers exactly like the issue-45 seam',
    );

    // Daily replay determinism after recovery: same date, same recovered case.
    notifier.quit();
    notifier.startDaily('2031-09-28');
    final second = container.read(gameControllerProvider)!.caseData;
    expect(second.toJson(), equals(first.caseData.toJson()));
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
