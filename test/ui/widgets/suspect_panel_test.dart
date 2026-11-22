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
        RoomDef(id: 'r0', name: 'Hall', cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)]),
        RoomDef(id: 'r1', name: 'Library', cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)]),
        RoomDef(id: 'r2', name: 'Kitchen', cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)]),
        RoomDef(id: 'r3', name: 'Cellar', cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)]),
        RoomDef(id: 'r4', name: 'Study', cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)]),
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
      suspectId: 's3', targetId: 'V', direction: Direction.south, negated: true),
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
      suspectId: 's3', targetId: 'V', direction: Direction.south, negated: true),
  BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
]);

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
}) =>
    MaterialApp(
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

/// The 300px side slot exactly as the wide game screen hosts the panel:
/// bounded but loose height, so the panel renders the grid branch and
/// grows content-sized rows (issue 15). [locale] pins the l10n under test
/// (pool names resolve through the localized pools, issue 18); the
/// localization setup comes from the shared helper (issue 21).
Widget sidePanelWrap(
  CaseData c, {
  Map<String, Pos> placed = const {},
  Locale locale = const Locale('en'),
}) =>
    localizedTestApp(
      locale: locale,
      child: Align(
        child: SizedBox(
          width: 300,
          child: SuspectPanel(
            caseData: c,
            placed: placed,
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
  testWidgets('every suspect card shows its name and its clue sentences',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(Harness(onSuspectTap: (id) => tapped = id));
    await tester.pump();

    // The grid shows all cards at once; assert each name and exact en wording.
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Ash was in the Hall.'), findsOneWidget);
    expect(find.text('Blair'), findsOneWidget);
    expect(find.text('Blair was not on the same floor as the victim.'),
        findsOneWidget);
    expect(find.text('Casey'), findsOneWidget);
    expect(find.text('Casey was in the same corridor as Ellis.'),
        findsOneWidget);
    expect(find.text('Drew'), findsOneWidget);
    expect(find.text('Drew was not south of the victim.'), findsOneWidget);
    expect(find.text('Ellis'), findsOneWidget);
    expect(find.text('Ellis was in the same room as the Clock.'), findsOneWidget);

    // Placed suspect is marked.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tapping a card selects that suspect.
    await tester.tap(find.text('Drew'));
    expect(tapped, 's3');
  });

  testWidgets('suspects render as a 3x2 grid; no horizontal strip (UX-2)',
      (tester) async {
    final c = generateCase(difficulty: Difficulty.easy, seed: 3);
    await tester.pumpWidget(generatedWrap(c));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.physics, isA<NeverScrollableScrollPhysics>(),
        reason: '5 suspects fit the grid; no scrolling needed');
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3, reason: '3 columns');
    final childrenDelegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(childrenDelegate.children.length, 6,
        reason: '5 cards + 1 empty decorative slot = 6 slots (2 rows)');
    for (final s in c.suspects) {
      expect(find.text(s.name), findsOneWidget,
          reason: 'all 5 cards visible at once');
    }
    expect(find.byType(ListView), findsNothing,
        reason: 'the horizontally scrolling strip is gone');
  });

  testWidgets('clue text is uncapped on selected and unselected cards (UX-9)',
      (tester) async {
    await tester.pumpWidget(const Harness());
    await tester.pump();

    // Initially Ash (s0) is selected: uncapped clue text.
    final ashSelected =
        tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ashSelected.maxLines, isNull);

    // Unselected cards are uncapped too: the (taller) card height bounds
    // the text instead of a 2-line ellipsis (UX-9).
    final blair = tester
        .widget<Text>(find.text('Blair was not on the same floor as the victim.'));
    expect(blair.maxLines, isNull);
    expect(blair.overflow, isNull);

    // Tap Blair -> selection moves; Blair expands, Ash stays uncapped.
    await tester.tap(find.text('Blair'));
    await tester.pump();

    final blairSelected = tester
        .widget<Text>(find.text('Blair was not on the same floor as the victim.'));
    expect(blairSelected.maxLines, isNull);
    final ash = tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ash.maxLines, isNull);
  });

  testWidgets('grid fills a pinned height; cards stretch taller (UX-9)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pump();

    final gridRect = tester.getRect(find.byType(GridView));
    expect(gridRect.height, 400, reason: 'the grid fills the pinned slot');
    // Two rows split the 400px slot minus 8px padding and one 4px gutter;
    // each card's InkWell fills its tile minus the 4px card padding.
    final cardRect = tester.getRect(find.byType(InkWell).first);
    expect(cardRect.height, closeTo((400 - 2 * 4 - 4) / 2 - 2 * 4, 0.5),
        reason: 'cards stretch to fill the slot height');
  });

  testWidgets('each card is a semantic button labelled name + first clue (UX-2)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const Harness());
    await tester.pump();

    final node = tester.getSemantics(find.text('Ash'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains('Ash was in the Hall.'));
    semantics.dispose();
  });

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
      joinedBySuspect[clue.suspectId] = joinedBySuspect[clue.suspectId] == null
          ? text
          : '${joinedBySuspect[clue.suspectId]}\n$text';
    }

    // Every paragraph box must be at least the text's ideal height —
    // anything shorter means the pinned 150px card clipped it (Expanded
    // stretches short paragraphs to fill the card, so taller is fine).
    for (final entry in joinedBySuspect.entries) {
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(entry.value));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(idealParagraphHeight(paragraph) - 0.5),
        reason: 'clues of ${entry.key} render in full on the wide card',
      );
    }
  });

  testWidgets(
      'side panel at 300px: guest names render in full, unclipped (issue 15)',
      (tester) async {
    await tester.pumpWidget(sidePanelWrap(
      longNameFixture,
      placed: {'s1': longNameFixture.solution['s1']!},
    ));
    await tester.pump();

    for (final s in longNameFixture.suspects) {
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(s.name));
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
            paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5),
        reason:
            'name of ${s.id} ("${s.name}") is not truncated on the 300px card',
      );
    }
  });

  /// Pumps [poolNameFixture] with every suspect placed at the 300px side
  /// slot and asserts each placed name renders at a readable scale
  /// (issue 18).
  Future<void> expectPlacedNamesAtReadableScale(
      WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(sidePanelWrap(
      poolNameFixture,
      locale: locale,
      placed: {
        for (final s in poolNameFixture.suspects)
          s.id: poolNameFixture.solution[s.id]!,
      },
    ));
    await tester.pump();

    final names = NameForms.forLocale(locale.languageCode, poolNameFixture);
    for (final s in poolNameFixture.suspects) {
      final displayed = names.nom(s.id);
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(displayed));
      final fitted = tester.renderObject<RenderFittedBox>(
        find.ancestor(of: find.text(displayed), matching: find.byType(FittedBox)),
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
            paragraph.getMinIntrinsicWidth(paragraph.size.height) - 0.5),
        reason: 'placed name "$displayed" ($locale) is not truncated',
      );
    }
  }

  testWidgets(
      'side panel at 300px: placed names render at a readable scale '
      '(issue 18, en)', (tester) async {
    await expectPlacedNamesAtReadableScale(tester, const Locale('en'));
  });

  testWidgets(
      'side panel at 300px: placed names render at a readable scale '
      '(issue 18, ru)', (tester) async {
    await expectPlacedNamesAtReadableScale(tester, const Locale('ru'));
  });

  testWidgets('cartoon skin renders suspect cards with token card styling '
      '(issue 23)', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
        find.descendant(
            of: find.byType(SuspectPanel),
            matching: find.byType(Container)).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, stickerTokens.card.background);
    expect(decoration.border?.top.color, stickerTokens.card.borderColor);
    expect(decoration.border?.top.width, stickerTokens.card.borderWidth);
    expect(decoration.boxShadow?.single, stickerTokens.card.shadow);
  });
}
