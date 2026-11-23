import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/seeded_overrides.dart';

Future<(ProviderContainer, PrefsRepository)> pumpSettings(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/settings');
  await tester.pumpAndSettle();
  return (container, container.read(prefsRepositoryProvider));
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

void main() {
  testWidgets('theme change persists across container reload', (tester) async {
    final (_, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.text(l10n.themeDark));
    await tester.pumpAndSettle();

    // A fresh repository over the same prefs proves persistence.
    final prefs2 = await SharedPreferences.getInstance();
    expect(PrefsRepository(prefs2).loadSettings().themeMode, ThemeMode.dark);
    expect(repo.loadSettings().themeMode, ThemeMode.dark);
  });

  testWidgets('haptics toggle persists', (tester) async {
    final (_, repo) = await pumpSettings(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(repo.loadSettings().haptics, isFalse);
  });

  testWidgets('reset clears saves/stats/daily but keeps settings', (
    tester,
  ) async {
    final (container, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);
    // Seed progress data.
    await repo.saveSettings(const Settings(themeMode: ThemeMode.dark));
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    // Advance the fake clock so the async persist completes.
    await tester.pump();
    await repo.saveStats(Stats()..totalCases = 9);
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-19', streak: 2),
    );

    await tester.tap(find.text(l10n.resetProgress));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetProgress).last);
    await tester.pumpAndSettle();

    expect(repo.loadActiveGame(), isNull);
    expect(repo.loadStats().totalCases, 0);
    expect(repo.loadDailyState().streak, 0);
    // Settings are kept.
    expect(repo.loadSettings().themeMode, ThemeMode.dark);
    expect(find.text(l10n.progressReset), findsOneWidget);
  });

  testWidgets('skin picker offers the four localized skins (issue 23)', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);
    for (final label in [
      l10n.skinClassic,
      l10n.skinCandy,
      l10n.skinSticker,
      l10n.skinComic,
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'segment $label');
    }
    // The caption explains that ThemeMode applies to Классика only.
    expect(find.text(l10n.themeModeCaption), findsOneWidget);
  });

  testWidgets('selecting Комикс updates the controller and persists '
      '(issue 23)', (tester) async {
    final (container, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.skinComic));
    await tester.pumpAndSettle();

    expect(container.read(settingsControllerProvider).skin, SkinSetting.comic);
    // A fresh repository over the same prefs proves persistence.
    final prefs2 = await SharedPreferences.getInstance();
    expect(PrefsRepository(prefs2).loadSettings().skin, SkinSetting.comic);
    expect(repo.loadSettings().skin, SkinSetting.comic);
  });
}
