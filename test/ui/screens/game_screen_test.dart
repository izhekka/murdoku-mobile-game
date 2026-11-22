import 'dart:convert';

import 'package:flutter/rendering.dart';
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
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

final CaseData fixedCase = generateCase(difficulty: Difficulty.easy, seed: 3);

/// Standard cases always carry a negated clue (issue #10 caps it at 1);
/// issue 16 proves the negated clue template renders on the real game
/// screen, not just in hand-built suspect-panel fixtures.
final CaseData standardCase =
    generateCase(difficulty: Difficulty.standard, seed: 3);

late ProviderContainer container;

Future<void> pumpGame(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double textScale = 1.0,
  LanguageSetting language = LanguageSetting.russian,
  Difficulty difficulty = Difficulty.easy,
  int seed = 3,
}) async {
  SharedPreferences.setMockInitialValues({
    'murdoku.settings': jsonEncode(Settings(language: language).toJson()),
  });
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
        difficulty,
        seed: seed,
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

/// Places the first solution guest through the real select + tap flow.
Future<void> placeFirstGuest(WidgetTester tester) async {
  final notifier = container.read(gameControllerProvider.notifier);
  final first = fixedCase.solution.entries.first;
  notifier.selectSuspect(first.key);
  await tester.pumpAndSettle();
  await tapCell(tester, first.value.row, first.value.col);
}

/// Ideal (unclamped) height the paragraph's text needs at its laid-out
/// width: a rendered paragraph shorter than this is being clipped.
double idealParagraphHeight(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.size.width);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Issue 15 no-clipping property for a name row paragraph: the box must be
/// at least the name's ideal height at its laid-out width, and no word may
/// be width-cut (single-word pool names cannot wrap).
void expectNameParagraphInFull(
  WidgetTester tester,
  String name, {
  required String suspectId,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byType(SuspectPanel),
      matching: find.text(name),
    ),
  );
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
    reason:
        'name of $suspectId ("$name") renders in full on the wide side panel',
  );
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(
        paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5),
    reason:
        'name of $suspectId ("$name") is not truncated on the wide side panel',
  );
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

  testWidgets(
      'wide landscape window keeps the board square and the bottom row '
      'tappable (smoke regression, UX-10)', (tester) async {
    await pumpGame(tester, size: const Size(1200, 896));
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // The board is square by construction. On a landscape window its slot
    // is wider than tall, so the grid must shrink to the available height
    // — a height-clamped box silently clips the bottom row and its cells
    // stop receiving taps.
    expect(boardRect.height, boardRect.width,
        reason: 'board_view must stay square on landscape windows');

    // A guest can actually be placed in the bottom row through a real tap.
    // Pick a bottom-row cell the case leaves empty (not the victim's, not
    // under an object) so the place tool accepts it.
    final lastRow = fixedCase.gridSize - 1;
    final freeCol = [
      for (var col = 0; col < fixedCase.gridSize; col++)
        if (fixedCase.victimPos != (row: lastRow, col: col) &&
            fixedCase.objects.every((o) => o.pos != (row: lastRow, col: col)))
          col,
    ].first;
    final cell = boardRect.width / fixedCase.gridSize;
    final firstId = fixedCase.suspects.first.id;
    container.read(gameControllerProvider.notifier).selectSuspect(firstId);
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(
      boardRect.left + (freeCol + 0.5) * cell,
      boardRect.top + (lastRow + 0.5) * cell,
    ));
    await tester.pumpAndSettle();
    final pos = container.read(gameControllerProvider)!.placed[firstId];
    expect(pos?.row, lastRow,
        reason: 'the bottom-row cell must receive the tap on wide layouts');
    expect(pos?.col, freeCol,
        reason: 'the bottom-row cell must receive the tap on wide layouts');
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

  testWidgets('wide side panel renders every clue in full, unclipped (UX-9)',
      (tester) async {
    await pumpGame(tester, size: const Size(1200, 896));
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    // Per suspect, the exact string its unselected card renders:
    // clueTexts.join('\n').
    final joinedBySuspect = <String, String>{};
    for (final clue in fixedCase.clues) {
      final text = describeClue(clue, fixedCase, l10n, names);
      joinedBySuspect[clue.suspectId] = joinedBySuspect[clue.suspectId] == null
          ? text
          : '${joinedBySuspect[clue.suspectId]}\n$text';
    }

    // No suspect is selected yet: every card shows its clue paragraph.
    // The paragraph box must be at least the text's ideal height — anything
    // shorter means the card clipped the text (the pre-fix ~90px tiles did).
    // (Expanded stretches short paragraphs to fill the card, so the box may
    // legitimately be taller than the text.)
    for (final entry in joinedBySuspect.entries) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(entry.value),
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
        reason: 'clue of ${entry.key} renders in full on the wide side panel',
      );
    }

    // Selecting the longest clue's owner keeps it fully rendered on the
    // expanded card (issue acceptance: find.text(fullClue) findsOneWidget).
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

  testWidgets(
      'wide side panel renders every guest name in full, unclipped (issue 15)',
      (tester) async {
    await pumpGame(tester, size: const Size(1200, 896));
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    for (final s in fixedCase.suspects) {
      expectNameParagraphInFull(tester, names.nom(s.id), suspectId: s.id);
    }

    // A placed card carries the 18px check icon; its name row gets ~18px
    // less width — the name must still render in full.
    await placeFirstGuest(tester);
    final first = fixedCase.solution.entries.first.key;
    expectNameParagraphInFull(tester, names.nom(first), suspectId: first);
  });

  testWidgets(
      'wide side panel renders every en guest name in full, unclipped '
      '(issue 15)', (tester) async {
    await pumpGame(
      tester,
      size: const Size(1200, 896),
      language: LanguageSetting.english,
    );
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    expect(l10n.localeName, 'en', reason: 'the en settings choice applies');
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    for (final s in fixedCase.suspects) {
      expectNameParagraphInFull(tester, names.nom(s.id), suspectId: s.id);
    }
  });

  testWidgets('pause menu opens from the toolbar; Resume closes it (issue 11)',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);
    expect(container.read(gameControllerProvider)!.placed.length, 1);

    await tester.tap(find.text(l10n.pauseMenuTitle).first);
    await tester.pumpAndSettle();
    expect(find.text(l10n.resume), findsOneWidget);
    expect(find.text(l10n.howToPlayTitle), findsOneWidget);
    expect(find.text(l10n.settingsTitle), findsOneWidget);
    expect(find.text(l10n.abandonCase), findsOneWidget);

    // Opening the sheet is not a timer pause (issue #11, out of scope).
    final before = container.read(gameControllerProvider)!.elapsed;
    await tester.pump(const Duration(seconds: 2));
    expect(container.read(gameControllerProvider)!.elapsed, greaterThan(before),
        reason: 'the elapsed timer keeps running while the sheet is open');

    await tester.tap(find.text(l10n.resume));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resume), findsNothing);
    expect(container.read(gameControllerProvider)!.placed.length, 1,
        reason: 'Resume leaves the game state untouched');
  });

  testWidgets(
      'pause menu: How to play pushes above the game; Back returns with the '
      'guest still placed (issue 11)', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);

    await tester.tap(find.text(l10n.pauseMenuTitle).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.howToPlayTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.rule1Text), findsOneWidget,
        reason: 'How to play opens above the running case');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(l10n.rule1Text), findsNothing);
    expect(container.read(gameControllerProvider)!.placed.length, 1,
        reason: 'Back returns to the game with board placement intact');
    expect(find.text(l10n.pauseMenuTitle), findsOneWidget,
        reason: 'the game screen is back on top');
  });

  testWidgets(
      'pause menu: Settings pushes above the game; Back returns with the '
      'guest still placed (issue 11)', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);

    await tester.tap(find.text(l10n.pauseMenuTitle).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.themeModeLabel), findsOneWidget,
        reason: 'Settings opens above the running case');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(l10n.themeModeLabel), findsNothing);
    expect(container.read(gameControllerProvider)!.placed.length, 1,
        reason: 'Back returns to the game with board placement intact');
  });

  testWidgets(
      'pause menu: Abandon case shows the exit dialog; cancelling returns to '
      'the game (issue 11)', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);

    await tester.tap(find.text(l10n.pauseMenuTitle).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.abandonCase));
    await tester.pumpAndSettle();
    expect(find.text(l10n.quitConfirmTitle), findsOneWidget,
        reason: 'Abandon case reuses the existing exit dialog');

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.quitConfirmTitle), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(container.read(gameControllerProvider)!.placed.length, 1,
        reason: 'cancelling returns to the running game');
  });

  testWidgets('pause menu: confirming Abandon case quits to home (issue 11)',
      (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);

    await tester.tap(find.text(l10n.pauseMenuTitle).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.abandonCase));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.quitCase));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(container.read(gameControllerProvider), isNull,
        reason: 'confirming abandon quits the case');
  });

  testWidgets('toolbar tooltips describe their own buttons (issue 17)',
      (tester) async {
    for (final language in [LanguageSetting.russian, LanguageSetting.english]) {
      await pumpGame(tester, language: language);
      final l10n = l10nOf(tester);

      String tooltipOf(String label) => tester
          .widget<Tooltip>(find
              .ancestor(of: find.text(label), matching: find.byType(Tooltip))
              .first)
          .message!;

      expect(tooltipOf(l10n.toolPlace), l10n.toolPlace,
          reason: 'Place announces its own action ($language)');
      expect(tooltipOf(l10n.toolMark), l10n.stateExcluded,
          reason: 'Mark keeps its state description ($language)');
      expect(tooltipOf(l10n.toolErase), l10n.toolErase,
          reason: 'Erase announces its own action ($language)');
      expect(tooltipOf(l10n.toolUndo), l10n.toolUndo,
          reason: 'Undo announces its own action ($language)');
      expect(tooltipOf(l10n.toolCheck), l10n.toolCheckTooltip,
          reason: 'Check has a dedicated tooltip ($language)');
      expect(tooltipOf(l10n.toolHint), l10n.hintsLeft(2),
          reason: 'Hint keeps its hints-left tooltip ($language)');
      expect(tooltipOf(l10n.toolAccuse), l10n.accuse,
          reason: 'Accuse announces its own action ($language)');
      expect(tooltipOf(l10n.pauseMenuTitle), l10n.pauseMenuTitle,
          reason: 'Pause announces its own action ($language)');
    }
  });

  testWidgets('a negated clue renders on the game screen (issue 16)',
      (tester) async {
    await pumpGame(tester, difficulty: Difficulty.standard);
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, standardCase);

    final negated = standardCase.clues.where((c) => c.negated).toList();
    expect(negated, isNotEmpty,
        reason: 'standard cases always carry a negated clue (issue #10)');
    final text = describeClue(negated.first, standardCase, l10n, names);
    expect(negated.first.negated, isTrue);

    // The positive counterpart of the same predicate must render through the
    // *Not template, not the plain one: both strings differ only by the
    // negation («не»), so finding the negated one and not the positive one
    // proves the negated rendering path is what ran.
    final positive = switch (negated.first) {
      InRoom(:final suspectId, :final roomId) =>
        InRoom(suspectId: suspectId, roomId: roomId, negated: false),
      SameRow(:final suspectId, :final targetId) =>
        SameRow(suspectId: suspectId, targetId: targetId, negated: false),
      SameCol(:final suspectId, :final targetId) =>
        SameCol(suspectId: suspectId, targetId: targetId, negated: false),
      DirectionClue(
        :final suspectId,
        :final targetId,
        :final direction,
      ) =>
        DirectionClue(
            suspectId: suspectId,
            targetId: targetId,
            direction: direction,
            negated: false),
      Beside(:final suspectId, :final targetId) =>
        Beside(suspectId: suspectId, targetId: targetId, negated: false),
      BesideObject(:final suspectId, :final objectId) =>
        BesideObject(suspectId: suspectId, objectId: objectId, negated: false),
    };
    final positiveText = describeClue(positive, standardCase, l10n, names);
    expect(positiveText, isNot(text),
        reason: 'the negated and positive templates must differ');

    container
        .read(gameControllerProvider.notifier)
        .selectSuspect(negated.first.suspectId);
    await tester.pumpAndSettle();

    expect(find.text(text), findsOneWidget,
        reason: 'the negated clue template renders on the real game screen');
    expect(find.text(positiveText), findsNothing,
        reason: 'the plain (non-negated) template of the same predicate '
            'must not stand in for the negated one');
  });
}
