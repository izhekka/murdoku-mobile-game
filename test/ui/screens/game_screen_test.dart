import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

final CaseData fixedCase = generateCase(difficulty: Difficulty.easy, seed: 3);

late ProviderContainer container;

Future<void> pumpGame(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  container.read(gameControllerProvider.notifier).startNewCase(
        Difficulty.easy,
        seed: 3,
      );
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MurdokuApp(),
  ));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/game');
  await tester.pumpAndSettle();
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

Future<void> tapCell(WidgetTester tester, int row, int col) async {
  final boardRect = tester.getRect(find.byKey(const Key('board_view')));
  final cell = boardRect.width / fixedCase.gridSize;
  await tester.tapAt(Offset(
    boardRect.left + (col + 0.5) * cell,
    boardRect.top + (row + 0.5) * cell,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('solving the board opens the accuse prompt', (tester) async {
    await pumpGame(tester);
    final notifier = container.read(gameControllerProvider.notifier);

    for (final entry in fixedCase.solution.entries) {
      notifier.selectSuspect(entry.key);
      await tester.pumpAndSettle();
      await tapCell(tester, entry.value.row, entry.value.col);
    }
    final state = container.read(gameControllerProvider)!;
    expect(state.placed.length, fixedCase.suspects.length);

    // Auto-prompt: accuse sheet appears when the board is solved.
    expect(find.text(l10nOf(tester).accuseTitle), findsOneWidget);
  });

  testWidgets('accusing the murderer wins and shows the victory dialog',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);

    for (final entry in fixedCase.solution.entries) {
      notifier.selectSuspect(entry.key);
      await tester.pumpAndSettle();
      await tapCell(tester, entry.value.row, entry.value.col);
    }
    await tester.pumpAndSettle();

    final murdererName = fixedCase.suspects
        .firstWhere((s) => s.id == fixedCase.murdererId)
        .name;
    await tester.tap(find.text(murdererName).last);
    await tester.pumpAndSettle();

    expect(find.byType(VictoryDialog), findsOneWidget);
    expect(find.text(l10n.victoryTitle), findsOneWidget);
    expect(find.textContaining('Time:'), findsOneWidget);
    expect(find.text(l10n.victoryMistakes(0)), findsOneWidget);
  });

  testWidgets('wrong accusation shows the alibi snackbar and bumps mistakes',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    final innocent = fixedCase.suspects
        .map((s) => s.id)
        .firstWhere((id) => id != fixedCase.murdererId);

    await tester.tap(find.byIcon(Icons.gavel));
    await tester.pumpAndSettle();
    final innocentName =
        fixedCase.suspects.firstWhere((s) => s.id == innocent).name;
    expect(find.byType(AccuseSheet), findsOneWidget);
    final sheetName = find.descendant(
        of: find.byType(AccuseSheet), matching: find.text(innocentName));
    expect(sheetName.evaluate().length, 1,
        reason: 'debug: innocent tile count in sheet');
    await tester.tap(sheetName.first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.alibi(innocentName)), findsOneWidget);
    final state = container.read(gameControllerProvider)!;
    expect(state.wrongAccusations, 1);
    expect(state.phase, GamePhase.playing);
  });

  testWidgets('check tool reports correct count via snackbar', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);

    final first = fixedCase.solution.entries.first;
    notifier.selectSuspect(first.key);
    await tester.pumpAndSettle();
    await tapCell(tester, first.value.row, first.value.col);

    await tester.tap(find.byIcon(Icons.fact_check));
    await tester.pumpAndSettle();
    expect(find.text(l10n.checkResult(1, 5)), findsOneWidget);
  });

  testWidgets('lifecycle hidden pauses the timer; visible resumes',
      (tester) async {
    await pumpGame(tester);

    await tester.pump(const Duration(seconds: 2));
    expect(container.read(gameControllerProvider)!.elapsed,
        const Duration(seconds: 2));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 5));
    expect(container.read(gameControllerProvider)!.elapsed,
        const Duration(seconds: 2), reason: 'paused while hidden');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(gameControllerProvider)!.elapsed,
        const Duration(seconds: 3));
  });

  testWidgets('undo button reverses a placement', (tester) async {
    await pumpGame(tester);
    final notifier = container.read(gameControllerProvider.notifier);
    final first = fixedCase.solution.entries.first;
    notifier.selectSuspect(first.key);
    await tester.pumpAndSettle();
    await tapCell(tester, first.value.row, first.value.col);
    expect(container.read(gameControllerProvider)!.placed.length, 1);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(container.read(gameControllerProvider)!.placed, isEmpty);
  });

  testWidgets('reveal via toolbar forfeits and shows the truth',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.revealSolution).last);
    await tester.pumpAndSettle();

    final state = container.read(gameControllerProvider)!;
    expect(state.phase, GamePhase.revealed);
    expect(state.placed, fixedCase.solution);
  });
}
