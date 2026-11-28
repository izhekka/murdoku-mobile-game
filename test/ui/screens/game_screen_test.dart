import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/format.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/avatar.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/seeded_overrides.dart';
import '../widgets/suspect_panel_test.dart' show renderedPlainOf;

Pos p(int row, int col) => (row: row, col: col);

final CaseData fixedCase = generateCase(difficulty: Difficulty.easy, seed: 3);

/// Standard cases always carry a negated clue (issue #10 caps it at 1);
/// issue 16 proves the negated clue template renders on the real game
/// screen, not just in hand-built suspect-panel fixtures.
final CaseData standardCase = generateCase(
  difficulty: Difficulty.standard,
  seed: 3,
);

/// The case actually in play, read live from the game controller
/// (issue 22). Tap helpers derive grid geometry and solution entries
/// from it per call, so however the running case was started — through
/// [pumpGame] or through the home-screen UI — taps stay on target and
/// the stale-geometry bug class from issue 19 cannot reappear.
CaseData currentCase() => container.read(gameControllerProvider)!.caseData;

late ProviderContainer container;

Future<void> pumpGame(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double textScale = 1.0,
  LanguageSetting language = LanguageSetting.russian,
  Difficulty difficulty = Difficulty.easy,
  int seed = 3,
  SkinSetting skin = SkinSetting.sticker,
  bool tutorialSeen = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'murdoku.settings': jsonEncode(
      Settings(language: language, skin: skin).toJson(),
    ),
    // The first-run tutorial overlay (tutorial_overlay.dart) overflows at
    // 320px + textScale 2.0 — a pre-existing defect outside issue 27's
    // scope; tests that isolate the suspects header mark it seen.
    if (tutorialSeen) 'murdoku.tutorialSeen': true,
  });
  final prefs = await SharedPreferences.getInstance();
  container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  container
      .read(gameControllerProvider.notifier)
      .startNewCase(difficulty, seed: seed);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/game');
  await tester.pumpAndSettle();
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

Future<void> tapCell(WidgetTester tester, int row, int col) async {
  final boardRect = tester.getRect(find.byKey(const Key('board_view')));
  final cell = boardRect.width / currentCase().gridSize;
  await tester.tapAt(
    Offset(
      boardRect.left + (col + 0.5) * cell,
      boardRect.top + (row + 0.5) * cell,
    ),
  );
  await tester.pumpAndSettle();
}

/// Places the first solution guest through the real select + tap flow.
Future<void> placeFirstGuest(WidgetTester tester) async {
  final notifier = container.read(gameControllerProvider.notifier);
  final first = currentCase().solution.entries.first;
  notifier.selectSuspect(first.key);
  await tester.pumpAndSettle();
  await tapCell(tester, first.value.row, first.value.col);
}

/// Ideal (unclamped) height the paragraph's text needs at its laid-out
/// width: a rendered paragraph shorter than this is being clipped. Uses the
/// render object's own intrinsics so the room chip's placeholder dimensions
/// (issue 104) participate — a standalone TextPainter over the rich span
/// tree would assert without them.
double idealParagraphHeight(RenderParagraph paragraph) =>
    paragraph.computeMaxIntrinsicHeight(paragraph.size.width);

/// Issue 15 no-clipping property for a name row paragraph: the box must be
/// at least the name's ideal height at its laid-out width, and no word may
/// be width-cut (single-word pool names cannot wrap).
void expectNameParagraphInFull(
  WidgetTester tester,
  String name, {
  required String suspectId,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byType(SuspectPanel), matching: find.text(name)),
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
      paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5,
    ),
    reason:
        'name of $suspectId ("$name") is not truncated on the wide side panel',
  );
}

void main() {
  testWidgets('ru library clue sentence wraps without mid-word fragments at '
      'the phone viewport (issue 76, bare text since 89)', (tester) async {
    // Seed re-pinned for the issue-#106 deduction-chain gate: the old
    // seed-9 easy case no longer ships a Library clue — seed 61 is
    // probe-measured (2026-11-28) to ship an InRoom(…poolIndex 1…) card, so
    // the long ru word «библиотек…» still exercises the wrap behavior.
    await pumpGame(
      tester,
      size: const Size(402, 874),
      tutorialSeen: true,
      seed: 61,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(SuspectPanel),
        matching: find.textContaining('библиотек'),
      ),
    );
    // Issue 76 run-1 evidence (per-PNG verdicts travel with the issue's run
    // report): the sticker chip's ~70px text
    // box broke «библиотеке.» mid-word and wrapped the sentence into FOUR
    // lines (~80px); the chip-padding token fix widened the box to ~79px.
    // Since issue 89 the sentences render as bare full-width texts (no chip
    // padding), which only widens the wrap box further — the assertion (at
    // most three lines per word group, no mid-word fragments, pixel-verified
    // by the issue 76 closing re-capture) is pump-checked here by the line
    // count (the test font renders glyphs at fontSize width, so exact
    // word-width comparisons are not faithful here).
    expect(paragraph.size.height, lessThan(72));
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('accusing the murderer wins and shows the victory dialog', (
    tester,
  ) async {
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
    // Scope the tap to the accuse sheet and scroll its list until the tile
    // is reachable: the murderer's name can also appear on displayed clue
    // cards, and its sheet tile can sit below the sheet fold (the fixture
    // case content changed with the issue-61 remap).
    final murdererTile = find.descendant(
      of: find.byType(AccuseSheet),
      matching: find.text(murdererName),
    );
    await tester.scrollUntilVisible(
      murdererTile,
      50,
      scrollable: find.descendant(
        of: find.byType(AccuseSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(murdererTile);
    await tester.pumpAndSettle();

    expect(find.byType(VictoryDialog), findsOneWidget);
    expect(find.text(l10n.victoryTitle), findsOneWidget);
    expect(find.textContaining(l10n.victoryTime('')), findsOneWidget);
    expect(find.text(l10n.victoryMistakes(0)), findsOneWidget);
  });

  testWidgets('accuse sheet lists suspects by their localized names (review)', (
    tester,
  ) async {
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
          matching: find.text(names.nom(s.id)),
        ),
        findsOneWidget,
        reason: 'accuse tile for ${s.id} shows the localized name',
      );
    }
  });

  testWidgets('wrong accusation shows the alibi snackbar and bumps mistakes', (
    tester,
  ) async {
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
      of: find.byType(AccuseSheet),
      matching: find.text(innocentName),
    );
    expect(
      sheetName.evaluate().length,
      1,
      reason: 'innocent tile appears exactly once in the sheet',
    );
    await tester.tap(sheetName.first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.alibi(innocentName)), findsOneWidget);
    final state = container.read(gameControllerProvider)!;
    expect(state.wrongAccusations, 1);
    expect(state.phase, GamePhase.playing);
  });

  testWidgets('lifecycle hidden pauses the timer; visible resumes', (
    tester,
  ) async {
    await pumpGame(tester);

    await tester.pump(const Duration(seconds: 2));
    expect(
      container.read(gameControllerProvider)!.elapsed,
      const Duration(seconds: 2),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 5));
    expect(
      container.read(gameControllerProvider)!.elapsed,
      const Duration(seconds: 2),
      reason: 'paused while hidden',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(gameControllerProvider)!.elapsed,
      const Duration(seconds: 3),
    );
  });

  testWidgets('reveal via the hint sheet forfeits and shows the truth '
      '(issue 107)', (tester) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    expect(
      find.byIcon(Icons.visibility),
      findsNothing,
      reason: 'the app bar has no reveal action anymore',
    );
    await tester.tap(find.byKey(const Key('tool_hint')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.hintPlace), findsOneWidget);
    expect(find.text(l10n.hintEliminate), findsOneWidget);
    expect(find.text(l10n.revealSolution), findsOneWidget);

    await tester.tap(find.text(l10n.revealSolution));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.revealConfirmTitle),
      findsOneWidget,
      reason: 'reveal still asks for confirmation',
    );
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
      l10n.toolHint,
      l10n.toolAccuse,
    ]) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'toolbar label "$label" must be visible under the icon',
      );
    }
  });

  testWidgets('toolbar buttons expose semantic button labels (UX-5)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    final node = tester.getSemantics(find.text(l10n.toolAccuse));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains(l10n.toolAccuse));
    semantics.dispose();
  });

  testWidgets('timer text exposes difficulty + time semantics (UX-5)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpGame(tester);
    final l10n = l10nOf(tester);

    final timerNode = tester.getSemantics(find.textContaining('·').first);
    expect(
      timerNode.label,
      l10n.timerSemantics(l10n.difficultyEasy, formatDuration(Duration.zero)),
    );
    semantics.dispose();
  });

  testWidgets('whole game screen at textScale 2.0 has no overflow (F-7)', (
    tester,
  ) async {
    // Phone viewport, scale 2.0: the suspect grid's clue text must
    // ellipsize (never overflow), toolbar labels shrink, board keeps its
    // layout. Any RenderFlex overflow throws and fails this test.
    await pumpGame(tester, size: const Size(412, 915), textScale: 2.0);
    expect(tester.takeException(), isNull);

    // The suspect panel still shows every card (clue text truncated, not
    // hidden behind an exception). At scale 2.0 the pinned grid's grown rows
    // far exceed the slot (issue 39), so the grid scrolls and lazily builds
    // only the rows inside the viewport's range: assert the first row in
    // place, scroll, then assert the rest. Names resolve through the active
    // locale.
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    for (final s in fixedCase.suspects.take(3)) {
      expect(
        find.text(names.nom(s.id)),
        findsWidgets,
        reason: 'suspect ${s.id} card present at textScale 2.0',
      );
    }
    await tester.drag(
      find.text(names.nom(fixedCase.suspects.first.id)),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    for (final s in fixedCase.suspects.skip(3)) {
      expect(
        find.text(names.nom(s.id)),
        findsWidgets,
        reason: 'suspect ${s.id} card present after scrolling to row 2',
      );
    }

    // The suspects header (issue 27) survives scale 2.0: rendered, one
    // scaled line tall, and inside the viewport so it never pushes the
    // grid cards past the fold.
    expect(find.byKey(suspectsPanelHeaderKey), findsOneWidget);
    final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
    expect(headerRect.width, lessThanOrEqualTo(412.0));
    expect(
      headerRect.height,
      lessThanOrEqualTo(72.0),
      reason: 'the header stays a single scaled line at textScale 2.0',
    );
  });

  testWidgets(
    'suspects header stays inside 320px at scale 2.0, comic uppercase '
    '(issue 27)',
    (tester) async {
      // Worst case: the widest header text (comic's uppercase Cyrillic
      // ПОДОЗРЕВАЕМЫЕ, 13 glyphs) at textScale 2.0 in the smallest viewport.
      // tutorialSeen: the first-run tutorial overlay overflows in this
      // combination (pre-existing, unrelated to the header — see the gap
      // report); the guard isolates the panel layout.
      await pumpGame(
        tester,
        size: const Size(320, 569),
        textScale: 2.0,
        skin: SkinSetting.comic,
        tutorialSeen: true,
      );
      expect(tester.takeException(), isNull);

      expect(
        find.text('ПОДОЗРЕВАЕМЫЕ'),
        findsOneWidget,
        reason: 'the comic skin renders the header uppercase',
      );
      final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
      expect(
        headerRect.width,
        lessThanOrEqualTo(320.0),
        reason: 'the header row fits the 320px viewport',
      );
      expect(
        headerRect.height,
        lessThanOrEqualTo(72.0),
        reason: 'the header does not squeeze the grid at 320px scale 2.0',
      );
      // The grid keeps usable room under the header: cards still lay out
      // without any overflow exception (asserted above).
    },
  );

  testWidgets(
    'board sits flush above a full-height suspect panel (UX-6/UX-9)',
    (tester) async {
      await pumpGame(tester, size: const Size(412, 915));
      expect(tester.takeException(), isNull);

      final boardRect = tester.getRect(find.byKey(const Key('board_view')));
      // The panel's header row (issue 27) is the board's flush neighbor; the
      // grid sits directly under the header with only the grid's own padding.
      final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
      final gridRect = tester.getRect(find.byType(GridView));
      expect(
        boardRect.bottom,
        closeTo(headerRect.top, 8),
        reason: 'no dead vertical gap between board and the panel header',
      );
      expect(
        headerRect.bottom,
        closeTo(gridRect.top, 8),
        reason: 'the header sits directly above the suspect grid',
      );
      // The panel fills the space under the board instead of the old fixed
      // 205px slot (UX-9): no dead band above the map, panel at least 240px.
      expect(gridRect.height, greaterThanOrEqualTo(240));
    },
  );

  testWidgets('narrow game screen gives the board its maximum square at '
      '402x874 (issue 95)', (tester) async {
    await pumpGame(tester, size: const Size(402, 874));
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    expect(
      boardRect.width,
      closeTo(386, 0.5),
      reason: 'board side = viewport width − 2×8 on the reference phone',
    );
    expect(boardRect.height, closeTo(386, 0.5), reason: 'board stays square');
    expect(
      boardRect.left,
      closeTo(8, 0.5),
      reason: "side padding = today's top padding (8)",
    );
    final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
    expect(
      headerRect.top - boardRect.bottom,
      closeTo(8, 0.5),
      reason: 'padded board abuts the panel exactly (no vertical gap)',
    );
  });

  testWidgets('max square holds across the narrow range: 472x800 and '
      '320x568 (issue 95)', (tester) async {
    await pumpGame(tester, size: const Size(472, 800));
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    expect(
      boardRect.width,
      closeTo(456, 0.5),
      reason: '472 viewport ⇒ full-width square 456; panel takes the rest',
    );
    final panelRect = tester.getRect(find.byType(SuspectPanel));
    expect(
      panelRect.height,
      closeTo(212, 0.5),
      reason: 'panel takes the remaining height below the board',
    );

    await pumpGame(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    final small = tester.getRect(find.byKey(const Key('board_view')));
    expect(
      small.width,
      closeTo(304, 1.0),
      reason: '320×568 still fits the full-width square (304)',
    );
    final smallPanel = tester.getRect(find.byType(SuspectPanel));
    expect(
      smallPanel.height,
      closeTo(132, 0.5),
      reason:
          'issue 107: the single-row toolbar frees the old second row — '
          'the panel grows from 72 to 132',
    );
  });

  testWidgets('squat narrow viewport shrinks the board to fit the panel '
      'minimum (issue 95)', (tester) async {
    await pumpGame(tester, size: const Size(320, 460));
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    expect(
      boardRect.width,
      closeTo(256, 1.0),
      reason:
          'leftover 344 − panel min 72 = 272 slot ⇒ square 256 '
          '(issue 107: one toolbar row, not two)',
    );
    final panelRect = tester.getRect(find.byType(SuspectPanel));
    expect(
      panelRect.height,
      closeTo(72, 0.5),
      reason: 'the panel keeps its minimum; the board shrinks instead',
    );
  });

  testWidgets('wide branch pins the board bottom-left; the panel takes the '
      'rest without the header (issue 103)', (tester) async {
    await pumpGame(tester, size: const Size(1024, 768), tutorialSeen: true);
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // Row slot 768 − app bar 56 = 712 tall × (1024 − strip 72) = 952 wide:
    // min(712, 952 − 300) = 652 ⇒ plate 652 − 16 = 636 (issue 107).
    expect(boardRect.width, closeTo(636, 0.5));
    expect(boardRect.height, closeTo(636, 0.5));
    expect(
      boardRect.left,
      closeTo(8, 0.5),
      reason: 'the board hugs the left screen edge (no dead band)',
    );
    final panelRect = tester.getRect(find.byType(SuspectPanel));
    expect(
      panelRect.width,
      closeTo(300, 0.5),
      reason:
          'the panel keeps its minimum width; the strip takes the rest '
          '(issue 107)',
    );
    expect(
      find.byKey(suspectsPanelHeaderKey),
      findsNothing,
      reason: 'the landscape game screen drops the suspects header',
    );

    // Portrait control: the narrow branch keeps the header.
    await pumpGame(tester, size: const Size(402, 874), tutorialSeen: true);
    expect(find.byKey(suspectsPanelHeaderKey), findsOneWidget);
  });

  testWidgets('852x393 reference: board footprint 321 at the left edge, '
      'panel between board and strip, no header (issue 103/107)', (
    tester,
  ) async {
    await pumpGame(tester, size: const Size(852, 393), tutorialSeen: true);
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // Row slot 393 − app bar 56 = 337 tall × (852 − strip 72) = 780 wide:
    // min(337, 780 − 300) = 337 ⇒ plate 321 inside the 8px padding, pinned
    // to the left edge (issue 107 removes the bottom toolbar's 60px).
    expect(boardRect.width, closeTo(321, 0.5));
    expect(boardRect.height, closeTo(321, 0.5));
    expect(boardRect.left, closeTo(8, 0.5));
    expect(
      boardRect.top,
      closeTo(64, 0.5),
      reason: 'app bar 56 + the 8px seam',
    );
    final panelRect = tester.getRect(find.byType(SuspectPanel));
    expect(panelRect.left, closeTo(337, 0.5));
    expect(panelRect.width, closeTo(443, 0.5));
    expect(panelRect.height, closeTo(337, 0.5));
    expect(
      panelRect.right,
      closeTo(852 - 72, 0.5),
      reason: 'the strip (56 + 2×8 padding) takes the right edge (issue 107)',
    );
    expect(
      find.text('Подозреваемые'),
      findsNothing,
      reason: 'the suspects header is not rendered in landscape',
    );
  });

  testWidgets('tall wide window: the board cedes the 300px panel minimum '
      '(issue 103)', (tester) async {
    await pumpGame(tester, size: const Size(600, 1000), tutorialSeen: true);
    expect(tester.takeException(), isNull);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // Slot 1000 − 56 = 944 tall × (600 − strip 72) = 528 wide: the board
    // cedes the 300px panel minimum ⇒ min(944, 528 − 300) = 228 square
    // (issue 107: the strip narrows the width-limited case).
    expect(boardRect.width, closeTo(212, 0.5));
    expect(boardRect.height, closeTo(212, 0.5));
    expect(boardRect.left, closeTo(8, 0.5));
    final panelRect = tester.getRect(find.byType(SuspectPanel));
    expect(panelRect.width, closeTo(300, 0.5));
  });

  testWidgets('landscape standard 7x7: the grid scrolls without overflow '
      '(issue 103)', (tester) async {
    await pumpGame(
      tester,
      size: const Size(852, 393),
      difficulty: Difficulty.standard,
      tutorialSeen: true,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<ClampingScrollPhysics>(),
      reason: '4 grown rows exceed the 277px slot; the grid scrolls',
    );
    // The 4th row is below the fold; scrolling reaches its cards.
    final names = NameForms.forLocale('ru', currentCase());
    await tester.drag(
      find.text(names.nom(currentCase().suspects.first.id)),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(names.nom(currentCase().suspects.last.id)),
      findsOneWidget,
      reason: 'the last suspect row is reachable by scrolling',
    );
  });

  testWidgets('every RU clue sentence of the generated corpus stays within '
      'two lines at the landscape card text width (issue 103, two since '
      '107)', (tester) async {
    await pumpGame(tester, size: const Size(852, 393), tutorialSeen: true);
    final context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context)!;
    expect(l10n.localeName, 'ru');

    // The landscape card's text width at the reference panel (443 wide
    // since issue 107): tile (443 − 2·4 − 4)/2 = 215.5 minus the card
    // insets 2·(4 + 8 + border 3).
    const cardTextWidth = (443 - 2 * 4 - 1 * 4) / 2 - 2 * (4 + 8 + 3);
    // Measured with production Roboto metrics (the fixed-advance test font
    // inflates widths) in the card's own merged bodySmall style.
    final style = DefaultTextStyle.of(context).style
        .merge(Theme.of(context).textTheme.bodySmall)
        .copyWith(fontFamily: 'Roboto');
    await _ensureRobotoLoaded(tester);

    // The AC is a corpus claim: names and rooms draw from fixed pools, so a
    // sweep over the difficulties and a seed window bounds the longest
    // sentence the generator can produce (code-review round, issue 103).
    // Lines are counted by height, not width — a wrapped paragraph reports
    // its widest line, which can sit under the limit.
    // Issue 107 bounds it to TWO lines: the right-edge strip narrows the
    // reference card to 185.5px and the longest RU sentences wrap to two
    // lines there (cards grow, the grid scrolls — no clipping).
    for (final difficulty in Difficulty.values) {
      for (var seed = 1; seed <= 20; seed++) {
        final c = generateCase(difficulty: difficulty, seed: seed);
        final names = NameForms.forLocale('ru', c);
        for (final clue in c.clues) {
          final text = describeClue(clue, c, l10n, names);
          expect(
            _measureIdealHeight(text, style, cardTextWidth),
            lessThan(48),
            reason:
                'RU sentence "$text" ($difficulty seed $seed) stays within '
                'two lines at $cardTextWidth px (three lines measure ≥48px)',
          );
        }
      }
    }
  });

  testWidgets('small viewport 320x569 does not overflow (UX-6)', (
    tester,
  ) async {
    await pumpGame(tester, size: const Size(320, 569));
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
    expect(
      boardRect.bottom,
      closeTo(headerRect.top, 8),
      reason: 'board stays flush with the panel header on small screens',
    );
    expect(
      headerRect.height,
      lessThanOrEqualTo(48),
      reason: 'the header does not squeeze the grid at 320px',
    );
  });

  testWidgets('wide landscape window keeps the board square and the bottom row '
      'tappable (smoke regression, UX-10)', (tester) async {
    await pumpGame(tester, size: const Size(1200, 896));
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // The board is square by construction. On a landscape window its slot
    // is wider than tall, so the grid must shrink to the available height
    // — a height-clamped box silently clips the bottom row and its cells
    // stop receiving taps.
    expect(
      boardRect.height,
      boardRect.width,
      reason: 'board_view must stay square on landscape windows',
    );

    // A guest can actually be placed in the bottom row through a real tap.
    // Pick a bottom-row cell the case leaves empty (not the victim's, not
    // under an object) so the place tool accepts it.
    final lastRow = currentCase().gridSize - 1;
    final freeCol = [
      for (var col = 0; col < currentCase().gridSize; col++)
        if (currentCase().victimPos != (row: lastRow, col: col) &&
            currentCase().objects.every(
              (o) => o.pos != (row: lastRow, col: col),
            ))
          col,
    ].first;
    final cell = boardRect.width / currentCase().gridSize;
    final firstId = currentCase().suspects.first.id;
    container.read(gameControllerProvider.notifier).selectSuspect(firstId);
    await tester.pumpAndSettle();
    await tester.tapAt(
      Offset(
        boardRect.left + (freeCol + 0.5) * cell,
        boardRect.top + (lastRow + 0.5) * cell,
      ),
    );
    await tester.pumpAndSettle();
    final pos = container.read(gameControllerProvider)!.placed[firstId];
    expect(
      pos?.row,
      lastRow,
      reason: 'the bottom-row cell must receive the tap on wide layouts',
    );
    expect(
      pos?.col,
      freeCol,
      reason: 'the bottom-row cell must receive the tap on wide layouts',
    );
  });

  testWidgets('longest clue renders in full on its expanded card (UX-9)', (
    tester,
  ) async {
    await pumpGame(tester, size: const Size(412, 915));
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    final rendered = [
      for (final clue in fixedCase.clues)
        (
          suspectId: clue.suspectId,
          text: renderedPlainOf(
            describeClueSegments(clue, fixedCase, l10n, names),
          ),
        ),
    ];
    final longest = rendered.reduce(
      (a, b) => a.text.length >= b.text.length ? a : b,
    );

    container
        .read(gameControllerProvider.notifier)
        .selectSuspect(longest.suspectId);
    await tester.pumpAndSettle();

    expect(
      find.text(longest.text),
      findsOneWidget,
      reason: 'the longest clue is fully rendered on the expanded card',
    );
  });

  testWidgets('wide side panel renders every clue in full, unclipped (UX-9)', (
    tester,
  ) async {
    await pumpGame(tester, size: const Size(1200, 896));
    expect(tester.takeException(), isNull);

    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, fixedCase);
    // Per clue, the exact sentence its card renders (issue 26/89): every
    // clue is its own bare Text, not a joined paragraph. Sentences dedupe
    // by text: two clues can render the same words (e.g. two same-kind
    // items in one room — the #93 interim furniture cycles chair/sofa), and
    // one renderObject per distinct sentence covers every occurrence.
    // The rendered plain text: the room chip is a \uFFFC placeholder in
    // the RichText's plain text (issue 104).
    final renderedClues = <({String suspectId, String text})>[];
    final seenTexts = <String>{};
    for (final clue in fixedCase.clues) {
      final text = renderedPlainOf(
        describeClueSegments(clue, fixedCase, l10n, names),
      );
      if (seenTexts.add(text)) {
        renderedClues.add((suspectId: clue.suspectId, text: text));
      }
    }

    // No suspect is selected yet: every card shows its clue sentences.
    // Each paragraph box must be at least the text's ideal height — anything
    // shorter means the card clipped the text (the pre-fix ~90px tiles did).
    // (Expanded stretches short paragraphs to fill the card, so the box may
    // legitimately be taller than the text.)
    //
    // Issue #93 interlude: clue statements are nameless (issue 89), so two
    // cards can render the same sentence (e.g. two guests strictly north of
    // the same target) — the dedupe above keeps one probe per sentence and
    // finding it targets the first identical paragraph.
    for (final clue in renderedClues) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(clue.text).first,
      );
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
        reason:
            'clue of ${clue.suspectId} renders in full on the wide side panel',
      );
    }

    // Selecting the longest clue's owner keeps it fully rendered on the
    // expanded card (issue acceptance: the fullClue text is on screen — one
    // or more identical paragraphs render it; the no-clipping property is
    // per paragraph and already checked above).
    final rendered = [
      for (final clue in fixedCase.clues)
        (
          suspectId: clue.suspectId,
          text: renderedPlainOf(
            describeClueSegments(clue, fixedCase, l10n, names),
          ),
        ),
    ];
    final longest = rendered.reduce(
      (a, b) => a.text.length >= b.text.length ? a : b,
    );
    container
        .read(gameControllerProvider.notifier)
        .selectSuspect(longest.suspectId);
    await tester.pumpAndSettle();
    expect(
      find.text(longest.text),
      findsWidgets,
      reason: 'the longest clue is fully rendered on the expanded card',
    );
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
    },
  );

  testWidgets('wide side panel renders every en guest name in full, unclipped '
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

  testWidgets(
    'pause menu opens from the toolbar; Resume closes it (issue 11)',
    (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);
      await placeFirstGuest(tester);
      expect(container.read(gameControllerProvider)!.placed.length, 1);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resume), findsOneWidget);
      expect(find.text(l10n.howToPlayTitle), findsOneWidget);
      expect(find.text(l10n.settingsTitle), findsOneWidget);
      expect(find.text(l10n.abandonCase), findsOneWidget);

      // Opening the sheet is not a timer pause (issue #11, out of scope).
      final before = container.read(gameControllerProvider)!.elapsed;
      await tester.pump(const Duration(seconds: 2));
      expect(
        container.read(gameControllerProvider)!.elapsed,
        greaterThan(before),
        reason: 'the elapsed timer keeps running while the sheet is open',
      );

      await tester.tap(find.text(l10n.resume));
      await tester.pumpAndSettle();
      expect(find.text(l10n.resume), findsNothing);
      expect(
        container.read(gameControllerProvider)!.placed.length,
        1,
        reason: 'Resume leaves the game state untouched',
      );
    },
  );

  testWidgets(
    'pause menu: How to play pushes above the game; Back returns with the '
    'guest still placed (issue 11)',
    (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);
      await placeFirstGuest(tester);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.howToPlayTitle));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.rule1Text),
        findsOneWidget,
        reason: 'How to play opens above the running case',
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(l10n.rule1Text), findsNothing);
      expect(
        container.read(gameControllerProvider)!.placed.length,
        1,
        reason: 'Back returns to the game with board placement intact',
      );
      expect(
        find.byIcon(Icons.pause),
        findsOneWidget,
        reason: 'the game screen is back on top',
      );
    },
  );

  testWidgets(
    'pause menu: Settings pushes above the game; Back returns with the '
    'guest still placed (issue 11)',
    (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);
      await placeFirstGuest(tester);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsTitle));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.themeModeLabel),
        findsOneWidget,
        reason: 'Settings opens above the running case',
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(l10n.themeModeLabel), findsNothing);
      expect(
        container.read(gameControllerProvider)!.placed.length,
        1,
        reason: 'Back returns to the game with board placement intact',
      );
    },
  );

  testWidgets(
    'pause menu: Abandon case shows the exit dialog; cancelling returns to '
    'the game (issue 11)',
    (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);
      await placeFirstGuest(tester);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.abandonCase));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.quitConfirmTitle),
        findsOneWidget,
        reason: 'Abandon case reuses the existing exit dialog',
      );

      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.quitConfirmTitle), findsNothing);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        container.read(gameControllerProvider)!.placed.length,
        1,
        reason: 'cancelling returns to the running game',
      );
    },
  );

  testWidgets('pause menu: confirming Abandon case quits to home (issue 11)', (
    tester,
  ) async {
    await pumpGame(tester);
    final l10n = l10nOf(tester);
    await placeFirstGuest(tester);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.abandonCase));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.quitCase));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      container.read(gameControllerProvider),
      isNull,
      reason: 'confirming abandon quits the case',
    );
  });

  testWidgets('toolbar tooltips describe their own buttons (issue 17)', (
    tester,
  ) async {
    for (final language in [LanguageSetting.russian, LanguageSetting.english]) {
      await pumpGame(tester, language: language);
      final l10n = l10nOf(tester);

      String tooltipOf(String label) => tester
          .widget<Tooltip>(
            find
                .ancestor(of: find.text(label), matching: find.byType(Tooltip))
                .first,
          )
          .message!;

      expect(
        tooltipOf(l10n.toolPlace),
        l10n.toolPlace,
        reason: 'Place announces its own action ($language)',
      );
      expect(
        tooltipOf(l10n.toolMark),
        l10n.toolMarkTooltip,
        reason: 'Mark has a dedicated tooltip ($language)',
      );
      expect(
        tooltipOf(l10n.toolHint),
        l10n.toolHintTooltip,
        reason: 'Hint has a dedicated tooltip ($language)',
      );
      expect(
        tooltipOf(l10n.toolAccuse),
        l10n.accuse,
        reason: 'Accuse announces its own action ($language)',
      );
    }
  });

  testWidgets('a negated clue renders on the game screen (issue 16)', (
    tester,
  ) async {
    await pumpGame(tester, difficulty: Difficulty.standard);
    final l10n = l10nOf(tester);
    final names = NameForms.forLocale(l10n.localeName, standardCase);

    final negated = standardCase.clues.where((c) => c.negated).toList();
    expect(
      negated,
      isNotEmpty,
      reason: 'standard cases always carry a negated clue (issue #10)',
    );
    String renderedOf(Clue clue) =>
        renderedPlainOf(describeClueSegments(clue, standardCase, l10n, names));
    final text = describeClue(negated.first, standardCase, l10n, names);
    final renderedText = renderedOf(negated.first);
    expect(negated.first.negated, isTrue);

    // The positive counterpart of the same predicate must render through the
    // *Not template, not the plain one: both strings differ only by the
    // negation («не»), so finding the negated one and not the positive one
    // proves the negated rendering path is what ran.
    final positive = switch (negated.first) {
      InRoom(:final suspectId, :final roomId) => InRoom(
        suspectId: suspectId,
        roomId: roomId,
        negated: false,
      ),
      SameRow(:final suspectId, :final targetId) => SameRow(
        suspectId: suspectId,
        targetId: targetId,
        negated: false,
      ),
      SameCol(:final suspectId, :final targetId) => SameCol(
        suspectId: suspectId,
        targetId: targetId,
        negated: false,
      ),
      DirectionClue(:final suspectId, :final targetId, :final direction) =>
        DirectionClue(
          suspectId: suspectId,
          targetId: targetId,
          direction: direction,
          negated: false,
        ),
      Beside(:final suspectId, :final targetId) => Beside(
        suspectId: suspectId,
        targetId: targetId,
        negated: false,
      ),
      BesideObject(:final suspectId, :final objectId) => BesideObject(
        suspectId: suspectId,
        objectId: objectId,
        negated: false,
      ),
    };
    final positiveText = describeClue(positive, standardCase, l10n, names);
    final renderedPositiveText = renderedOf(positive);
    expect(
      positiveText,
      isNot(text),
      reason: 'the negated and positive templates must differ',
    );
    expect(
      renderedPositiveText,
      isNot(renderedText),
      reason: 'the rendered forms differ too (the chip is a placeholder)',
    );

    container
        .read(gameControllerProvider.notifier)
        .selectSuspect(negated.first.suspectId);
    await tester.pumpAndSettle();

    // The clue card can sit outside the suspect grid's built viewport —
    // the grid lazily builds until scrolled, and the card holding this
    // clue drifted into row 2 with the issue-61 remap. Scroll the grid's
    // own scrollable (document order puts it before each card's clue
    // scroll view, so .first is the grid).
    await tester.scrollUntilVisible(
      find.text(renderedText),
      100,
      scrollable: find
          .descendant(
            of: find.byType(SuspectPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(renderedText),
      findsOneWidget,
      reason: 'the negated clue template renders on the real game screen',
    );
    expect(
      find.text(renderedPositiveText),
      findsNothing,
      reason:
          'the plain (non-negated) template of the same predicate '
          'must not stand in for the negated one',
    );
  });

  testWidgets(
    'tap helpers place into the cell of the case pumpGame started (issue 19)',
    (tester) async {
      await pumpGame(tester, difficulty: Difficulty.standard);
      final notifier = container.read(gameControllerProvider.notifier);

      // placeFirstGuest must drive the started case's first solution guest,
      // not the easy fixture's (standard s0 solves (0,2)).
      await placeFirstGuest(tester);
      final first = standardCase.solution.entries.first;
      expect(
        container.read(gameControllerProvider)!.placed[first.key],
        first.value,
        reason: 'placeFirstGuest targets the case pumpGame started',
      );

      // A last-column cell proves the 6x6 geometry: with the stale fixed-5
      // cell size the tap point lands at 1.1 board widths — off the board.
      final last = standardCase.solution.entries.firstWhere(
        (e) => e.value.col == standardCase.gridSize - 1,
      );
      notifier.selectSuspect(last.key);
      await tester.pumpAndSettle();
      await tapCell(tester, last.value.row, last.value.col);
      expect(
        container.read(gameControllerProvider)!.placed[last.key],
        last.value,
        reason: 'tapCell derives its cell size from the started case',
      );
    },
  );

  testWidgets(
    'tap helpers read the case in play when it started without pumpGame '
    '(issue 22)',
    (tester) async {
      await pumpGame(tester);
      // A UI-driven case start mutates exactly this state: the home screen
      // calls the same notifier method (home_screen.dart). pumpGame never
      // learns about it, so the helpers must follow the controller's live
      // case, not a snapshot taken when pumpGame ran.
      container
          .read(gameControllerProvider.notifier)
          .startNewCase(Difficulty.standard, seed: 3);
      await tester.pumpAndSettle();

      await placeFirstGuest(tester);
      final first = standardCase.solution.entries.first;
      expect(
        container.read(gameControllerProvider)!.placed[first.key],
        first.value,
        reason: 'placeFirstGuest targets the case actually in play',
      );

      // With stale easy (5-cell) geometry a last-column tap lands at 1.1
      // board widths — off the board (issue 19's 6x6 proof, re-run after a
      // case start pumpGame did not witness).
      final notifier = container.read(gameControllerProvider.notifier);
      final last = standardCase.solution.entries.firstWhere(
        (e) => e.value.col == standardCase.gridSize - 1,
      );
      notifier.selectSuspect(last.key);
      await tester.pumpAndSettle();
      await tapCell(tester, last.value.row, last.value.col);
      expect(
        container.read(gameControllerProvider)!.placed[last.key],
        last.value,
        reason: 'tapCell derives its cell size from the case actually in play',
      );
    },
  );

  testWidgets('toolbar buttons use the skin action colors (issue 23)', (
    tester,
  ) async {
    await pumpGame(tester); // default skin: sticker

    Color pillColor(Key key) {
      final container = tester.widget<Container>(find.byKey(key));
      return (container.decoration as BoxDecoration?)!.color!;
    }

    expect(pillColor(const Key('tool_place')), stickerTokens.actions.place);
    expect(pillColor(const Key('tool_mark')), stickerTokens.actions.mark);
    expect(pillColor(const Key('tool_hint')), stickerTokens.actions.hint);
    expect(pillColor(const Key('tool_accuse')), stickerTokens.actions.accuse);
  });

  testWidgets('toolbar glyphs render skin ink on pastel pills, white on '
      'danger (issue 87)', (tester) async {
    for (final entry in {
      SkinSetting.candy: candyTokens,
      SkinSetting.sticker: stickerTokens,
      SkinSetting.comic: comicTokens,
    }.entries) {
      await pumpGame(tester, skin: entry.key);
      final tokens = entry.value;

      Color? iconColor(Key key) => tester
          .widget<Icon>(
            find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
          )
          .color;
      Color? labelColor(Key key) => tester
          .widget<Text>(
            find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          )
          .style!
          .color;

      for (final key in const ['tool_place', 'tool_mark', 'tool_hint']) {
        expect(
          iconColor(Key(key)),
          tokens.ink,
          reason: '${tokens.skin} $key icon must be the skin ink (issue 87)',
        );
        expect(
          labelColor(Key(key)),
          tokens.ink,
          reason: '${tokens.skin} $key label must be the skin ink (issue 87)',
        );
      }
      expect(
        iconColor(const Key('tool_accuse')),
        Colors.white,
        reason: '${tokens.skin} accuse icon stays white on the danger pill',
      );
      expect(
        labelColor(const Key('tool_accuse')),
        Colors.white,
        reason: '${tokens.skin} accuse label stays white on the danger pill',
      );
    }
  });

  testWidgets('classic toolbar glyphs keep the theme default (issue 87)', (
    tester,
  ) async {
    await pumpGame(tester, skin: SkinSetting.classic);

    Color? iconColor(Key key) => tester
        .widget<Icon>(
          find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
        )
        .color;
    Color? labelColor(Key key) => tester
        .widget<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        )
        .style!
        .color;

    expect(iconColor(const Key('tool_place')), isNull);
    expect(labelColor(const Key('tool_place')), isNull);
    expect(iconColor(const Key('tool_accuse')), isNull);
    expect(labelColor(const Key('tool_accuse')), isNull);
  });

  group('interaction coverage pins (issue 35)', () {
    /// Pumps the app and lands on /game with NO active case (fresh prefs).
    Future<void> pumpWithoutCase(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'murdoku.settings': jsonEncode(
          const Settings(language: LanguageSetting.english).toJson(),
        ),
        'murdoku.tutorialSeen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: seededOverrides(prefs));
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MurdokuApp(),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/game');
      await tester.pumpAndSettle();
    }

    testWidgets('no active case: placeholder screen and back navigation', (
      tester,
    ) async {
      await pumpWithoutCase(tester);
      final l10n = l10nOf(tester);

      expect(find.text(l10n.noActiveCase), findsOneWidget);
      await tester.tap(find.text(l10n.backToHome));
      await tester.pumpAndSettle();
      expect(find.text(l10n.appTitle), findsOneWidget);
    });

    testWidgets('mark-tool drag across cells draws X marks', (tester) async {
      await pumpGame(tester);
      await tester.tap(find.byKey(const Key('tool_mark')));
      await tester.pumpAndSettle();

      final boardRect = tester.getRect(find.byKey(const Key('board_view')));
      final cell = boardRect.width / currentCase().gridSize;
      final start = boardRect.center - Offset(cell, 0);
      await tester.dragFrom(start, Offset(cell * 2, 0));
      await tester.pumpAndSettle();

      expect(
        container.read(gameControllerProvider)!.xMarks,
        isNotEmpty,
        reason: 'dragging with the mark tool excludes the swept cells',
      );
    });

    testWidgets('tapping a suspect card selects and deselects it', (
      tester,
    ) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);
      final names = NameForms.forLocale(l10n.localeName, currentCase());
      // Selection styling on the default (sticker) skin: the selected card
      // is outlined in the suspect's own color (suspect_panel.dart's
      // _cartoonDecoration); every unselected card stays in the skin's
      // border color (issue 44).
      int highlighted(int suspectIndex) => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SuspectPanel),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).border?.top.color ==
                        suspectColor(suspectIndex),
              ),
            ),
          )
          .length;
      final name = names.nom('s0');

      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider)!.selectedSuspectId, 's0');
      expect(highlighted(0), 1);

      // Re-tapping the selected card deselects it (issue 44): provider state
      // null and no card highlighted.
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider)!.selectedSuspectId, isNull);
      expect(highlighted(0), 0);

      // Selecting another suspect still works after a deselect.
      final other = names.nom('s1');
      await tester.tap(find.text(other).last);
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider)!.selectedSuspectId, 's1');
      expect(highlighted(1), 1);

      await tester.tap(find.text(other).last);
      await tester.pumpAndSettle();
      expect(container.read(gameControllerProvider)!.selectedSuspectId, isNull);
      expect(highlighted(1), 0);
    });

    testWidgets('appbar back opens the quit-confirm dialog', (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.byTooltip(l10n.quitCase));
      await tester.pumpAndSettle();
      expect(find.text(l10n.quitConfirmTitle), findsOneWidget);
    });

    testWidgets('appbar legend action opens the legend sheet', (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.byTooltip(l10n.legendTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.legendRooms), findsOneWidget);
    });

    testWidgets('app bar actions are exactly Legend then Menu; the toolbar has '
        'no menu button (issue 107)', (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.resume),
        findsOneWidget,
        reason: 'the app-bar Menu icon opens the pause sheet',
      );
      await tester.tap(find.text(l10n.resume));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AppBar>(find.byType(AppBar).first).actions!.length,
        2,
        reason: 'the actions are exactly [Legend, Menu]',
      );
      final legendRect = tester.getRect(find.byIcon(Icons.menu_book));
      final menuRect = tester.getRect(find.byIcon(Icons.pause));
      expect(
        legendRect.right <= menuRect.left,
        isTrue,
        reason: 'Legend sits left of Menu in the actions row',
      );
      expect(
        find.byTooltip(l10n.pauseMenuTitle),
        findsOneWidget,
        reason: 'the Menu icon announces itself as the pause menu',
      );
      expect(
        find.byKey(const Key('tool_menu')),
        findsNothing,
        reason: 'the toolbar no longer carries a Menu button',
      );
    });

    testWidgets('hint toolbar button opens the hint sheet', (tester) async {
      await pumpGame(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.byKey(const Key('tool_hint')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.hintPlace), findsOneWidget);
      expect(find.text(l10n.hintEliminate), findsOneWidget);
    });

    testWidgets('dismissing the victory dialog navigates home', (tester) async {
      await pumpGame(tester, tutorialSeen: true);
      final l10n = l10nOf(tester);
      final notifier = container.read(gameControllerProvider.notifier);

      for (final entry in fixedCase.solution.entries) {
        notifier.selectSuspect(entry.key);
        await tester.pumpAndSettle();
        await tapCell(tester, entry.value.row, entry.value.col);
      }
      await tester.pumpAndSettle();

      final names = NameForms.forLocale(l10n.localeName, fixedCase);
      // Scope to the accuse sheet and scroll to the tile (issue 61: the
      // fixture case content changed — the unscoped `.last` name can hit a
      // clue card or a below-the-fold sheet tile).
      final murdererTile = find.descendant(
        of: find.byType(AccuseSheet),
        matching: find.text(names.nom(fixedCase.murdererId)),
      );
      await tester.scrollUntilVisible(
        murdererTile,
        50,
        scrollable: find.descendant(
          of: find.byType(AccuseSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(murdererTile);
      await tester.pumpAndSettle();
      expect(find.byType(VictoryDialog), findsOneWidget);

      await tester.tap(find.text(l10n.victoryDone));
      await tester.pumpAndSettle();
      expect(find.text(l10n.appTitle), findsOneWidget);
    });
  });

  testWidgets('classic skin: toolbar buttons keep the scheme rendering', (
    tester,
  ) async {
    await pumpGame(tester, skin: SkinSetting.classic);

    Color? containerColor(Key key) =>
        (tester.widget<Container>(find.byKey(key)).decoration
                as BoxDecoration?)!
            .color;

    // The active tool gets the primary container; inactive ones stay
    // transparent (no skin pill).
    expect(
      containerColor(const Key('tool_place')),
      Theme.of(tester.element(find.byKey(const Key('tool_place'))))
          .colorScheme
          .primaryContainer,
    );
    expect(containerColor(const Key('tool_mark')), Colors.transparent);
  });

  group('portrait toolbar: one row of 4 at every width (issue 107)', () {
    final viewports = [
      (320, 568),
      (402, 874),
      (471, 800),
      (472, 800),
      (599, 800),
    ];
    for (final (w, h) in viewports) {
      testWidgets('one row of [Place, Mark X, Hint, Accuse] at ${w}x$h '
          '(issue 107)', (tester) async {
        await pumpGame(
          tester,
          size: Size(w.toDouble(), h.toDouble()),
          skin: SkinSetting.classic,
          tutorialSeen: true,
        );
        expect(tester.takeException(), isNull);
        expectToolbarOneRowOf4(tester);
      });
    }

    testWidgets('one row of 4 holds on a cartoon skin at 402x874 '
        '(issue 107)', (tester) async {
      await pumpGame(
        tester,
        size: const Size(402, 874),
        skin: SkinSetting.candy,
        tutorialSeen: true,
      );
      expect(tester.takeException(), isNull);
      expectToolbarOneRowOf4(tester);
    });
  });

  testWidgets('landscape: the toolbar is a vertical strip on the right edge '
      'and the board takes the full body height (issue 107)', (tester) async {
    await pumpGame(tester, size: const Size(800, 360), tutorialSeen: true);
    expect(tester.takeException(), isNull);

    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    // Body height 360 − app bar 56 = the 304px slot — the full body height,
    // with no toolbar docked under it anymore; the board's own 8px padding
    // pair leaves the 288px plate. (Pre-change the bottom toolbar capped the
    // slot at 244px.)
    expect(boardRect.width, closeTo(288, 0.5));
    expect(boardRect.height, closeTo(288, 0.5));
    expect(boardRect.top, closeTo(64, 0.5), reason: 'app bar 56 + 8 seam');
    expect(boardRect.bottom, closeTo(352, 0.5), reason: '8px bottom padding');

    final panelRect = tester.getRect(find.byType(SuspectPanel));
    final placeRect = tester.getRect(find.byKey(const Key('tool_place')));
    expect(
      panelRect.right <= placeRect.left,
      isTrue,
      reason: 'the panel sits between the board and the strip',
    );
    expect(
      placeRect.left,
      closeTo(800 - 8 - 56, 0.5),
      reason: 'strip: 8px outer padding + the 56px fixed width',
    );
    expect(
      placeRect.right,
      closeTo(800 - 8, 0.5),
      reason: 'the strip hugs the right edge',
    );
    expectToolbarStrip(tester);
  });

  testWidgets('landscape strip scrolls instead of overflowing on a short '
      'wide window (review render-proof, issue 107)', (tester) async {
    await pumpGame(tester, size: const Size(600, 280), tutorialSeen: true);
    // The stack's natural height (4×52 + 3×4 = 220) exceeds the 208px
    // content area under the app bar; any RenderFlex overflow would throw
    // here — the strip must scroll instead.
    expect(tester.takeException(), isNull);
    final accuseRect = tester.getRect(find.byKey(const Key('tool_accuse')));
    expect(
      accuseRect.height,
      greaterThanOrEqualTo(44),
      reason: 'pills keep their 44pt targets while scrolling',
    );

    // The accuse pill starts below the fold; scrolling the strip reveals
    // it fully.
    await tester.drag(
      find.byKey(const Key('tool_accuse')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    final revealed = tester.getRect(find.byKey(const Key('tool_accuse')));
    expect(
      revealed.top,
      greaterThanOrEqualTo(56),
      reason: 'the revealed pill stays inside the body',
    );
    expect(
      revealed.bottom,
      lessThanOrEqualTo(280 - 8 + 0.5),
      reason: 'the whole accuse pill is reachable by scrolling the strip',
    );
  });
}

/// Loads the Flutter SDK's bundled Roboto-Regular.ttf (the production font
/// families for these labels default to) under the 'Roboto' family name, so
/// label widths can be measured with device metrics instead of the
/// fixed-advance FlutterTest font.
///
/// The path is a stock Flutter cache artifact and a missing file fails the
/// test loudly DELIBERATELY: the ≥9px readability floor may only be measured
/// with the production font, never a substitute (vendoring the font would be
/// an owner-side option if some environment ships it elsewhere).
Future<void> _ensureRobotoLoaded(WidgetTester tester) async {
  final ttf = () {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      if (file.existsSync()) return file;
    }
    // flutter test runs text through the flutter_tester engine binary at
    // <sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester; walk the
    // ancestors to find <sdk>/bin/cache/artifacts/material_fonts.
    var dir = File(Platform.resolvedExecutable).parent;
    while (true) {
      final candidate = File('${dir.path}/material_fonts/Roboto-Regular.ttf');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          'Roboto-Regular.ttf not found in the Flutter SDK cache',
        );
      }
      dir = parent;
    }
  }();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(ttf.readAsBytesSync().buffer)));
  await tester.runAsync(loader.load);
}

/// The wrapped height [text] needs at [maxWidth] in the merged [style]
/// (production-font family expected, e.g. Roboto): one line of the card's
/// bodySmall measures 16px, two lines 32px.
double _measureIdealHeight(String text, TextStyle style, double maxWidth) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Adjacent-pair ≥4px seam assertions shared by the issue-88 wrap tests.
void assertSeams(List<Rect> row, String rowName) {
  for (var i = 0; i < row.length - 1; i++) {
    expect(
      row[i + 1].left - row[i].right,
      greaterThanOrEqualTo(4),
      reason: '$rowName: pill $i and ${i + 1} must be ≥4px apart (issue 88)',
    );
  }
}

/// Issue 107 portrait toolbar geometry: exactly the four buttons
/// (place/mark/hint/accuse) on one shared row, ≥44×44 each, ≥4px seams
/// between adjacent pills.
void expectToolbarOneRowOf4(WidgetTester tester) {
  const keys = ['tool_place', 'tool_mark', 'tool_hint', 'tool_accuse'];
  final row = [for (final k in keys) tester.getRect(find.byKey(Key(k)))];
  for (var i = 0; i < keys.length; i++) {
    expect(row[i].width, greaterThanOrEqualTo(44), reason: keys[i]);
    expect(row[i].height, greaterThanOrEqualTo(44), reason: keys[i]);
    expect(
      (row[i].top - row[0].top).abs(),
      lessThan(0.01),
      reason: '${keys[i]} shares the single toolbar row',
    );
  }
  assertSeams(row, 'toolbar');
}

/// Issue 107 landscape strip geometry: the four buttons stacked
/// top-to-bottom (place/mark/hint/accuse), each stretched to the strip's
/// fixed 56px width (uniform stack), ≥44 tall, ≥4px vertical seams.
void expectToolbarStrip(WidgetTester tester) {
  const keys = ['tool_place', 'tool_mark', 'tool_hint', 'tool_accuse'];
  final strip = [for (final k in keys) tester.getRect(find.byKey(Key(k)))];
  for (var i = 0; i < keys.length; i++) {
    expect(
      strip[i].width,
      closeTo(_toolbarStripTestWidth, 0.1),
      reason: '${keys[i]} fills the fixed strip width (uniform stack)',
    );
    expect(strip[i].height, greaterThanOrEqualTo(44), reason: keys[i]);
    if (i > 0) {
      expect(
        strip[i].top - strip[i - 1].bottom,
        greaterThanOrEqualTo(4),
        reason: '${keys[i]} sits at least 4px below ${keys[i - 1]}',
      );
    }
  }
}

/// The strip width the geometry assertions pin; mirrors production's
/// `_toolbarStripWidth` (tests cannot reach a private lib constant).
const double _toolbarStripTestWidth = 56;
