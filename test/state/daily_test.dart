import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('same UTC date yields the identical daily case', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
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
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Clock says the day AFTER the daily was started.
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 1, 5)),
    ]);
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(gameControllerProvider.notifier);

    notifier.startDaily('2026-11-19');
    final state = container.read(gameControllerProvider)!;
    expect(state.isDaily, isTrue);
    expect(state.dailyDate, '2026-11-19',
        reason: 'daily identity is the start date, not the wall clock');

    // Solve the case: place everyone, accuse the murderer.
    for (final entry in state.caseData.solution.entries) {
      notifier.selectSuspect(entry.key);
      notifier.tapCell(entry.value);
    }
    expect(notifier.accuse(state.caseData.murdererId), isTrue);
    final won = container.read(gameControllerProvider)!;

    await container.read(statsControllerProvider.notifier).recordWin(
      difficulty: won.caseData.difficulty,
      time: won.elapsed,
      mistakes: won.wrongAccusations,
      isDaily: won.isDaily,
      dailyDate: won.dailyDate!,
    );

    expect(repo.loadDailyState().lastCompletedDate, '2026-11-19',
        reason: 'completion is booked for the START date across midnight');
    expect(repo.loadDailyState().streak, 1);
  });

  testWidgets('daily card shows no done marker when yesterday was completed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);
    await repo.saveDailyState(
        const DailyState(lastCompletedDate: '2026-11-19', streak: 2));

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 0, 30)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MurdokuApp(),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(HomeScreen)))!;

    expect(find.text(l10n.dailyCompleted), findsNothing);
  });

  testWidgets('daily card shows the done marker for today', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsRepository(prefs);
    await repo.saveDailyState(
        const DailyState(lastCompletedDate: '2026-11-20', streak: 3));

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 8, 0)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MurdokuApp(),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(HomeScreen)))!;

    expect(find.text(l10n.dailyCompleted), findsOneWidget);
  });
}
