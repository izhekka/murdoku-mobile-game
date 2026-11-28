import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart' as integration_test;
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/main.dart' show murdokuBootstrap;
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

/// iOS-simulator pixel-fidelity capture matrix (issue 76).
///
/// Drives the real app through 15 key states across {en, ru} × {light, dark}
/// on the booted iPhone 18 Pro, printing one `[UX] <name>` marker per state;
/// a mac-side shell loop fires `xcrun simctl io <udid> screenshot` per marker
/// into `build/ux_shots/<screen>.png` with the name parts
/// `<screen>_<state>_<locale>_<mode>` (capture method proven on one state
/// first, recorded in the issue 76 run report: the marker+simctl loop was
/// chosen over binding.takeScreenshot because the plugin render lacks the
/// system status bar/home indicator that rubric item 1 reviews and drifts
/// in color; screenshots stay uncommitted build/ artifacts).
///
/// Locale and theme switches go through the real Settings UI (segmented
/// controls). Dark mode only exists on the classic skin (`lib/app.dart`
/// forces light for cartoon skins), so dark sweeps additionally switch the
/// skin to classic — that is the app's only true dark mode.
///
/// Run: `flutter test integration_test/ux_capture_test.dart -d <sim-UDID>`
/// with a mac-side tail loop on the log grepping `\[UX\] <name>`.
void main() {
  integration_test.IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS pixel-fidelity capture matrix', (tester) async {
    // The boot configures process-wide globals the test framework verifies
    // as unchanged after a test. Snapshot and restore (smoke-test pattern).
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    final bootSemanticsHandle = await murdokuBootstrap(
      forcedSeed: 3,
      skipTutorial: true,
    );
    await tester.pumpAndSettle();

    AppLocalizations l10nOf(WidgetTester t) =>
        AppLocalizations.of(t.element(find.byType(Scaffold).last))!;
    ProviderContainer containerOf(WidgetTester t) =>
        ProviderScope.containerOf(t.element(find.byType(Scaffold).last));

    // Assertions for pushed SCREEN content scope to the topmost page
    // scaffold: home stays mounted below it and repeats some texts.
    Finder onTop(Finder finder) =>
        find.descendant(of: find.byType(Scaffold).last, matching: finder);

    var l10n = l10nOf(tester);
    final captured = <String>[];
    const holdPerShot = Duration(milliseconds: 2500);

    /// One marker line per state; the mac-side loop captures each.
    Future<void> shot(String name) async {
      captured.add(name);
      debugPrint('[UX] $name');
      await Future<void>.delayed(holdPerShot);
    }

    /// Closes a modal sheet/dialog by tapping the barrier near the top.
    Future<void> dismissModal() async {
      await tester.tapAt(const Offset(24, 120));
      await tester.pumpAndSettle();
    }

    /// Pushes one of the plain-AppBar screens via the home menu card.
    Future<void> pushFromHome(String titleText) async {
      await tester.tap(find.text(titleText));
      await tester.pumpAndSettle();
    }

    /// Real back affordance (issue 75: these screens are pushed). The
    /// plain-AppBar back button is a Material BackButton (repo-proven
    /// pattern of test/ui/secondary_screen_back_nav_test.dart; flutter_test
    /// pageBack instead expects a Cupertino back button and throws).
    Future<void> pageBackToHome() async {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }

    /// Taps the language segment in the current locale's label; returns
    /// the localizations in the NEW locale.
    Future<AppLocalizations> switchLanguage(LanguageTarget target) async {
      final label = switch (target) {
        LanguageTarget.russian => l10n.languageRussian,
        LanguageTarget.english => l10n.languageEnglish,
      };
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return l10nOf(tester);
    }

    /// Taps the theme and skin segments (in the now-current locale); the
    /// dark mode only exists on the classic skin (cartoon skins force
    /// light, lib/app.dart), the light sweeps restore the shipped default.
    Future<void> switchTheme({required bool dark}) async {
      await tester.tap(find.text(dark ? l10n.themeDark : l10n.themeLight));
      await tester.tap(find.text(dark ? l10n.skinClassic : l10n.skinSticker));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    /// Solves the open easy case like the smoke test does: selects each
    /// suspect through the controller, taps their solution cell by real
    /// board coordinates.
    Future<void> solveOpenCase() async {
      final container = containerOf(tester);
      final state = container.read(gameControllerProvider)!;
      final boardRect = tester.getRect(find.byKey(const Key('board_view')));
      final cell = boardRect.width / state.caseData.gridSize;
      Offset cellCenter(int row, int col) => Offset(
        boardRect.left + (col + 0.5) * cell,
        boardRect.top + (row + 0.5) * cell,
      );
      for (final entry in state.caseData.solution.entries) {
        container
            .read(gameControllerProvider.notifier)
            .selectSuspect(entry.key);
        await tester.pumpAndSettle();
        await tester.tapAt(cellCenter(entry.value.row, entry.value.col));
        await tester.pumpAndSettle();
      }
    }

    // Four capture sweeps: the app is deterministic because every segment
    // is tapped explicitly each sweep and progress is reset through the
    // real settings UI (also a matrix state) at each sweep start.
    const modes = [
      (LanguageTarget.russian, false),
      (LanguageTarget.english, false),
      (LanguageTarget.russian, true),
      (LanguageTarget.english, true),
    ];

    for (final (target, dark) in modes) {
      final locale = switch (target) {
        LanguageTarget.russian => 'ru',
        LanguageTarget.english => 'en',
      };
      final mode = dark ? 'dark' : 'light';
      final p = '${locale}_$mode'; // capture-name suffix
      debugPrint('UXLOG sweep $p starting');

      // 1. Push settings; switch locale/theme/skin for this sweep.
      await pushFromHome(l10n.settingsTitle);
      l10n = await switchLanguage(target);
      await switchTheme(dark: dark);
      l10n = l10nOf(tester); // resolve getters in the NEW locale
      expect(onTop(find.text(l10n.themeModeLabel)), findsOneWidget);
      await shot('settings_plain_$p');

      // 2. Reset progress through the real confirm dialog (wipes
      // saves/stats/daily, keeps settings — sweep determinism).
      await tester.tap(find.text(l10n.resetProgress));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resetConfirmTitle), findsOneWidget);
      await shot('settings_resetConfirm_$p');
      // The dialog's confirm TextButton contains the same text as the
      // settings ListTile behind it — target the TextButton (widgetWithText)
      // so the tile can never be the tap target.
      await tester.tap(find.widgetWithText(TextButton, l10n.resetProgress));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resetConfirmTitle), findsNothing);
      debugPrint(
        'UXDEBUG activeGame=${containerOf(tester).read(prefsRepositoryProvider).loadActiveGame()}',
      );
      // The progressReset snackbar auto-dismisses after ~4s; wait it out.
      await Future<void>.delayed(const Duration(seconds: 5));

      // 3-4. Home (clean: no continue card after reset) → stats empty.
      await pageBackToHome();
      expect(find.text(l10n.continueCase), findsNothing);
      await pushFromHome(l10n.statsTitle);
      expect(onTop(find.text(l10n.statsEmpty)), findsOneWidget);
      await shot('stats_empty_$p');
      await pageBackToHome();

      // 5. how-to-play: plain and scrolled to the bottom.
      await pushFromHome(l10n.howToPlayTitle);
      expect(onTop(find.text(l10n.howToPlayTitle)), findsOneWidget);
      await shot('htp_plain_$p');
      await tester.dragUntilVisible(
        find.text(l10n.glossaryDirections),
        find.byType(ListView).last,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(onTop(find.text(l10n.glossaryDirections)), findsOneWidget);
      await shot('htp_bottom_$p');
      await pageBackToHome();

      // 6. Home plain (freshly reset: no continue card).
      expect(find.text(l10n.appTitle), findsOneWidget);
      await shot('home_plain_$p');

      // 7-8. Difficulty sheet → easy case → game fresh.
      await tester.tap(find.text(l10n.newCase));
      await tester.pumpAndSettle();
      expect(find.text(l10n.chooseDifficulty), findsOneWidget);
      await shot('home_difficulty_$p');
      await tester.tap(find.text(l10n.difficultyEasy).last);
      // Debug-mode case generation blocks the main thread 60-90s
      // (TOOLCHAIN.md Known non-bug) — pumpAndSettle waits it out.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board_view')), findsOneWidget);
      expect(find.byType(SuspectPanel), findsOneWidget);
      await shot('game_fresh_$p');

      // 9. Driver-only hop home with the running case intact: the discard
      // dialog needs an active save while on home, and the real app has no
      // in-UI path from a running case back to home without abandoning it.
      // Everything above and below reaches its state through real UI.
      GoRouter.of(tester.element(find.byType(Scaffold).last)).go('/');
      await tester.pumpAndSettle();

      // 10. New case with an active save → discard dialog → Cancel (the
      // in-progress case must stay for the rest of the sweep).
      await tester.tap(find.text(l10n.newCase));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.difficultyEasy).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.discardTitle), findsOneWidget);
      await shot('home_discard_$p');
      await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
      await tester.pumpAndSettle();

      // 11. Back into the running case through the real Continue card.
      await tester.tap(find.text(l10n.continueCase));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board_view')), findsOneWidget);

      // 12. Pause menu sheet (the app-bar Menu icon, issue 107) → Resume
      // row. (The abandon row is sheet-unique.)
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.pause),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.abandonCase), findsOneWidget);
      await shot('game_pause_$p');
      await tester.tap(find.text(l10n.resume).last);
      await tester.pumpAndSettle();

      // 13. Legend sheet (appbar legend affordance) → barrier dismiss.
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.menu_book),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.legendTitle), findsOneWidget);
      await shot('game_legend_$p');
      await dismissModal();

      // 14. Hint sheet (toolbar pill) → barrier dismiss without using a
      // hint (hints must stay intact for the solve).
      await tester.tap(find.byKey(const Key('tool_hint')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.hintsLeft(2)), findsOneWidget);
      await shot('game_hint_$p');
      await dismissModal();

      // 15. Solve the case → the accuse sheet auto-opens on the solved
      // transition → pick the murderer → victory dialog → Done.
      await solveOpenCase();
      expect(find.text(l10n.accuseTitle), findsOneWidget);
      await shot('game_accuse_$p');
      final state = containerOf(tester).read(gameControllerProvider)!;
      final names = NameForms.forLocale(l10n.localeName, state.caseData);
      await tester.tap(find.text(names.nom(state.caseData.murdererId)).last);
      await tester.pumpAndSettle();
      expect(find.text(l10n.victoryTitle), findsOneWidget);
      await shot('game_win_$p');
      await tester.tap(find.text(l10n.victoryDone));
      await tester.pumpAndSettle();

      // 16. Stats populated by the solved run.
      await pushFromHome(l10n.statsTitle);
      expect(find.text(l10n.statsEmpty), findsNothing);
      await shot('stats_populated_$p');
      await pageBackToHome();

      debugPrint('UXLOG sweep $p complete');
    }

    // Every listed state in all four mode combos was reached and marked.
    const states = [
      'settings_plain',
      'settings_resetConfirm',
      'stats_empty',
      'stats_populated',
      'htp_plain',
      'htp_bottom',
      'home_plain',
      'home_difficulty',
      'home_discard',
      'game_fresh',
      'game_pause',
      'game_legend',
      'game_hint',
      'game_accuse',
      'game_win',
    ];
    final expected = <String>{};
    for (final (target, dark) in modes) {
      final locale = switch (target) {
        LanguageTarget.russian => 'ru',
        LanguageTarget.english => 'en',
      };
      for (final state in states) {
        expected.add('${state}_${locale}_${dark ? 'dark' : 'light'}');
      }
    }
    expect(captured.toSet(), expected);
    expect(captured.length, expected.length);

    // Restore the globals the boot changed (framework-checked).
    ErrorWidget.builder = originalErrorWidgetBuilder;
    bootSemanticsHandle.dispose();
  }, timeout: const Timeout(Duration(minutes: 45)));
}

/// Language preference the sweep switches to through the settings UI.
enum LanguageTarget { russian, english }
