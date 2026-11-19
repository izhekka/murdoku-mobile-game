import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart' as integration_test;
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/main.dart' show murdokuBootstrap;
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';

/// Full-loop smoke test on the real app: home → new easy case → place every
/// guest via board taps → auto accuse prompt → correct accusation → victory
/// dialog → back home → daily card reachable.
///
/// Run: `flutter test integration_test/smoke_test.dart -d <device>`
/// (needs a device/emulator — macOS/iOS builds additionally require Xcode).
void main() {
  // NOTE: the brew-cask Flutter SDK ships an integration_test copy the Dart
  // analyzer mis-resolves (class exists at packages/integration_test/lib/
  // integration_test.dart:45 but the analyzer claims it is undefined).
  // Compilation on a device is the authoritative check; this ignore keeps
  // `flutter analyze` clean until the SDK packaging is fixed.
  // ignore: undefined_prefixed_name
  integration_test.IntegrationTestWidgetsBinding.ensureInitialized();

  testWidgets('full game loop smoke test', (tester) async {
    await murdokuBootstrap(forcedSeed: 3);
    await tester.pumpAndSettle();

    // First launch: dismiss the tutorial if present.
    final gotIt = find.text('Got it');
    if (tester.any(gotIt)) {
      await tester.tap(gotIt.last);
      await tester.pumpAndSettle();
    }

    ProviderContainer containerOf(WidgetTester t) =>
        ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

    // New case → difficulty sheet → Easy (no save exists: no discard dialog).
    await tester.tap(find.text('New case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy').last);
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(gameControllerProvider), isNotNull);

    // Place every guest at their solution cell through real board taps,
    // selecting each suspect through the controller (the strip-scroll stays
    // out of the smoke path).
    final state = containerOf(tester).read(gameControllerProvider)!;
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final cell = boardRect.width / state.caseData.gridSize;
    Offset cellCenter(int row, int col) => Offset(
        boardRect.left + (col + 0.5) * cell,
        boardRect.top + (row + 0.5) * cell);

    for (final entry in state.caseData.solution.entries) {
      containerOf(tester)
          .read(gameControllerProvider.notifier)
          .selectSuspect(entry.key);
      await tester.pumpAndSettle();
      await tester.tapAt(cellCenter(entry.value.row, entry.value.col));
      await tester.pumpAndSettle();
    }

    // Board solved → the accuse sheet opens automatically.
    final murdererName = state.caseData.suspects
        .firstWhere((s) => s.id == state.caseData.murdererId)
        .name;
    await tester.tap(find.text(murdererName).last);
    await tester.pumpAndSettle();

    // Victory dialog → Done → back home.
    expect(find.text('Case closed!'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(gameControllerProvider), isNull);

    // Daily card leads into a fresh daily case.
    await tester.tap(find.text('Daily case'));
    await tester.pumpAndSettle();
    final daily = containerOf(tester).read(gameControllerProvider)!;
    expect(daily.isDaily, isTrue);
  });
}
