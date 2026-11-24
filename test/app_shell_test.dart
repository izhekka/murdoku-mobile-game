import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:murdoku/ui/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/seeded_overrides.dart';

Future<SharedPreferences> mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('home renders the app title from l10n', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.appTitle), findsOneWidget);
  });

  testWidgets('dark mode toggle changes material app brightness for the '
      'classic skin (issue 23)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // The theme swap rebuilds the tree; read the live element afterwards.
    final rebuilt = tester.element(find.byType(HomeScreen));
    expect(Theme.of(rebuilt).brightness, Brightness.dark);
  });

  testWidgets('cartoon skins are light-only: themeMode is ignored (issue 23)', (
    tester,
  ) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    // Default skin is sticker; asking for dark must not darken it.
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    final rebuilt = tester.element(find.byType(HomeScreen));
    expect(Theme.of(rebuilt).brightness, Brightness.light);
  });

  testWidgets('the app shell exposes the active skin tokens in context '
      '(issue 23)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    SkinTokens tokensOfHome() =>
        SkinScope.maybeOf(tester.element(find.byType(HomeScreen)))!;
    expect(tokensOfHome().skin, SkinSetting.sticker);

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.comic);
    await tester.pumpAndSettle();

    expect(tokensOfHome().skin, SkinSetting.comic);
    expect(tokensOfHome(), comicTokens);
  });

  testWidgets('MurdokuApp holds the shared delegate const (identity check, '
      'issue 24)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, same(murdokuLocalizationsDelegates));
  });

  testWidgets('navigating to /stats renders the stats placeholder via l10n', (
    tester,
  ) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(context)!;
    GoRouter.of(context).go('/stats');
    await tester.pumpAndSettle();

    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text(l10n.statsTitle), findsOneWidget);
  });

  testWidgets('settings changes keep the navigation stack (issue 76)', (
    tester,
  ) async {
    // Every MurdokuApp rebuild must reuse the same GoRouter: a fresh router
    // on each rebuild resets navigation to '/', kicking the player out of
    // Settings on every theme/skin/language switch (found by the iOS
    // pixel-fidelity capture driver).
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    GoRouter.of(context).go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
