import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

import '../../support/localized_test_app.dart';
import 'suspect_panel_test.dart'
    show
        fixture,
        multiClueFixture,
        sidePanelWrap,
        skinSidePanelWrap,
        skinWrap,
        standardFixture,
        suspectCardOf;

/// The segments' comparable shape: (text, roomIndex-or-null) per segment —
/// lets the tests pin the exact segment split without == on the classes.
List<(String, int?)> shapeOf(List<ClueSegment> segments) => [
  for (final s in segments)
    s is RoomClueSegment ? (s.text, s.roomIndex) : (s.text, null),
];

/// The fixture board with pool-indexed rooms (generated cases resolve room
/// names through the localized pools; the legacy fixture's rooms have none,
/// so ru falls back to 'в Library'): r0..r4 map to pool rooms 0..4. s0's
/// clue moves to r1 so the ru chip label pins the pool prep phrase.
final CaseData poolRoomFixture = fixture.copyWith(
  rooms: [
    for (final (i, room) in fixture.rooms.indexed)
      RoomDef(id: room.id, name: room.name, cells: room.cells, poolIndex: i),
  ],
  clues: const [InRoom(suspectId: 's0', roomId: 'r1', negated: false)],
);

/// (l10n, names) for [locale] against the shared fixture: pumps a minimal
/// localized host and grabs the real localization + name resolver.
Future<(AppLocalizations, NameForms)> l10nFor(
  WidgetTester tester,
  Locale locale,
) async {
  await tester.pumpWidget(
    localizedTestApp(
      locale: locale,
      child: const SizedBox.shrink(key: ValueKey('chip-probe')),
    ),
  );
  final context = tester.element(find.byKey(const ValueKey('chip-probe')));
  return (
    AppLocalizations.of(context)!,
    NameForms.forLocale(locale.languageCode, fixture),
  );
}

void main() {
  group('clue segments (issue 104)', () {
    testWidgets('en positive InRoom: dash + prefix + room chip', (
      tester,
    ) async {
      final (l10n, names) = await l10nFor(tester, const Locale('en'));
      final clue = fixture.clues.first;
      expect(
        clue,
        isA<InRoom>(),
        reason: 'premise: s0 carries the InRoom clue',
      );
      expect(shapeOf(describeClueSegments(clue, fixture, l10n, names)), const [
        ('— ', null),
        ('in the ', null),
        ('Hall', 0),
      ]);
    });

    testWidgets('en negated InRoom: "not in the" prefix still chips the room', (
      tester,
    ) async {
      final (l10n, names) = await l10nFor(tester, const Locale('en'));
      const clue = InRoom(suspectId: 's0', roomId: 'r0', negated: true);
      expect(shapeOf(describeClueSegments(clue, fixture, l10n, names)), const [
        ('— ', null),
        ('not in the ', null),
        ('Hall', 0),
      ]);
    });

    testWidgets('ru positive InRoom: no prefix segment, full prep phrase', (
      tester,
    ) async {
      final (l10n, _) = await l10nFor(tester, const Locale('ru'));
      final names = NameForms.forLocale('ru', poolRoomFixture);
      const clue = InRoom(suspectId: 's0', roomId: 'r1', negated: false);
      expect(
        shapeOf(describeClueSegments(clue, poolRoomFixture, l10n, names)),
        const [('— ', null), ('в библиотеке', 1)],
      );
    });

    testWidgets('non-room kinds: dash + one plain segment, no room chip', (
      tester,
    ) async {
      final (l10n, names) = await l10nFor(tester, const Locale('en'));
      final clue = fixture.clues[1]; // SameRow(s1, V, negated: true)
      expect(
        clue,
        isA<SameRow>(),
        reason: 'premise: the second clue is SameRow',
      );
      expect(shapeOf(describeClueSegments(clue, fixture, l10n, names)), const [
        ('— ', null),
        ('not in the same row as the victim', null),
      ]);
    });

    testWidgets('roomIndex follows caseData.rooms order (fixture r3 -> 3)', (
      tester,
    ) async {
      final (l10n, names) = await l10nFor(tester, const Locale('en'));
      const clue = InRoom(suspectId: 's0', roomId: 'r3', negated: false);
      final segments = describeClueSegments(clue, fixture, l10n, names);
      expect(
        segments.whereType<RoomClueSegment>().single.roomIndex,
        3,
        reason:
            'the room index is the legend/board order, not the palette index',
      );
    });

    testWidgets('a stored name occurring mid-template keeps the trailing '
        'plain segment (issue 107: de-dotting made every template end at '
        'the room; legacy names can still occur mid-template and the split '
        'stays lossless)', (tester) async {
      final (l10n, _) = await l10nFor(tester, const Locale('en'));
      final legacy = fixture.copyWith(
        rooms: [
          for (final (i, room) in fixture.rooms.indexed)
            RoomDef(
              id: room.id,
              name: i == 0 ? 'in' : room.name,
              cells: room.cells,
            ),
        ],
        clues: const [InRoom(suspectId: 's0', roomId: 'r0', negated: false)],
      );
      final names = NameForms.forLocale('en', legacy);
      // "— in the in": the name "in" first occurs inside the en prefix, so
      // the room chip lands mid-sentence and the trailing words stay a
      // plain segment.
      expect(
        shapeOf(describeClueSegments(legacy.clues.first, legacy, l10n, names)),
        const [('— ', null), ('in', 0), (' the in', null)],
      );
    });

    testWidgets('segments join back to the plain describeClue sentence', (
      tester,
    ) async {
      final (l10n, names) = await l10nFor(tester, const Locale('en'));
      for (final clue in fixture.clues) {
        final plain = describeClue(clue, fixture, l10n, names);
        expect(
          describeClueSegments(
            clue,
            fixture,
            l10n,
            names,
          ).map((s) => s.text).join(),
          plain,
          reason: 'the segments are a lossless split of "$plain"',
        );
      }
    });
  });

  group('room chip rendering (issue 104)', () {
    /// The chip Containers inside the sentence's rich-text subtree.
    List<Container> chipContainersOf(WidgetTester tester, Finder sentence) =>
        tester
            .widgetList<Container>(
              find.descendant(of: sentence, matching: find.byType(Container)),
            )
            .toList();

    /// The chip label's expected ink on [tokens] (tint-derived, AA).
    Color expectedInk(SkinTokens tokens, int roomIndex) => clueChipInk(
      clueChipEffectiveBackground(tokens, roomIndex, tokens.card.background),
    );

    testWidgets('sticker: the room phrase renders as a chip in the room tint', (
      tester,
    ) async {
      await tester.pumpWidget(skinWrap(stickerTokens));
      await tester.pumpAndSettle();

      // The sentence's plain text carries the \uFFFC placeholder where the
      // chip sits.
      final sentence = find.text('— in the \uFFFC');
      expect(sentence, findsOneWidget);
      final chips = chipContainersOf(tester, sentence);
      expect(chips, hasLength(1));
      final decoration = chips.single.decoration! as BoxDecoration;
      expect(decoration.color, stickerTokens.roomTints[0]);
      expect(decoration.borderRadius, BorderRadius.circular(clueChipRadius));

      // Chip label: the room phrase in the tint-derived AA ink.
      expect(
        tester.widget<Text>(find.text('Hall')).style?.color,
        expectedInk(stickerTokens, 0),
      );
    });

    testWidgets('sticker: non-room sentences carry no chip; the dash span is '
        '0.75x the sentence font size', (tester) async {
      await tester.pumpWidget(skinWrap(stickerTokens));
      await tester.pumpAndSettle();

      final blair = find.text('— not in the same row as the victim');
      expect(blair, findsOneWidget);
      expect(
        find.descendant(of: blair, matching: find.byType(Container)),
        findsNothing,
        reason: 'same-row/col/direction/item sentences never chip',
      );

      // Dash first span at 0.75x; the plain segments keep the sentence size.
      final sentenceStyle = Theme.of(tester.element(find.byType(SuspectPanel)))
          .textTheme
          .bodySmall!;
      final spans =
          ((tester.widget<Text>(blair).textSpan!) as TextSpan).children!;
      final dash = spans.first as TextSpan;
      expect(dash.text, '— ');
      expect(
        dash.style!.fontSize,
        closeTo(sentenceStyle.fontSize! * clueDashFontScale, 0.001),
      );
      expect((spans[1] as TextSpan).style!.fontSize, sentenceStyle.fontSize);
    });

    testWidgets('sticker: a negated InRoom sentence still chips the room', (
      tester,
    ) async {
      final negatedRoomFixture = fixture.copyWith(
        clues: const [InRoom(suspectId: 's0', roomId: 'r0', negated: true)],
      );
      await tester.pumpWidget(skinWrap(stickerTokens, c: negatedRoomFixture));
      await tester.pumpAndSettle();

      final sentence = find.text('— not in the \uFFFC');
      expect(sentence, findsOneWidget);
      final chips = chipContainersOf(tester, sentence);
      expect(
        (chips.single.decoration! as BoxDecoration).color,
        stickerTokens.roomTints[0],
      );
    });

    testWidgets('candy and comic chip parity with their own tint palettes', (
      tester,
    ) async {
      for (final tokens in [candyTokens, comicTokens]) {
        await tester.pumpWidget(skinWrap(tokens));
        await tester.pumpAndSettle();
        final chips = chipContainersOf(tester, find.text('— in the \uFFFC'));
        expect(
          (chips.single.decoration! as BoxDecoration).color,
          tokens.roomTints[0],
          reason: '${tokens.skin}: the chip fills with the room board tint',
        );
        expect(
          tester.widget<Text>(find.text('Hall')).style?.color,
          expectedInk(tokens, 0),
        );
      }
    });

    testWidgets('classic: chip fills the alpha-0.55 legend swatch over the '
        'card surface; the dash span scales there too', (tester) async {
      await tester.pumpWidget(sidePanelWrap(fixture));
      await tester.pump();

      final sentence = find.text('— in the \uFFFC');
      expect(sentence, findsOneWidget);
      final bg = classicRoomTints[0].withValues(alpha: 0.55);
      final chips = chipContainersOf(tester, sentence);
      expect((chips.single.decoration! as BoxDecoration).color, bg);

      final element = tester.element(find.byType(SuspectPanel));
      expect(
        tester.widget<Text>(find.text('Hall')).style?.color,
        clueChipInk(
          Color.alphaBlend(
            bg,
            Theme.of(element).colorScheme.surfaceContainerHighest,
          ),
        ),
      );
      // Classic's joined paragraph opens with the scaled dash span (two
      // levels down: paragraph root -> sentence span -> dash span).
      final sentenceStyle = Theme.of(element).textTheme.bodySmall!;
      final root = (tester.widget<Text>(sentence).textSpan!) as TextSpan;
      final firstSentence = root.children!.first as TextSpan;
      final dashSpan = firstSentence.children!.first as TextSpan;
      expect(dashSpan.text, '— ');
      expect(
        dashSpan.style!.fontSize,
        closeTo(sentenceStyle.fontSize! * clueDashFontScale, 0.001),
      );
    });

    testWidgets('chip rows grow to their content in the loose 300px side '
        'panel (issues 104/26/UX-9)', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        skinSidePanelWrap(stickerTokens, multiClueFixture),
      );
      await tester.pump();

      // s0 carries four clues, the first room-bearing: its row must grow to
      // the rich content (the chip's reserved box included) so the card's
      // scroll viewport shows the whole column.
      final scrollView = find.descendant(
        of: suspectCardOf('s0'),
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
    });

    testWidgets('ru: the chip label is the full pool prep phrase', (
      tester,
    ) async {
      await tester.pumpWidget(
        localizedTestApp(
          locale: const Locale('ru'),
          child: SkinScope(
            tokens: stickerTokens,
            child: Align(
              child: SizedBox(
                width: 300,
                child: SuspectPanel(
                  caseData: poolRoomFixture,
                  placed: const {},
                  selectedSuspectId: null,
                  onSuspectTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('в библиотеке'), findsOneWidget);
      final sentence = find.text('— \uFFFC');
      expect(sentence, findsOneWidget);
      final chips = chipContainersOf(tester, sentence);
      expect(
        (chips.single.decoration! as BoxDecoration).color,
        stickerTokens.roomTints[1],
        reason: 'r1 (library) is room index 1 in the legend/board order',
      );
    });
  });

  group('room chip rows at any text scale (issue 104)', () {
    /// The landscape game screen's header-less host (issue 103): tight 575
    /// x 277 — the narrow grid branch with 2 columns and content-height
    /// rows.
    Widget landscapeWrap(CaseData c, SkinTokens tokens) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => SkinScope(tokens: tokens, child: child!),
      home: Scaffold(
        body: Align(
          child: SizedBox(
            width: 575,
            height: 277,
            child: SuspectPanel(
              caseData: c,
              placed: const {},
              selectedSuspectId: null,
              onSuspectTap: (_) {},
              showHeader: false,
            ),
          ),
        ),
      ),
    );

    testWidgets('landscape host at textScale 2.0: chip rows overflow the '
        'slot, the grid scrolls, nothing throws (issues 104/103/39)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(landscapeWrap(standardFixture, stickerTokens));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the scale-2.0 chip layout lays out cleanly, chips included',
      );
      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<ClampingScrollPhysics>(),
        reason: 'grown chip rows exceed the 277px slot; the grid scrolls',
      );
    });
  });

  group('room chip colors (issue 104)', () {
    /// The AA bar: chip label ink vs the chip's effective background.
    void expectAA(Color ink, Color bg, String skin) {
      expect(
        clueContrastRatio(ink, bg),
        greaterThanOrEqualTo(4.5),
        reason:
            '$skin: chip ink $ink reads '
            '${clueContrastRatio(ink, bg).toStringAsFixed(2)}:1 on bg $bg',
      );
    }

    test('cartoon skins: ink on the opaque tint reaches AA for every tint', () {
      for (final tokens in [candyTokens, stickerTokens, comicTokens]) {
        for (var i = 0; i < tokens.roomTints.length; i++) {
          final bg = clueChipBackground(tokens, i);
          expect(bg, tokens.roomTints[i % tokens.roomTints.length]);
          expectAA(clueChipInk(bg), bg, '${tokens.skin} tint #$i');
        }
      }
    });

    test('classic light: ink reaches AA over the composited legend swatch '
        'and stays the darker shade', () {
      final card = AppTheme.light.colorScheme.surfaceContainerHighest;
      for (var i = 0; i < classicRoomTints.length; i++) {
        final bg = clueChipEffectiveBackground(null, i, card);
        final ink = clueChipInk(bg);
        expectAA(ink, bg, 'classic light tint #$i');
        expect(
          ink.computeLuminance(),
          lessThan(bg.computeLuminance()),
          reason: 'classic light tint #$i: the ink is the darker shade',
        );
      }
    });

    test('classic dark: ink reaches AA over the dark composited swatch', () {
      final card = AppTheme.dark.colorScheme.surfaceContainerHighest;
      for (var i = 0; i < classicRoomTints.length; i++) {
        final bg = clueChipEffectiveBackground(null, i, card);
        expectAA(clueChipInk(bg), bg, 'classic dark tint #$i');
      }
    });

    test('classic chip background is the legend-swatch alpha 0.55', () {
      expect(
        clueChipBackground(null, 0),
        classicRoomTints[0].withValues(alpha: 0.55),
      );
    });

    test('tint index wraps modulo the palette like the legend and board', () {
      expect(
        clueChipBackground(stickerTokens, stickerTokens.roomTints.length),
        stickerTokens.roomTints[0],
        reason: 'room 9 (index 8) wraps to the first tint',
      );
      expect(
        clueChipBackground(stickerTokens, stickerTokens.roomTints.length + 2),
        stickerTokens.roomTints[2],
        reason: 'room 11 (index 10) wraps to the third tint',
      );
    });
  });
}
