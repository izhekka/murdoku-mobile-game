import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/screens/how_to_play_screen.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:murdoku/ui/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/seeded_overrides.dart';

void main() {
  /// Pump the real buildRouter() app with the first-launch tutorial already
  /// dismissed, so the home menu rows can be tapped directly (the tutorial
  /// has its own test suite).
  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PrefsRepository(prefs).saveTutorialSeen(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Issue 75: the home menu entry for one of the three secondary screens
  /// must PUSH the screen (a real back affordance in the AppBar), and the
  /// back affordance must pop the router all the way back to `/`.
  Future<void> expectBackRoundTrip(
    WidgetTester tester, {
    required String Function(AppLocalizations l10n) entryTitle,
    required Type screenType,
  }) async {
    await pumpApp(tester);
    final home = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(home)!;

    await tester.tap(find.text(entryTitle(l10n)));
    await tester.pumpAndSettle();
    expect(find.byType(screenType), findsOneWidget);
    // AC wording: "the AppBar exposes a back affordance" — scope the check
    // to the AppBar, where automaticallyImplyLeading renders the back
    // button on the pushed screen (Home, the root, has none).
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackButton),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final after = tester.element(find.byType(HomeScreen));
    expect(
      GoRouter.of(after).routerDelegate.currentConfiguration.uri.path,
      '/',
    );
  }

  testWidgets(
    'how-to-play menu entry pushes a screen with a working back affordance',
    (tester) async {
      await expectBackRoundTrip(
        tester,
        entryTitle: (l10n) => l10n.howToPlayTitle,
        screenType: HowToPlayScreen,
      );
    },
  );

  testWidgets(
    'stats menu entry pushes a screen with a working back affordance',
    (tester) async {
      await expectBackRoundTrip(
        tester,
        entryTitle: (l10n) => l10n.statsTitle,
        screenType: StatsScreen,
      );
    },
  );

  testWidgets(
    'settings menu entry pushes a screen with a working back affordance',
    (tester) async {
      await expectBackRoundTrip(
        tester,
        entryTitle: (l10n) => l10n.settingsTitle,
        screenType: SettingsScreen,
      );
    },
  );
}
