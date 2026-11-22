import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/format.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

final CaseData fixedCase = generateCase(difficulty: Difficulty.easy, seed: 3);

late ProviderContainer container;

Future<void> pumpGame(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double textScale = 1.0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    final murdererName = names.nom(fixedCase.murdererId);
    await tester.tap(find.text(murdererName).last);
    await tester.pumpAndSettle();

    expect(find.byType(VictoryDialog), findsOneWidget);
    expect(find.text(l10n.victoryTitle), findsOneWidget);
    expect(find.textContaining(l10n.victoryTime('')), findsOneWidget);
    expect(find.text(l10n.victoryMistakes(0)), findsOneWidget);
  });

  testWidgets('accuse sheet lists suspects by their localized names (review)',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);

    await tester.tap(find.byIcon(Icons.gavel));
    await tester.pumpAndSettle();
    expect(find.byType(AccuseSheet), findsOneWidget);
    for (final s in fixedCase.suspects) {
      expect(
        find.descendant(
            of: find.byType(AccuseSheet),
            matching: find.text(names.nom(s.id))),
        findsOneWidget,
        reason: 'accuse tile for ${s.id} shows the localized name',
      );
    }
  });

  testWidgets('wrong accusation shows the alibi snackbar and bumps mistakes',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);

    final innocent = fixedCase.suspects
        .map((s) => s.id)
        .firstWhere((id) => id != fixedCase.murdererId);

    await tester.tap(find.byIcon(Icons.gavel));
    await tester.pumpAndSettle();
    final innocentName = names.nom(innocent);
    expect(find.byType(AccuseSheet), findsOneWidget);
    final sheetName = find.descendant(
        of: find.byType(AccuseSheet), matching: find.text(innocentName));
    expect(sheetName.evaluate().length, 1,
        reason: 'innocent tile appears exactly once in the sheet');
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

  testWidgets('toolbar buttons show visible labels (UX-5)', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    for (final label in [
      l10n.toolPlace,
      l10n.toolMark,
      l10n.toolErase,
      l10n.toolUndo,
      l10n.toolCheck,
      l10n.toolHint,
      l10n.toolAccuse,
    ]) {
      expect(find.text(label), findsWidgets,
          reason: 'toolbar label "$label" must be visible under the icon');
    }
  });

  testWidgets('toolbar buttons expose semantic button labels (UX-5)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    final node = tester.getSemantics(find.text(l10n.toolAccuse));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains(l10n.toolAccuse));
    semantics.dispose();
  });

  testWidgets('timer text exposes difficulty + time semantics (UX-5)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    final timerNode =
        tester.getSemantics(find.textContaining('·').first);
    expect(timerNode.label,
        l10n.timerSemantics(l10n.difficultyEasy, formatDuration(Duration.zero)));
    semantics.dispose();
  });

  testWidgets('whole game screen at textScale 2.0 has no overflow (F-7)',
      (tester) async {
    // Phone viewport, scale 2.0: the suspect grid's clue text must
    // ellipsize (never overflow), toolbar labels shrink, board keeps its
    // layout. Any RenderFlex overflow throws and fails this test.
    await pumpGame(
      tester,
      size: const Size(412, 915),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);

    // The suspect panel still shows every card (clue text truncated, not
    // hidden behind an exception). Names resolve through the active locale.
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    for (final s in fixedCase.suspects) {
      expect(find.text(names.nom(s.id)), findsWidgets,
          reason: 'suspect ${s.id} card present at textScale 2.0');
    }
  });

  testWidgets('board sits flush above a full-height suspect panel (UX-6/UX-9)',
      (tester) async {
    await pumpGame(tester, size: const Size(412, 915));
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final gridRect = tester.getRect(find.byType(GridView));
    expect(boardRect.bottom, closeTo(gridRect.top, 8),
        reason: 'no dead vertical gap between board and suspect panel');
    // The panel fills the space under the board instead of the old fixed
    // 205px slot (UX-9): no dead band above the map, panel at least 240px.
    expect(gridRect.height, greaterThanOrEqualTo(240));
  });

  testWidgets('small viewport 320x569 does not overflow (UX-6)',
      (tester) async {
    await pumpGame(tester, size: const Size(320, 569));
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final gridRect = tester.getRect(find.byType(GridView));
    expect(boardRect.bottom, closeTo(gridRect.top, 8),
        reason: 'board stays flush with the panel on small screens');
  });

  testWidgets('longest clue renders in full on its expanded card (UX-9)',
      (tester) async {
    await pumpGame(tester, size: const Size(412, 915));
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    final rendered = [
      for (final clue in fixedCase.clues)
        (suspectId: clue.suspectId,
            text: describeClue(clue, fixedCase, l10n, names)),
    ];
    final longest =
        rendered.reduce((a, b) => a.text.length >= b.text.length ? a : b);

    container
        .read(gameControllerProvider.notifier)
        .selectSuspect(longest.suspectId);
    await tester.pumpAndSettle();

    expect(find.text(longest.text), findsOneWidget,
        reason: 'the longest clue is fully rendered on the expanded card');
  });
}
