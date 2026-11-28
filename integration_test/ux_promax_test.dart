import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart' as integration_test;
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/main.dart' show murdokuBootstrap;
import 'package:murdoku/state/game_controller.dart';

/// One-time Pro Max ru overflow sanity check (issue 76): captures the board
/// mid-game, how-to-play scrolled to the bottom and a populated stats screen
/// in Russian with the default (light) settings, so the longest-text screens
/// are checked for RenderFlex overflows / clipped text on the larger phone.
///
/// Run like `integration_test/ux_capture_test.dart`, with the marker loop
/// pointed at the Pro Max UDID (BB7FB6F1-01F0-4AA5-8A64-AAE12FE4A3FB) and
/// this file's log.
void main() {
  integration_test.IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pro Max ru overflow sanity check', (tester) async {
    final originalErrorWidgetBuilder = ErrorWidget.builder;
    final bootSemanticsHandle = await murdokuBootstrap(
      forcedSeed: 3,
      skipTutorial: true,
    );
    await tester.pumpAndSettle();

    AppLocalizations l10nOf(WidgetTester t) =>
        AppLocalizations.of(t.element(find.byType(Scaffold).last))!;
    var l10n = l10nOf(tester);

    Future<void> shot(String name) async {
      debugPrint('[UX] promax_$name');
      await Future<void>.delayed(const Duration(milliseconds: 2500));
    }

    // Reset any progress left over from previous installs (the flutter tool
    // keeps the app container between failed integration runs) through the
    // real settings UI, so no active save blocks the first new case.
    await tester.tap(find.text(l10n.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetProgress));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, l10n.resetProgress));
    await tester.pumpAndSettle();
    // The progressReset snackbar auto-dismisses after ~4s; wait it out.
    await Future<void>.delayed(const Duration(seconds: 5));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 1. Board mid-game in ru: start a new easy case, make one placement.
    void step(String label) =>
        print('PROMAX step $label'); // ignore: avoid_print
    l10n = l10nOf(tester);
    await tester.tap(find.text(l10n.newCase));
    await tester.pumpAndSettle();
    step(
      'tap easy; easyText=${tester.widgetList(find.text(l10n.difficultyEasy)).length} chooseDifficulty=${tester.widgetList(find.text(l10n.chooseDifficulty)).length}',
    );
    await tester.tap(find.text(l10n.difficultyEasy).last);
    // Debug-mode case generation blocks the main thread 60-90s (known
    // non-bug) — pumpAndSettle waits it out.
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    final state = container.read(gameControllerProvider);
    final midGameState = state!;
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final cell = boardRect.width / midGameState.caseData.gridSize;
    final first = midGameState.caseData.solution.entries.first;
    container.read(gameControllerProvider.notifier).selectSuspect(first.key);
    await tester.pumpAndSettle();
    await tester.tapAt(
      Offset(
        boardRect.left + (first.value.col + 0.5) * cell,
        boardRect.top + (first.value.row + 0.5) * cell,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool_hint')), findsOneWidget);
    await shot('board_ru_light');

    // 2. How-to-play scrolled to the bottom in ru (via the pause sheet's
    // real push, so Back returns into the running case).
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.pause),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.howToPlayTitle).last);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text(l10n.glossaryDirections),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await shot('htp_ru_light');
    // Real back affordance: plain-AppBar Material BackButton (tester
    // pageBack would expect a Cupertino one and throw).
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Back into the game screen (the pause sheet popped on navigation).

    // 3. Abandon the case so stats can be populated by a fresh win, then
    // win one easy case and capture the populated stats.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.pause),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.abandonCase).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.quitCase).last);
    await tester.pumpAndSettle();
    // Now on home with no save; start a fresh case and solve it fully
    // through real board taps, then confirm the accusation.
    // (Same solve loop as ux_capture_test.dart but with a win.)
    l10n = l10nOf(tester);
    await tester.tap(find.text(l10n.newCase));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.difficultyEasy).last);
    await tester.pumpAndSettle();
    final state3 = container.read(gameControllerProvider)!;
    final boardRect2 = tester.getRect(find.byKey(const Key('board_view')));
    final cell2 = boardRect2.width / state3.caseData.gridSize;
    for (final entry in state3.caseData.solution.entries) {
      container.read(gameControllerProvider.notifier).selectSuspect(entry.key);
      await tester.pumpAndSettle();
      await tester.tapAt(
        Offset(
          boardRect2.left + (entry.value.col + 0.5) * cell2,
          boardRect2.top + (entry.value.row + 0.5) * cell2,
        ),
      );
      await tester.pumpAndSettle();
    }
    // The solved transition auto-opens the accuse sheet: pick the murderer
    // to trigger the victory dialog (name lookup in the current locale).
    expect(find.text(l10n.accuseTitle), findsOneWidget);
    final names = NameForms.forLocale(l10n.localeName, state3.caseData);
    await tester.tap(find.text(names.nom(state3.caseData.murdererId)).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.victoryTitle), findsOneWidget);
    await tester.tap(find.text(l10n.victoryDone));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.statsTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.statsEmpty), findsNothing);
    await shot('stats_ru_light');

    // Restore the globals the boot changed (framework-checked).
    ErrorWidget.builder = originalErrorWidgetBuilder;
    bootSemanticsHandle.dispose();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
