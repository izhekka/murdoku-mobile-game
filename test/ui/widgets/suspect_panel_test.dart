import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

import '../../support/localized_test_app.dart';

Pos p(int row, int col) => (row: row, col: col);

/// The 5x5 fixture board; [clues] lets variants stress card sizing (e.g.
/// suspects carrying several clue cards).
CaseData buildFixture(List<Clue> clues) => CaseData(
  seed: 1,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(
      id: 'r0',
      name: 'Hall',
      cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)],
    ),
    RoomDef(
      id: 'r1',
      name: 'Library',
      cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)],
    ),
    RoomDef(
      id: 'r2',
      name: 'Kitchen',
      cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)],
    ),
    RoomDef(
      id: 'r3',
      name: 'Cellar',
      cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)],
    ),
    RoomDef(
      id: 'r4',
      name: 'Study',
      cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)],
    ),
  ],
  objects: [
    ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 1)),
    ObjectDef(id: 'o1', kind: ObjectKind.clock, pos: p(4, 4)),
  ],
  suspects: [
    Suspect(id: 's0', name: 'Ash'),
    Suspect(id: 's1', name: 'Blair'),
    Suspect(id: 's2', name: 'Casey'),
    Suspect(id: 's3', name: 'Drew'),
    Suspect(id: 's4', name: 'Ellis'),
  ],
  victimPos: p(2, 2),
  murdererId: 's2',
  clues: clues,
  solution: {
    's0': p(0, 0),
    's1': p(1, 4),
    's2': p(2, 1),
    's3': p(3, 3),
    's4': p(4, 2),
  },
);

/// 5x5 fixture with one clue per suspect (varied types, incl. negations).
final CaseData fixture = buildFixture([
  InRoom(suspectId: 's0', roomId: 'r0', negated: false),
  SameRow(suspectId: 's1', targetId: 'V', negated: true),
  SameCol(suspectId: 's2', targetId: 's4', negated: false),
  DirectionClue(
    suspectId: 's3',
    targetId: 'V',
    direction: Direction.south,
    negated: true,
  ),
  BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
]);

/// Same 5x5 board, but s0 carries four clues (hard cases give suspects
/// several clue cards): the joined text is taller than the old pinned 150px
/// wide-branch card even at text scale 1.0.
final CaseData multiClueFixture = buildFixture([
  InRoom(suspectId: 's0', roomId: 'r0', negated: false),
  SameRow(suspectId: 's0', targetId: 'V', negated: true),
  SameCol(suspectId: 's0', targetId: 's4', negated: false),
  BesideObject(suspectId: 's0', objectId: 'o1', negated: false),
  SameRow(suspectId: 's1', targetId: 'V', negated: true),
  SameCol(suspectId: 's2', targetId: 's4', negated: false),
  DirectionClue(
    suspectId: 's3',
    targetId: 'V',
    direction: Direction.south,
    negated: true,
  ),
  BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
]);

/// Same board, but s0 carries two clue sentences: the grown row heights then
/// exceed the 600px-tall side slot in both renderers (classic paragraph and
/// skin chips) while each card stays shorter than the slot, so the shrink-wrap
/// grid clamps, row 2 (Drew/Ellis/empty) sits below the fold with no scroll
/// affordance, and scrolling can still bring the full bottom-row card on
/// screen (issue 30).
final CaseData overflowFixture = buildFixture([
  InRoom(suspectId: 's0', roomId: 'r0', negated: false),
  SameRow(suspectId: 's0', targetId: 'V', negated: true),
  SameRow(suspectId: 's1', targetId: 'V', negated: true),
  SameCol(suspectId: 's2', targetId: 's4', negated: false),
  DirectionClue(
    suspectId: 's3',
    targetId: 'V',
    direction: Direction.south,
    negated: true,
  ),
  BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
]);

/// Standard-difficulty stand-in: the fixture board gains a sixth guest, so
/// the panel lays out 7 grid children (6 cards + the empty slot = 3 rows).
/// The panel only reads suspects and clue sentences, so rooms/solution stay
/// as-is (issue 39).
final CaseData standardFixture = fixture.copyWith(
  suspects: [
    ...fixture.suspects,
    const Suspect(id: 's5', name: 'Finley'),
  ],
  clues: [
    ...fixture.clues,
    InRoom(suspectId: 's5', roomId: 'r0', negated: false),
  ],
);

/// Hard-difficulty stand-in: a seventh guest, so 8 grid children and the
/// pre-existing more-suspects-than-the-grid-shows scrollable clause apply
/// (issue 39 non-regression).
final CaseData hardFixture = standardFixture.copyWith(
  suspects: [
    ...standardFixture.suspects,
    const Suspect(id: 's6', name: 'Grey'),
  ],
  clues: [
    ...standardFixture.clues,
    InRoom(suspectId: 's6', roomId: 'r1', negated: false),
  ],
);

/// Same board and clues as [fixture], but s0 carries a long multi-word
/// display name (stored/custom cases may carry arbitrary names) and s1 is
/// placed (its check icon narrows the name row): both stress the name row
/// at the 300px side-panel card width (issue 15).
final CaseData longNameFixture = fixture.copyWith(
  suspects: [
    const Suspect(id: 's0', name: 'Mercedes Ann Vane'),
    ...fixture.suspects.skip(1),
  ],
);

/// Same board and clues as [fixture], but every suspect carries one of the
/// widest pool names (6 glyphs in both locales: 'Harper'/'Morgan'/'Oakley'
/// en, 'Харпер'/'Морган' ru) and every card is placed, so the check marker
/// squeezes the name row at its worst case (issue 18).
final CaseData poolNameFixture = fixture.copyWith(
  suspects: [
    const Suspect(id: 's0', name: 'Harper', poolIndex: 7),
    const Suspect(id: 's1', name: 'Morgan', poolIndex: 12),
    const Suspect(id: 's2', name: 'Oakley', poolIndex: 14),
    const Suspect(id: 's3', name: 'Frank', poolIndex: 5),
    const Suspect(id: 's4', name: 'Ellis', poolIndex: 4),
  ],
);

/// Stateful harness so taps move the selection like the real game does.
class Harness extends StatefulWidget {
  const Harness({super.key, this.onSuspectTap});

  final void Function(String)? onSuspectTap;

  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  String? _selected = 's0';

  @override
  Widget build(BuildContext context) => MaterialApp(
    // The panel test pins English: it asserts exact en clue wording with
    // declension forms (see localization_test.dart for the ru grammar).
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 320,
        child: SuspectPanel(
          caseData: fixture,
          placed: {'s2': fixture.solution['s2']!},
          selectedSuspectId: _selected,
          onSuspectTap: (id) {
            widget.onSuspectTap?.call(id);
            setState(() => _selected = _selected == id ? null : id);
          },
        ),
      ),
    ),
  );
}

Widget generatedWrap(
  CaseData c, {
  String? selectedSuspectId,
  void Function(String)? onSuspectTap,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 320,
      child: SuspectPanel(
        caseData: c,
        placed: const {},
        selectedSuspectId: selectedSuspectId,
        onSuspectTap: onSuspectTap ?? (_) {},
      ),
    ),
  ),
);

/// The panel's own wide branch: the LayoutBuilder sees >=600px and renders
/// the vertical card column.
Widget wideWrap(CaseData c) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(
      width: 600,
      child: SuspectPanel(
        caseData: c,
        placed: const {},
        selectedSuspectId: null,
        onSuspectTap: (_) {},
      ),
    ),
  ),
);

/// The panel under a skin scope at the 320px narrow width (issue 23's
/// builder-level scoping, mirroring lib/app.dart); [selectedId] mirrors the
/// real panel's selection state.
Widget skinWrap(SkinTokens tokens, {String? selectedId, CaseData? c}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => SkinScope(tokens: tokens, child: child!),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: SuspectPanel(
            caseData: c ?? fixture,
            placed: const {},
            selectedSuspectId: selectedId,
            onSuspectTap: (_) {},
          ),
        ),
      ),
    );

/// The 300px side slot exactly as the wide game screen hosts the panel:
/// bounded but loose height, so the panel renders the grid branch and
/// grows content-sized rows (issue 15). [locale] pins the l10n under test
/// (pool names resolve through the localized pools, issue 18); the
/// localization setup comes from the shared helper (issue 21).
Widget sidePanelWrap(
  CaseData c, {
  Map<String, Pos> placed = const {},
  Locale locale = const Locale('en'),
  void Function(String)? onSuspectTap,
}) => localizedTestApp(
  locale: locale,
  child: Align(
    child: SizedBox(
      width: 300,
      child: SuspectPanel(
        caseData: c,
        placed: placed,
        selectedSuspectId: null,
        onSuspectTap: onSuspectTap ?? (_) {},
      ),
    ),
  ),
);

/// The 300px side slot under a skin scope: same loose-height hosting as
/// [sidePanelWrap], with the skin's tokens live (issue 26).
Widget skinSidePanelWrap(
  SkinTokens tokens,
  CaseData c, {
  void Function(String)? onSuspectTap,
}) => localizedTestApp(
  child: SkinScope(
    tokens: tokens,
    child: Align(
      child: SizedBox(
        width: 300,
        child: SuspectPanel(
          caseData: c,
          placed: const {},
          selectedSuspectId: null,
          onSuspectTap: onSuspectTap ?? (_) {},
        ),
      ),
    ),
  ),
);

/// The panel pinned to a phone-sized slot, exactly as the narrow game screen
/// hosts it (`Expanded(child: panel)`, lib/ui/screens/game_screen.dart):
/// tight width and height render the pinned branch. [width]/[height] model
/// the space left under the board and toolbar on a narrow phone; [tokens]
/// scopes a cartoon skin (issue 39).
Widget pinnedWrap(
  CaseData c, {
  double width = 360,
  double height = 300,
  SkinTokens? tokens,
  void Function(String)? onSuspectTap,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: tokens == null
      ? null
      : (context, child) => SkinScope(tokens: tokens, child: child!),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: SuspectPanel(
          caseData: c,
          placed: const {},
          selectedSuspectId: null,
          onSuspectTap: onSuspectTap ?? (_) {},
        ),
      ),
    ),
  ),
);

/// The panel's own wide branch (>=600px) under a skin scope (issue 26).
Widget skinWideWrap(SkinTokens tokens, CaseData c) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => SkinScope(tokens: tokens, child: child!),
  home: Scaffold(
    body: SizedBox(
      width: 600,
      child: SuspectPanel(
        caseData: c,
        placed: const {},
        selectedSuspectId: null,
        onSuspectTap: (_) {},
      ),
    ),
  ),
);

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

void main() {
  testWidgets('every suspect card shows its name and its clue sentences', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(Harness(onSuspectTap: (id) => tapped = id));
    await tester.pump();

    // The grid shows all cards at once; assert each name and exact en wording.
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Ash was in the Hall.'), findsOneWidget);
    expect(find.text('Blair'), findsOneWidget);
    expect(
      find.text('Blair was not on the same floor as the victim.'),
      findsOneWidget,
    );
    expect(find.text('Casey'), findsOneWidget);
    expect(
      find.text('Casey was in the same corridor as Ellis.'),
      findsOneWidget,
    );
    expect(find.text('Drew'), findsOneWidget);
    expect(find.text('Drew was not south of the victim.'), findsOneWidget);
    expect(find.text('Ellis'), findsOneWidget);
    expect(
      find.text('Ellis was in the same room as the Clock.'),
      findsOneWidget,
    );

    // Placed suspect is marked.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tapping a card selects that suspect.
    await tester.tap(find.text('Drew'));
    expect(tapped, 's3');
  });

  testWidgets('suspects render as a 3x2 grid; no horizontal strip (UX-2)', (
    tester,
  ) async {
    // A tall surface: UX-9 grows the rows to their clue content, and the
    // default 600px-tall surface is shorter than two grown rows of a
    // generated case — the fit premise of the physics assertion below needs
    // the room (issue 30).
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = generateCase(difficulty: Difficulty.easy, seed: 3);
    await tester.pumpWidget(generatedWrap(c));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      grid.physics,
      isA<NeverScrollableScrollPhysics>(),
      reason: '5 suspects fit the grid; no scrolling needed',
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3, reason: '3 columns');
    final childrenDelegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(
      childrenDelegate.children.length,
      6,
      reason: '5 cards + 1 empty decorative slot = 6 slots (2 rows)',
    );
    for (final s in c.suspects) {
      expect(
        find.text(s.name),
        findsOneWidget,
        reason: 'all 5 cards visible at once',
      );
    }
    expect(
      find.byType(ListView),
      findsNothing,
      reason: 'the horizontally scrolling strip is gone',
    );
  });

  testWidgets('clue text is uncapped on selected and unselected cards (UX-9)', (
    tester,
  ) async {
    await tester.pumpWidget(const Harness());
    await tester.pump();

    // Initially Ash (s0) is selected: uncapped clue text.
    final ashSelected = tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ashSelected.maxLines, isNull);

    // Unselected cards are uncapped too: the (taller) card height bounds
    // the text instead of a 2-line ellipsis (UX-9).
    final blair = tester.widget<Text>(
      find.text('Blair was not on the same floor as the victim.'),
    );
    expect(blair.maxLines, isNull);
    expect(blair.overflow, isNull);

    // Tap Blair -> selection moves; Blair expands, Ash stays uncapped.
    await tester.tap(find.text('Blair'));
    await tester.pump();

    final blairSelected = tester.widget<Text>(
      find.text('Blair was not on the same floor as the victim.'),
    );
    expect(blairSelected.maxLines, isNull);
    final ash = tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ash.maxLines, isNull);
  });

  testWidgets('grid fills a pinned height; cards stretch taller (UX-9)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 412,
              height: 400,
              child: SuspectPanel(
                caseData: fixture,
                placed: const {},
                selectedSuspectId: null,
                onSuspectTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gridRect = tester.getRect(find.byType(GridView));
    // The grid fills the pinned slot minus the header row (issue 27): the
    // no-dead-space property is preserved with the header above the grid.
    final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
    expect(
      gridRect.height,
      closeTo(400 - headerRect.height, 0.5),
      reason: 'the grid fills the pinned slot below the header',
    );
    // Two rows split the post-header slot (400 - header) minus 8px padding
    // and one 4px gutter (issue 39: real rows over the post-header slot,
    // not the full pinned height); each card's InkWell fills its tile minus
    // the 4px card padding.
    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<NeverScrollableScrollPhysics>(),
      reason: 'the 2 grown rows fit the post-header slot; no scrolling',
    );
    final cardRect = tester.getRect(find.byType(InkWell).first);
    expect(
      cardRect.height,
      closeTo((400 - headerRect.height - 2 * 4 - 4) / 2 - 2 * 4, 0.5),
      reason: 'cards stretch to fill the post-header slot height',
    );
  });

  testWidgets(
    'each card is a semantic button labelled name + first clue (UX-2)',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(const Harness());
      await tester.pump();

      final node = tester.getSemantics(find.text('Ash'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, contains('Ash was in the Hall.'));
      semantics.dispose();
    },
  );

  testWidgets(
    'wide layout: cards size to their full clue text, no clipping (UX-9)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(wideWrap(multiClueFixture));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      final context = tester.element(find.byType(SuspectPanel));
      final l10n = AppLocalizations.of(context)!;
      final names = NameForms.forLocale(l10n.localeName, multiClueFixture);
      // Per suspect, the exact string its unselected card renders.
      final joinedBySuspect = <String, String>{};
      for (final clue in multiClueFixture.clues) {
        final text = describeClue(clue, multiClueFixture, l10n, names);
        joinedBySuspect[clue.suspectId] =
            joinedBySuspect[clue.suspectId] == null
            ? text
            : '${joinedBySuspect[clue.suspectId]}\n$text';
      }

      // Every paragraph box must be at least the text's ideal height —
      // anything shorter means the pinned 150px card clipped it (Expanded
      // stretches short paragraphs to fill the card, so taller is fine).
      for (final entry in joinedBySuspect.entries) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(entry.value),
        );
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
          reason: 'clues of ${entry.key} render in full on the wide card',
        );
      }
    },
  );

  testWidgets(
    'side panel at 300px: guest names render in full, unclipped (issue 15)',
    (tester) async {
      await tester.pumpWidget(
        sidePanelWrap(
          longNameFixture,
          placed: {'s1': longNameFixture.solution['s1']!},
        ),
      );
      await tester.pump();

      for (final s in longNameFixture.suspects) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(s.name),
        );
        // Height: the box must be at least the name's ideal height at its
        // laid-out width — shorter means the name row clipped the text (the
        // issue's no-clipping property applied to the name row).
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
          reason:
              'name of ${s.id} ("${s.name}") renders in full on the 300px card',
        );
        // Width: pool names are single words and cannot wrap, so nothing may
        // cut them either — the paragraph must lay out at its natural width
        // (today's ellipsis truncates it inside a ~36.7px box).
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5,
          ),
          reason:
              'name of ${s.id} ("${s.name}") is not truncated on the 300px card',
        );
      }
    },
  );

  /// Pumps [poolNameFixture] with every suspect placed at the 300px side
  /// slot and asserts each placed name renders at a readable scale
  /// (issue 18).
  Future<void> expectPlacedNamesAtReadableScale(
    WidgetTester tester,
    Locale locale,
  ) async {
    await tester.pumpWidget(
      sidePanelWrap(
        poolNameFixture,
        locale: locale,
        placed: {
          for (final s in poolNameFixture.suspects)
            s.id: poolNameFixture.solution[s.id]!,
        },
      ),
    );
    await tester.pump();

    final names = NameForms.forLocale(locale.languageCode, poolNameFixture);
    for (final s in poolNameFixture.suspects) {
      final displayed = names.nom(s.id);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(displayed),
      );
      final fitted = tester.renderObject<RenderFittedBox>(
        find.ancestor(
          of: find.text(displayed),
          matching: find.byType(FittedBox),
        ),
      );
      // FittedBox(scaleDown) lays its child out unconstrained, so the
      // paragraph's size is the name's natural, unscaled size; the painted
      // scale is slot width / natural width (capped at 1 by scaleDown).
      final slot = fitted.constraints.maxWidth;
      final scale = math.min(1.0, slot / paragraph.size.width);
      // The bug (issue 18): the inline 18px check icon left the placed name
      // only ~18.7px at the 300px side slot — in this renderer's metrics
      // (Ahem: 1em advance per glyph, titleSmall 14px) the 6-glyph pool
      // names scale to ~0.22. The badge keeps them the unplaced ~36.7px
      // slot.
      expect(
        scale,
        greaterThan(0.35),
        reason: 'placed name "$displayed" ($locale) renders at scale $scale',
      );
      // The AC's explicit slot floor: the placed name keeps ~36px.
      expect(
        slot,
        greaterThanOrEqualTo(36.0),
        reason: 'placed name "$displayed" ($locale) slot is $slot px',
      );
      // The #15 no-truncation guarantee still holds on placed cards in both
      // locales: the paragraph lays out at its natural (unellipsized) width.
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5,
        ),
        reason: 'placed name "$displayed" ($locale) is not truncated',
      );
    }
  }

  testWidgets('side panel at 300px: placed names render at a readable scale '
      '(issue 18, en)', (tester) async {
    await expectPlacedNamesAtReadableScale(tester, const Locale('en'));
  });

  testWidgets('side panel at 300px: placed names render at a readable scale '
      '(issue 18, ru)', (tester) async {
    await expectPlacedNamesAtReadableScale(tester, const Locale('ru'));
  });

  testWidgets('cartoon skin renders suspect cards with token card styling '
      '(issue 23)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Scope at the builder level, mirroring lib/app.dart.
        builder: (context, child) =>
            SkinScope(tokens: stickerTokens, child: child!),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SuspectPanel(
              caseData: fixture,
              placed: const {},
              selectedSuspectId: null,
              onSuspectTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(SuspectPanel),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, stickerTokens.card.background);
    expect(decoration.border?.top.color, stickerTokens.card.borderColor);
    expect(decoration.border?.top.width, stickerTokens.card.borderWidth);
    expect(decoration.boxShadow?.single, stickerTokens.card.shadow);
  });

  /// The exact en clue sentences the [fixture] cards render (see the first
  /// test's wording asserts).
  const clueSentences = {
    'Ash was in the Hall.',
    'Blair was not on the same floor as the victim.',
    'Casey was in the same corridor as Ellis.',
    'Drew was not south of the victim.',
    'Ellis was in the same room as the Clock.',
  };

  Iterable<Container> chipContainers(WidgetTester tester, SkinTokens tokens) =>
      tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == tokens.chip!.background,
        ),
      );

  testWidgets('every clue sentence sits in the skin chip on selected and '
      'unselected cards (issue 26)', (tester) async {
    for (final tokens in [candyTokens, stickerTokens, comicTokens]) {
      // Selected s0 (expanded card) and unselected cards both chip their
      // clues, exactly like the mockups' expanded card.
      await tester.pumpWidget(skinWrap(tokens, selectedId: 's0'));
      await tester.pumpAndSettle();

      var chips = chipContainers(tester, tokens).toList();
      expect(
        chips.length,
        fixture.clues.length,
        reason: '${tokens.skin}: every clue gets its own chip',
      );
      expect(
        chips.map((c) => (c.child! as Text).data!).toSet(),
        clueSentences,
        reason: '${tokens.skin}: the chips carry the clue sentences',
      );
      for (final chip in chips) {
        expect(
          chip.padding,
          tokens.chip!.padding,
          reason: '${tokens.skin}: chip padding comes from the token',
        );
        expect(
          (chip.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(tokens.chip!.radius),
          reason: '${tokens.skin}: chip radius comes from the token',
        );
      }

      // Unselected rendering chips its clue too.
      await tester.pumpWidget(skinWrap(tokens));
      await tester.pumpAndSettle();
      chips = chipContainers(tester, tokens).toList();
      expect(
        chips.length,
        fixture.clues.length,
        reason: '${tokens.skin}: unselected cards chip their clues too',
      );
    }
  });

  testWidgets(
    'classic keeps the pre-existing plain clue rendering (issue 26)',
    (tester) async {
      await tester.pumpWidget(const Harness());
      await tester.pump();

      expect(
        chipContainers(tester, stickerTokens),
        isEmpty,
        reason: 'no chip containers without a cartoon skin scope',
      );
      // The clue sentences still render (joined plain text, as shipped).
      expect(find.text('Ash was in the Hall.'), findsOneWidget);
    },
  );

  /// Describes [multiClueFixture]'s clues in the panel under test: s0's four
  /// clue sentences come first (the fixture lists them first).
  List<String> describeMultiClueSentences(WidgetTester tester) {
    final context = tester.element(find.byType(SuspectPanel));
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, multiClueFixture);
    return [
      for (final clue in multiClueFixture.clues)
        describeClue(clue, multiClueFixture, l10n, names),
    ];
  }

  testWidgets(
    'side panel at 300px: chip clues render in full and rows grow to the '
    'chip content (UX-9, issue 26)',
    (tester) async {
      // A tall surface: the chip rows grow past the default 600px test
      // viewport, and the shrink-wrap grid never builds off-screen rows.
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        skinSidePanelWrap(stickerTokens, multiClueFixture),
      );
      await tester.pump();

      final clueTexts = describeMultiClueSentences(tester);
      // Every chip's paragraph box is at least the text's ideal height —
      // anything shorter means the card clipped the sentence.
      for (final text in clueTexts) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
          reason: 'clue "$text" renders in full on the 300px side panel',
        );
      }

      // s0 carries the four clues: its row must grow to the chip content
      // (per-chip padding + gaps + the narrower chip wrap width), so the
      // scroll viewport shows the whole chip column — nothing hidden below
      // the fold, no scrolling needed (UX-9).
      final scrollView = find.ancestor(
        of: find.text(clueTexts.first),
        matching: find.byType(SingleChildScrollView),
      );
      final viewportHeight = tester.getSize(scrollView).height;
      final contentHeight = tester
          .getSize(
            find
                .descendant(of: scrollView, matching: find.byType(Column))
                .first,
          )
          .height;
      expect(
        contentHeight,
        lessThanOrEqualTo(viewportHeight + 0.5),
        reason:
            'the s0 row grew to its chip content '
            '($contentHeight > $viewportHeight means text sits below the fold)',
      );
    },
  );

  testWidgets('narrow pinned slot: chip clues stay uncapped and never overflow '
      '(UX-9, issue 26)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            SkinScope(tokens: comicTokens, child: child!),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 412,
              height: 400,
              child: SuspectPanel(
                caseData: multiClueFixture,
                placed: const {},
                selectedSuspectId: null,
                onSuspectTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'chip columns scroll in the pinned slot; no RenderFlex '
          'overflow, classic pinned behavior preserved',
    );

    final clueTexts = describeMultiClueSentences(tester);
    // Rows 1's chips (s0's four sentences, Blair's and Casey's cards) are
    // built at the initial offset: they lay out in full on the grown rows.
    for (final text in clueTexts.sublist(0, 6)) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
        reason: 'clue "$text" lays out in full on the pinned narrow grid',
      );
    }

    // Issue 39: the grown rows exceed the post-header slot, so the pinned
    // grid scrolls (the old behavior compressed the rows instead); scroll
    // row 2 (Drew and Ellis) into the viewport's build range and assert
    // there too.
    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<ClampingScrollPhysics>(),
      reason: 'grown chip rows exceeding the slot make the grid scrollable',
    );
    await tester.drag(find.text('Ash'), const Offset(0, -2000));
    await tester.pumpAndSettle();
    for (final text in clueTexts.sublist(6)) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
        reason: 'clue "$text" lays out in full on the pinned narrow grid',
      );
    }
  });

  testWidgets(
    'wide layout: chip clues size cards to their content, no clipping '
    '(UX-9, issue 26)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(skinWideWrap(candyTokens, multiClueFixture));
      await tester.pump();

      final clueTexts = describeMultiClueSentences(tester);
      for (final text in clueTexts) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
          reason: 'clue "$text" renders in full on the wide card at scale 2.0',
        );
      }
    },
  );

  testWidgets('panel header renders the localized title above the grid '
      '(issue 27)', (tester) async {
    await tester.pumpWidget(generatedWrap(fixture));
    await tester.pump();

    expect(find.text('Suspects'), findsOneWidget);
    final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
    final gridRect = tester.getRect(find.byType(GridView));
    expect(
      headerRect.bottom,
      lessThanOrEqualTo(gridRect.top + 0.5),
      reason: 'header sits above the suspect grid',
    );
    expect(
      headerRect.width,
      lessThanOrEqualTo(320.0),
      reason: 'the header row stays inside the 320px viewport',
    );
  });

  testWidgets('panel header shows «Подозреваемые» in ru (issue 27)', (
    tester,
  ) async {
    await tester.pumpWidget(sidePanelWrap(fixture, locale: const Locale('ru')));
    await tester.pump();

    expect(find.text('Подозреваемые'), findsOneWidget);
    expect(find.text('Suspects'), findsNothing);
  });

  testWidgets('comic header uppercase; candy/sticker title case; classic '
      'plain (issue 27)', (tester) async {
    await tester.pumpWidget(skinWrap(comicTokens));
    await tester.pump();
    expect(
      find.text('SUSPECTS'),
      findsOneWidget,
      reason: 'comic renders the header uppercase per its token',
    );
    expect(find.text('Suspects'), findsNothing);
    expect(
      tester.widget<Text>(find.text('SUSPECTS')).style?.color,
      comicTokens.ink,
      reason: 'comic renders the header in its ink token',
    );

    for (final tokens in [candyTokens, stickerTokens]) {
      await tester.pumpWidget(skinWrap(tokens));
      await tester.pump();
      expect(
        find.text('Suspects'),
        findsOneWidget,
        reason: '${tokens.skin} header stays title case per its mockup',
      );
      expect(find.text('SUSPECTS'), findsNothing);
    }

    // No skin scope (bare harness): classic keeps the header, plain styling.
    await tester.pumpWidget(const Harness());
    await tester.pump();
    expect(find.text('Suspects'), findsOneWidget);
    expect(find.text('SUSPECTS'), findsNothing);
    final theme = Theme.of(tester.element(find.byType(SuspectPanel)));
    expect(
      tester.widget<Text>(find.text('Suspects')).style?.color,
      theme.colorScheme.onSurface,
      reason: 'classic keeps the color scheme onSurface tone',
    );
  });

  testWidgets('side panel overflow: grown chip rows make the grid scrollable; '
      'bottom row reachable (issue 30)', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      skinSidePanelWrap(
        stickerTokens,
        overflowFixture,
        onSuspectTap: (id) => tapped = id,
      ),
    );
    await tester.pump();

    // Precondition: the grown rows exceed the slot — the bottom-row card's
    // tap target hangs below the fold of the 600px-tall surface and the
    // shrink-wrap grid offers no scroll affordance for it.
    final ellisCard = find.ancestor(
      of: find.text('Ellis'),
      matching: find.byType(InkWell),
    );
    expect(tester.getRect(ellisCard).bottom, greaterThan(600));

    // Drag the grid itself: Ash's name row sits outside the card's inner
    // chip scroller, so the vertical drag reaches the grid's Scrollable.
    await tester.drag(find.text('Ash'), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<ClampingScrollPhysics>(),
      reason: 'grown rows exceeding the slot make the grid scrollable',
    );
    expect(find.text('Ellis'), findsOneWidget);
    expect(
      find.text('Ellis was in the same room as the Clock.'),
      findsOneWidget,
    );
    expect(
      tester.getRect(ellisCard).bottom,
      lessThanOrEqualTo(600),
      reason: 'the full bottom-row card is on screen after scrolling',
    );
    await tester.tap(find.text('Ellis'));
    expect(tapped, 's4', reason: 'the bottom-row card is tappable');
  });

  testWidgets('side panel overflow (classic): grown plain rows make the grid '
      'scrollable; bottom row reachable (issue 30)', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      sidePanelWrap(overflowFixture, onSuspectTap: (id) => tapped = id),
    );
    await tester.pump();

    // Precondition: the grown rows exceed the slot — the bottom-row card's
    // tap target hangs below the fold of the 600px-tall surface.
    final ellisCard = find.ancestor(
      of: find.text('Ellis'),
      matching: find.byType(InkWell),
    );
    expect(tester.getRect(ellisCard).bottom, greaterThan(600));

    await tester.drag(find.text('Ash'), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<ClampingScrollPhysics>(),
      reason: 'grown rows exceeding the slot make the grid scrollable',
    );
    expect(find.text('Ellis'), findsOneWidget);
    expect(
      find.text('Ellis was in the same room as the Clock.'),
      findsOneWidget,
    );
    expect(
      tester.getRect(ellisCard).bottom,
      lessThanOrEqualTo(600),
      reason: 'the full bottom-row card is on screen after scrolling',
    );
    await tester.tap(find.text('Ellis'));
    expect(tapped, 's4', reason: 'the bottom-row card is tappable');
  });

  testWidgets('side panel fits: grid stays non-scrollable, all cards visible '
      '(issue 30)', (tester) async {
    // Classic renderer at the 600px-tall surface: one plain clue sentence
    // per card fits the slot.
    await tester.pumpWidget(sidePanelWrap(fixture));
    await tester.pump();

    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<NeverScrollableScrollPhysics>(),
      reason: 'content fits the slot; behavior is unchanged',
    );
    for (final s in fixture.suspects) {
      expect(find.text(s.name), findsOneWidget);
    }
    expect(find.byType(Scrollbar), findsNothing);
    expect(
      tester.widget<GridView>(find.byType(GridView)).padding,
      const EdgeInsets.all(4),
      reason: 'no padding change in the fitting layouts',
    );

    // Chip renderer: one chip per card needs a taller surface — at the
    // default 600px one the chip rows genuinely overflow (issue 30 makes
    // that scrollable), so prove the fitting case on an 800px surface.
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(skinSidePanelWrap(stickerTokens, fixture));
    await tester.pump();

    expect(
      tester.widget<GridView>(find.byType(GridView)).physics,
      isA<NeverScrollableScrollPhysics>(),
      reason: 'chip content fits the slot; behavior is unchanged',
    );
    for (final s in fixture.suspects) {
      expect(find.text(s.name), findsOneWidget);
    }
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets(
    'pinned standard case: 3 grown rows overflow the post-header slot; the '
    'grid scrolls and every suspect stays reachable (issue 39)',
    (tester) async {
      final tappedIds = <String>[];
      await tester.pumpWidget(
        pinnedWrap(standardFixture, onSuspectTap: tappedIds.add),
      );
      await tester.pump();

      final gridRect = tester.getRect(find.byType(GridView));
      final finleyCard = find.ancestor(
        of: find.text('Finley'),
        matching: find.byType(InkWell),
      );
      final finleyHeight = tester.getRect(finleyCard).height;

      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: 'grown rows exceeding the post-header slot scroll (issue 39)',
      );
      // Precondition: the sixth card hangs below the fold of the 300px slot.
      expect(tester.getRect(finleyCard).bottom, greaterThan(gridRect.bottom));

      // Scroll every card into view with the grid's own scroll machinery and
      // tap it: the AC's reachability is all six cards, not just the deepest
      // one, and mid-grid hit-test regressions must not pass unnoticed. The
      // trailing empty-slot row wins at max scroll, so centering (not
      // overshoot) is what shows each card fully.
      for (final s in standardFixture.suspects) {
        final card = find.ancestor(
          of: find.text(s.name),
          matching: find.byType(InkWell),
        );
        await Scrollable.ensureVisible(tester.element(card), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.name));
      }
      expect(
        tappedIds.toSet(),
        standardFixture.suspects.map((s) => s.id).toSet(),
        reason: 'all six cards are scrollable into view and tappable',
      );

      // The last card (Finley, centered by the loop) is fully on screen with
      // its grown height preserved — the deepest card's scroll geometry.
      final onScreen = tester.getRect(finleyCard);
      expect(
        onScreen.height,
        closeTo(finleyHeight, 0.5),
        reason: 'scrolled rows keep their grown height',
      );
      expect(
        onScreen.top,
        greaterThanOrEqualTo(gridRect.top - 0.5),
        reason: 'the sixth card is scrolled fully into view',
      );
      expect(
        onScreen.bottom,
        lessThanOrEqualTo(gridRect.bottom + 0.5),
        reason: 'the full bottom-row card is on screen after scrolling',
      );
    },
  );

  testWidgets(
    'pinned standard case (chip skin): overflow scrolls and the sixth card '
    'is reachable (issue 39)',
    (tester) async {
      String? tapped;
      await tester.pumpWidget(
        pinnedWrap(
          standardFixture,
          tokens: stickerTokens,
          onSuspectTap: (id) => tapped = id,
        ),
      );
      await tester.pump();

      final gridRect = tester.getRect(find.byType(GridView));
      final finleyCard = find.ancestor(
        of: find.text('Finley'),
        matching: find.byType(InkWell),
      );
      final finleyHeight = tester.getRect(finleyCard).height;

      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: 'chip grown rows exceeding the post-header slot scroll',
      );
      expect(tester.getRect(finleyCard).bottom, greaterThan(gridRect.bottom));

      await Scrollable.ensureVisible(
        tester.element(finleyCard),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();

      final onScreen = tester.getRect(finleyCard);
      expect(
        onScreen.height,
        closeTo(finleyHeight, 0.5),
        reason: 'scrolled rows keep their grown height',
      );
      expect(onScreen.top, greaterThanOrEqualTo(gridRect.top - 0.5));
      expect(
        onScreen.bottom,
        lessThanOrEqualTo(gridRect.bottom + 0.5),
        reason: 'the full bottom-row card is on screen after scrolling',
      );
      await tester.tap(find.text('Finley'));
      expect(
        tapped,
        's5',
        reason: 'the sixth card is tappable in the chip skin',
      );
    },
  );

  testWidgets(
    'pinned standard case that fits: grid stays non-scrollable and the real '
    '3 rows split the post-header slot (issue 39)',
    (tester) async {
      // A tall narrow surface: grown rows of a generated-style case are far
      // taller than the 300px phone slot, so the fitting premise needs a
      // 700px slot for 3 grown rows to fit (same premise as the UX-2 test's
      // 1400px surface).
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(pinnedWrap(standardFixture, height: 700));
      await tester.pump();

      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<NeverScrollableScrollPhysics>(),
        reason: 'the grown rows fit the post-header slot; no scrolling',
      );
      for (final s in standardFixture.suspects) {
        expect(find.text(s.name), findsOneWidget);
      }
      // The grid fills the post-header slot exactly, and each tile comes
      // from the real 3-row split of that slot (7 children = 6 cards +
      // empty slot): slot minus 2*4 padding minus 2 gutters of 4, minus the
      // 2*4 card padding on the tile.
      final panelRect = tester.getRect(find.byType(SuspectPanel));
      final headerRect = tester.getRect(find.byKey(suspectsPanelHeaderKey));
      final slot = panelRect.bottom - headerRect.bottom;
      final gridRect = tester.getRect(find.byType(GridView));
      expect(
        gridRect.height,
        closeTo(slot, 0.5),
        reason: 'the grid fills the post-header slot (no dead space)',
      );
      final cardRect = tester.getRect(find.byType(InkWell).first);
      expect(
        cardRect.height,
        closeTo((slot - 2 * 4 - 2 * 4) / 3 - 2 * 4, 0.5),
        reason: '3 real rows split the post-header slot',
      );
    },
  );

  testWidgets(
    'pinned hard case keeps the scrollable-more-than-six clause grown-row '
    'heights; the last suspect is reachable (issue 39, non-regression)',
    (tester) async {
      String? tapped;
      await tester.pumpWidget(
        pinnedWrap(hardFixture, onSuspectTap: (id) => tapped = id),
      );
      await tester.pump();

      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: '7 suspects keep the pre-existing scrollable physics',
      );
      // The >6 clause makes this scrollable under the old code too, so pin
      // the issue-39 mechanism directly: row 1 keeps its GROWN height —
      // taller than the pre-fix pinned math's hard-coded 2-row split of the
      // full panel height, which compressed every tile to
      // (height − 12)/2 − 8 (136 here, vs 192 grown at these metrics).
      final panelRect = tester.getRect(find.byType(SuspectPanel));
      final ashCard = find.ancestor(
        of: find.text('Ash'),
        matching: find.byType(InkWell),
      );
      final compressedSplit = (panelRect.height - 2 * 4 - 4) / 2 - 2 * 4;
      expect(
        tester.getRect(ashCard).height,
        greaterThan(compressedSplit + 0.5),
        reason: 'the hard case keeps grown rows, not compressed 2-row tiles',
      );
      // The seventh card sits in row 3, outside the initial viewport's build
      // range; scroll to the end (the last content row IS Grey there, unlike
      // the 6-suspect case's lone empty-slot row) and tap it.
      await tester.drag(find.text('Ash'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grey'));
      expect(tapped, 's6', reason: 'the seventh card is tappable');
    },
  );

  testWidgets(
    'pinned panel survives a tiny slot: rows grow and the grid scrolls '
    '(issue 39)',
    (tester) async {
      await tester.pumpWidget(pinnedWrap(standardFixture, height: 120));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the fill split only applies when it fits; no negative rows',
      );
      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: 'the grown rows cannot fit a 120px slot; the grid scrolls',
      );
    },
  );

  testWidgets(
    'pinned standard case at textScale 2.0: chip rows overflow the slot and '
    'the grid scrolls without exceptions (issue 39)',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        pinnedWrap(standardFixture, tokens: stickerTokens),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: 'scale-2.0 chip rows exceed the slot; the grid scrolls',
      );
    },
  );

  testWidgets(
    'pinned multi-clue case at textScale 2.0: bottom-row clue text scrolls '
    'fully into view, never clipped, in both renderers (issue 40)',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // The surfaces are taller than the default test window; resize it so
      // the pinned host really gets [height] (like the fit-premise tests).
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      // (tokens, pinned surface height): the post-header slot must fit ONE
      // grown row while two still overflow it — then scroll-to-visible can
      // fully show a bottom-row card AND the scrolling physics stays on
      // (issue 39's mechanism AC3 relies on). Grown tile heights at these
      // test metrics (measured: ~1467px classic, ~2182px sticker chip at the
      // 360px pinned card width, scale 2.0; header ~60px) give 1700 classic
      // and 2400 chip: ~170/158px headroom above one grown row either way.
      // A failure here means the premise drifted — re-measure the grown tile
      // heights against the current test-font metrics before suspecting a
      // layout regression.
      final surfaces = <(SkinTokens?, double)>[
        (null, 1700),
        (stickerTokens, 2400),
      ];

      for (final (tokens, height) in surfaces) {
        tester.view.physicalSize = Size(800, height + 100);
        await tester.pumpWidget(
          pinnedWrap(multiClueFixture, tokens: tokens, height: height),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the scale-2.0 multi-clue pinned layout lays out cleanly',
        );
        expect(
          tester.widget<GridView>(find.byType(GridView)).physics,
          isA<ClampingScrollPhysics>(),
          reason:
              'grown multi-clue rows exceed the post-header slot at '
              'textScale 2.0; the grid scrolls (issue 39 mechanism)',
        );

        // Clue sentences grouped by SUSPECT IDENTITY (never by flat-list
        // position), rendered exactly as the panel renders them: Classic
        // joins each card's sentences with newlines, chip mode keeps one
        // Text per sentence.
        final context = tester.element(find.byType(SuspectPanel));
        final l10n = AppLocalizations.of(context)!;
        final names = NameForms.forLocale(l10n.localeName, multiClueFixture);
        final sentencesById = <String, List<String>>{};
        for (final clue in multiClueFixture.clues) {
          (sentencesById[clue.suspectId] ??= []).add(
            describeClue(clue, multiClueFixture, l10n, names),
          );
        }
        String joinedById(String id) => sentencesById[id]!.join('\n');
        final expectedTexts = tokens == null
            // Classic: one joined Text per card.
            ? [joinedById('s0'), joinedById('s3'), joinedById('s4')]
            // Chip: one Text per clue sentence.
            : [
                for (final id in ['s0', 's3', 's4']) ...sentencesById[id]!,
              ];

        // The grown (multi-clue) card's and the bottom row's clue text lays
        // out in full at scale 2.0: each paragraph box is at least its ideal
        // height — anything shorter means the card clipped the text.
        for (final text in expectedTexts) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
            reason: 'clue text renders in full on the pinned grid at 2.0',
          );
        }

        final gridRect = tester.getRect(find.byType(GridView));
        final bottomRowNames = ['Drew', 'Ellis'];
        String clueOf(String name) => joinedById(name == 'Drew' ? 's3' : 's4');
        Finder cardOf(String name) =>
            find.ancestor(of: find.text(name), matching: find.byType(InkWell));

        // Precondition, before ANY scrolling: both bottom-row cards hang
        // below the fold (their bottoms are past the viewport), so only
        // scroll-to-visible can show them — the scroll path AC3 requires
        // is actually exercised.
        for (final name in bottomRowNames) {
          expect(
            tester.getRect(cardOf(name)).bottom,
            greaterThan(gridRect.bottom),
            reason: '$name hangs below the fold of the ${height}px pinned slot',
          );
        }

        for (final name in bottomRowNames) {
          final clue = clueOf(name);
          final card = cardOf(name);
          await Scrollable.ensureVisible(tester.element(card), alignment: 0.5);
          await tester.pumpAndSettle();

          final cardRect = tester.getRect(card);
          expect(
            cardRect.top,
            greaterThanOrEqualTo(gridRect.top - 0.5),
            reason: '$name card scrolled fully inside the grid viewport',
          );
          expect(
            cardRect.bottom,
            lessThanOrEqualTo(gridRect.bottom + 0.5),
            reason: '$name card scrolled fully inside the grid viewport',
          );

          // Its clue text is inside the shown card: fully visible and never
          // clipped by the card.
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(clue),
          );
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
            reason: '$name clue renders in full after scroll-to-visible',
          );
          final textRect = tester.getRect(find.text(clue));
          expect(
            textRect.top,
            greaterThanOrEqualTo(gridRect.top - 0.5),
            reason: '$name clue text fully on screen',
          );
          expect(
            textRect.bottom,
            lessThanOrEqualTo(gridRect.bottom + 0.5),
            reason: '$name clue text fully on screen',
          );
        }

        expect(tester.takeException(), isNull);
      }
    },
  );

  group('sentence coverage pins (issue 35)', () {
    Future<(AppLocalizations, NameForms)> l10nAndNames(
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const Harness());
      await tester.pump();
      final context = tester.element(find.byType(SuspectPanel));
      final l10n = AppLocalizations.of(context)!;
      return (l10n, NameForms.forLocale(l10n.localeName, fixture));
    }

    testWidgets('negated same-col clue renders the not-in-corridor sentence', (
      tester,
    ) async {
      final (l10n, names) = await l10nAndNames(tester);
      expect(
        describeClue(
          const SameCol(suspectId: 's2', targetId: 's4', negated: true),
          fixture,
          l10n,
          names,
        ),
        'Casey was not in the same corridor as Ellis.',
      );
    });

    testWidgets('negated beside-object clue renders the not-in-room sentence', (
      tester,
    ) async {
      final (l10n, names) = await l10nAndNames(tester);
      expect(
        describeClue(
          const BesideObject(suspectId: 's4', objectId: 'o1', negated: true),
          fixture,
          l10n,
          names,
        ),
        'Ellis was not in the same room as the Clock.',
      );
    });
  });

  group('layout and label coverage pins (issue 35)', () {
    testWidgets(
      'unbounded height: the narrow grid shrink-wraps and shows every card',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 320,
                  child: SuspectPanel(
                    caseData: fixture,
                    placed: const {},
                    selectedSuspectId: null,
                    onSuspectTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Neither pinned nor bounded: the grid branch runs unscrollable and
        // every card is built (no viewport recycling below the fold).
        expect(
          tester.widget<GridView>(find.byType(GridView)).physics,
          isA<NeverScrollableScrollPhysics>(),
        );
        for (final s in fixture.suspects) {
          expect(find.text(s.name), findsOneWidget);
        }
      },
    );

    testWidgets('a suspect with no clues labels its card with just the name', (
      tester,
    ) async {
      final cluelessCase = buildFixture([
        SameRow(suspectId: 's1', targetId: 'V', negated: false),
        SameCol(suspectId: 's2', targetId: 's4', negated: false),
        InRoom(suspectId: 's3', roomId: 'r3', negated: false),
        BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
      ]);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(generatedWrap(cluelessCase));
      await tester.pump();

      final node = tester.getSemantics(find.text('Ash'));
      // The card's own a11y label is the bare name (the merged node also
      // carries the card text's label after it). With no clues there is no
      // clue sentence after the name.
      expect(node.label, startsWith('Ash.'));
      expect(node.label, isNot(contains('was in the')));
      semantics.dispose();
    });
  });
}
