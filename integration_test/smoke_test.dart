import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart' as integration_test;
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/main.dart' show murdokuBootstrap;
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

/// Full-loop smoke test on the real app (default locale — Russian):
/// home → new easy case → place every guest via board taps → auto accuse
/// prompt → correct accusation → victory dialog → back home → daily case.
///
/// Run: `flutter test integration_test/smoke_test.dart -d <device>`
/// (needs a device/emulator — macOS/iOS builds additionally require Xcode).
void main() {
  integration_test.IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full game loop smoke test', (tester) async {
    await murdokuBootstrap(forcedSeed: 3, skipTutorial: true);
    await tester.pumpAndSettle();

    AppLocalizations l10nOf(WidgetTester t) => AppLocalizations.of(
        t.element(find.byType(Scaffold).first))!;
    final l10n = l10nOf(tester);

    ProviderContainer containerOf(WidgetTester t) =>
        ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

    // New case → difficulty sheet → Easy (no save exists: no discard dialog).
    await tester.tap(find.text(l10n.newCase));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.difficultyEasy).last);
    await tester.pumpAndSettle();
    final state = containerOf(tester).read(gameControllerProvider)!;
    expect(state, isNotNull);

    // Furniture is on the board.
    expect(find.byType(ItemSprite), findsWidgets);
    expect(find.byType(SuspectPanel), findsOneWidget);

    // Place every guest at their solution cell through real board taps,
    // selecting each suspect through the controller (the strip-scroll stays
    // out of the smoke path).
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final cell = boardRect.width / state.caseData.gridSize;
    Offset cellCenter(int row, int col) => Offset(
        boardRect.left + (col + 0.5) * cell,
        boardRect.top + (row + 0.5) * cell);

    final names = NameForms.forLocale(l10n.localeName, state.caseData);
    for (final entry in state.caseData.solution.entries) {
      containerOf(tester)
          .read(gameControllerProvider.notifier)
          .selectSuspect(entry.key);
      await tester.pumpAndSettle();
      await tester.tapAt(cellCenter(entry.value.row, entry.value.col));
      await tester.pumpAndSettle();
    }

    // Board solved → the accuse sheet opens automatically.
    final murdererName = names.nom(state.caseData.murdererId);
    await tester.tap(find.text(murdererName).last);
    await tester.pumpAndSettle();

    // Victory dialog → Done → back home.
    expect(find.text(l10n.victoryTitle), findsOneWidget);
    await tester.tap(find.text(l10n.victoryDone));
    await tester.pumpAndSettle();

    final wonState = containerOf(tester).read(gameControllerProvider)!;
    expect(wonState.phase, GamePhase.won);

    // Daily card leads into a fresh daily case.
    await tester.tap(find.text(l10n.dailyCase));
    await tester.pumpAndSettle();
    final daily = containerOf(tester).read(gameControllerProvider)!;
    expect(daily.isDaily, isTrue);
  });
}
