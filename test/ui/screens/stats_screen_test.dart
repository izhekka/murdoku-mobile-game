import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> pumpStats(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/stats');
  await tester.pumpAndSettle();
  return container;
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

void main() {
  testWidgets('empty state copy before any win', (tester) async {
    await pumpStats(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text(l10n.statsEmpty), findsOneWidget);
    expect(find.text(l10n.currentStreak(0)), findsOneWidget);
  });

  testWidgets('renders per-difficulty rows from persisted stats', (
    tester,
  ) async {
    final container = await pumpStats(tester);
    final l10n = l10nOf(tester);
    final repo = container.read(prefsRepositoryProvider);

    final stats = Stats()
      ..solved[Difficulty.easy] = 2
      ..bestTime[Difficulty.easy] = const Duration(seconds: 60)
      ..totalTime[Difficulty.easy] = const Duration(seconds: 150)
      ..totalCases = 2;
    await repo.saveStats(stats);
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: 'x', streak: 5),
    );

    // Force the screen to re-read persisted data.
    container.invalidate(statsControllerProvider);
    await tester.pumpAndSettle();

    expect(find.text(l10n.statsEmpty), findsNothing);
    expect(find.text(l10n.statsSolved(2)), findsOneWidget);
    expect(find.text(l10n.statsBest('01:00')), findsOneWidget);
    expect(find.text(l10n.statsAverage('01:15')), findsOneWidget);
    expect(find.text(l10n.currentStreak(5)), findsOneWidget);
    expect(find.text(l10n.totalCasesLabel(2)), findsOneWidget);
  });
}
