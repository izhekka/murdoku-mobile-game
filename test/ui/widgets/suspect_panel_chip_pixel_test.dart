import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

/// Issue 89/104 render-path proofs: rasterizing the suspect panel headless
/// and asserting on raw pixels. Issue 89 pinned the retired clue pill's
/// removal (zero pixels of the retired chip surfaces — candy #D8E0EE,
/// sticker/comic #F1F3F5). Issue 104 pins the room label chip's paint: the
/// rounded chip fills with the room's board tint and its label paints the
/// tint-derived AA ink inside the room sentence's box, and the 0.75x dash
/// paints strictly fewer pixels than a full-size dash.
Pos p(int row, int col) => (row: row, col: col);

final CaseData pixelCase = CaseData(
  seed: 5,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(
      id: 'r0',
      name: 'Kitchen',
      cells: [p(0, 0), p(0, 1), p(1, 0), p(1, 1)],
      poolIndex: 2,
    ),
  ],
  objects: [ObjectDef(id: 'o0', kind: ObjectKind.clock, pos: p(1, 1))],
  suspects: const [Suspect(id: 's0', name: 'Ash', poolIndex: 9)],
  victimPos: p(0, 1),
  murdererId: 's0',
  clues: const [
    InRoom(suspectId: 's0', roomId: 'r0', negated: false),
    // A non-room sentence for the issue-89 card-surface pin: it must keep
    // painting directly on the card background.
    SameRow(suspectId: 's0', targetId: 'V', negated: false),
  ],
  solution: {'s0': p(0, 0)},
);

/// Pixels inside the physical [rect] whose RGB matches [target] within
/// [tol] per channel.
int countMatches(
  Uint8List bytes,
  int width,
  Rect rect,
  int target, {
  int tol = 0,
}) {
  final tr = (target >> 16) & 0xFF;
  final tg = (target >> 8) & 0xFF;
  final tb = target & 0xFF;
  var count = 0;
  for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
    for (var x = rect.left.round(); x < rect.right.round(); x++) {
      final i = (y * width + x) * 4;
      if ((bytes[i] - tr).abs() <= tol &&
          (bytes[i + 1] - tg).abs() <= tol &&
          (bytes[i + 2] - tb).abs() <= tol) {
        count++;
      }
    }
  }
  return count;
}

/// Pixels inside the physical [rect] that differ from white by more than
/// [tol] per channel (the ink counter of the dash proof).
int countNonWhite(Uint8List bytes, int width, Rect rect, {int tol = 8}) {
  var count = 0;
  for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
    for (var x = rect.left.round(); x < rect.right.round(); x++) {
      final i = (y * width + x) * 4;
      if ((255 - bytes[i]).abs() > tol ||
          (255 - bytes[i + 1]).abs() > tol ||
          (255 - bytes[i + 2]).abs() > tol) {
        count++;
      }
    }
  }
  return count;
}

/// Rasterizes the panel boundary at dpr 3 and returns (bytes, pixel width).
Future<(Uint8List, int)> capturePanel(
  WidgetTester tester,
  String captureKey,
) async {
  var bytes = Uint8List(0);
  var width = 0;
  // toImage submits to the real IO task queue, which the fake-async test
  // zone forbids: run the capture in runAsync (like the golden matchers'
  // captureImage does).
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(ValueKey<String>(captureKey)),
    );
    final image = await boundary.toImage(pixelRatio: 3.0);
    width = image.width;
    bytes = Uint8List.fromList(
      (await image.toByteData())!.buffer.asUint8List(),
    );
    image.dispose();
  });
  return (bytes, width);
}

/// The rendered plain text of [segments]: the room chip is a \uFFFC
/// placeholder in the RichText's plain text.
String renderedPlainOf(List<ClueSegment> segments) =>
    segments.map((s) => s is RoomClueSegment ? '\uFFFC' : s.text).join();

/// [rect] scaled to the 3x capture.
Rect physicalOf(Rect rect) =>
    Rect.fromLTRB(rect.left * 3, rect.top * 3, rect.right * 3, rect.bottom * 3);

/// True when [rgb] matches [target] within [tol] per channel.
bool closeRgb(int rgb, int target, {int tol = 3}) {
  bool channel(int v, int t) => (v - t).abs() <= tol;
  return channel((rgb >> 16) & 0xFF, (target >> 16) & 0xFF) &&
      channel((rgb >> 8) & 0xFF, (target >> 8) & 0xFF) &&
      channel(rgb & 0xFF, target & 0xFF);
}

/// The pixel count of [rect] (physical coordinates).
int _pixelCount(Rect rect) =>
    (rect.bottom.round() - rect.top.round()) *
    (rect.right.round() - rect.left.round());

void main() {
  testWidgets('clue sentences paint bare on candy, sticker and comic: no '
      'retired chip-surface pixels (issue 89)', (tester) async {
    // The retired chip surfaces per skin: candy's own #D8E0EE (issue 87)
    // and the shared sticker/comic gray #F1F3F5 (issue 26).
    final retiredSurfaces = <(SkinTokens, List<int>)>[
      (candyTokens, [0xFFD8E0EE]),
      (stickerTokens, [0xFFF1F3F5]),
      (comicTokens, [0xFFF1F3F5]),
    ];

    for (final (tokens, surfaces) in retiredSurfaces) {
      // 800x900 LOGICAL at dpr 3 (physical 2400x2700): the grown card must
      // fit the window, and logical tester.getRect coordinates map 1:1
      // onto physical pixels at 3x (like
      // game_screen_toolbar_pixel_test.dart).
      tester.view.physicalSize = const Size(2400, 2700);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('panel-capture'),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                SkinScope(tokens: tokens, child: child!),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 640,
                  child: SuspectPanel(
                    caseData: pixelCase,
                    placed: const {},
                    selectedSuspectId: null,
                    onSuspectTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final (bytes, width) = await capturePanel(tester, 'panel-capture');

      final context = tester.element(find.byType(SuspectPanel));
      final l10n = AppLocalizations.of(context)!;
      final names = NameForms.forLocale(l10n.localeName, pixelCase);
      final roomSentence = renderedPlainOf(
        describeClueSegments(pixelCase.clues[0], pixelCase, l10n, names),
      );
      final plainSentence = renderedPlainOf(
        describeClueSegments(pixelCase.clues[1], pixelCase, l10n, names),
      );

      for (final sentenceText in [roomSentence, plainSentence]) {
        final sentenceRect = tester.getRect(find.text(sentenceText));
        final physical = Rect.fromLTRB(
          sentenceRect.left * 3,
          sentenceRect.top * 3,
          sentenceRect.right * 3,
          sentenceRect.bottom * 3,
        );

        // The retired pill surfaces: zero pixels anywhere in the sentence's
        // box — the pill body is gone, not merely re-colored or inset.
        for (final surface in surfaces) {
          final retired = countMatches(bytes, width, physical, surface);
          expect(
            retired,
            0,
            reason:
                '${tokens.skin}: the retired chip surface $surface still '
                'paints $retired pixels inside "$sentenceText"',
          );
        }
        // The card surface paints inside the sentence box (issue 89).
        final cardSurface = countMatches(
          bytes,
          width,
          physical,
          tokens.card.background.toARGB32(),
        );
        expect(
          cardSurface,
          greaterThan(0),
          reason:
              '${tokens.skin}: the card background must paint inside '
              '"$sentenceText", measured $cardSurface pixels',
        );
      }

      // Issue 104: the room chip fills its sentence box with the room's
      // board tint and its label paints the tint-derived ink.
      final roomRect = tester.getRect(find.text(roomSentence));
      final roomPhysical = Rect.fromLTRB(
        roomRect.left * 3,
        roomRect.top * 3,
        roomRect.right * 3,
        roomRect.bottom * 3,
      );
      final tint = clueChipBackground(tokens, 0);
      final tintPixels = countMatches(
        bytes,
        width,
        roomPhysical,
        tint.toARGB32(),
      );
      expect(
        tintPixels,
        greaterThan(0),
        reason:
            '${tokens.skin}: the room chip must paint the room tint '
            '$tint inside "${roomSentence.trim()}", measured $tintPixels',
      );
      final ink = clueChipInk(
        clueChipEffectiveBackground(tokens, 0, tokens.card.background),
      );
      final inkPixels = countMatches(
        bytes,
        width,
        roomPhysical,
        ink.toARGB32(),
      );
      expect(
        inkPixels,
        greaterThan(0),
        reason:
            '${tokens.skin}: the chip label must paint the tint-derived '
            'ink $ink, measured $inkPixels',
      );
    }
  });

  testWidgets('the clue dash paints smaller at 0.75x (issue 104 pixel '
      'proof)', (tester) async {
    tester.view.physicalSize = const Size(80, 80);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<int> inkPixelsOf(double dashScale) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('dash-capture'),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 60,
                  height: 30,
                  child: RichText(
                    text: clueSentenceSpan(
                      const [DashClueSegment('— ')],
                      sentenceStyle: const TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                      ),
                      tokens: stickerTokens,
                      cardSurface: stickerTokens.card.background,
                      dashScale: dashScale,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final (bytes, width) = await capturePanel(tester, 'dash-capture');
      return countNonWhite(bytes, width, const Rect.fromLTWH(0, 0, 80, 80));
    }

    final production = await inkPixelsOf(clueDashFontScale);
    final fullSize = await inkPixelsOf(1.0);
    expect(production, greaterThan(0));
    expect(
      production,
      lessThan(fullSize),
      reason:
          'the production 0.75x dash paints $production ink pixels vs '
          '$fullSize at full size — the shrink must be visible in pixels',
    );
  });

  testWidgets('classic room chip paints the composited legend swatch: '
      'closed-world dominant fill, mid-row scanline, AA ink — idle, '
      'selected, dark, and ru at textScale 2.0 (issue 104 bounce)', (
    tester,
  ) async {
    // 800x900 LOGICAL at dpr 3 (physical 2400x2700): every leg's card fits
    // the window, so logical getRect coordinates map 1:1 onto physical
    // pixels at 3x.
    tester.view.physicalSize = const Size(2400, 2700);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    /// One bounce leg: rasterize the classic panel and pin the chip's
    /// paint on raw pixels.
    Future<void> expectClassicChipPaints({
      ThemeData? theme,
      String? selectedId,
      Locale locale = const Locale('en'),
      double textScale = 1.0,
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('classic-capture'),
          child: MaterialApp(
            theme: theme,
            locale: locale,
            localizationsDelegates: murdokuLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                child: SizedBox(
                  width: 300,
                  child: SuspectPanel(
                    caseData: pixelCase,
                    placed: const {},
                    selectedSuspectId: selectedId,
                    onSuspectTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(SuspectPanel));
      final l10n = AppLocalizations.of(context)!;
      final names = NameForms.forLocale(l10n.localeName, pixelCase);
      // Classic renders s0's two sentences as ONE joined rich paragraph on
      // unselected cards and as one rich Text per sentence on the selected
      // card — try the join first, then the single sentence.
      final plains = [
        for (final clue in pixelCase.clues)
          if (clue.suspectId == 's0')
            renderedPlainOf(describeClueSegments(clue, pixelCase, l10n, names)),
      ];
      final joinedFinder = find.text(plains.join('\n'));
      final sentence = joinedFinder.evaluate().isNotEmpty
          ? joinedFinder
          : find.text(plains.first);
      expect(sentence, findsOneWidget);
      final sentenceRect = tester.getRect(sentence);
      final chipRect = tester.getRect(
        find.descendant(of: sentence, matching: find.byType(Container)),
      );
      // Closed world: the card surface color is read from the tree, not
      // assumed.
      final cardContainer = tester.widget<Container>(
        find.ancestor(of: sentence, matching: find.byType(Container)).first,
      );
      final cardSurface = (cardContainer.decoration! as BoxDecoration).color!;

      final (bytes, width) = await capturePanel(tester, 'classic-capture');

      final bg = clueChipBackground(null, 0);
      expect(
        bg,
        classicRoomTints[0].withValues(alpha: 0.55),
        reason: 'premise: classic fills the legend-swatch alpha',
      );
      final composite = Color.alphaBlend(bg, cardSurface);
      final compositePx = composite.toARGB32();
      final ink = clueChipInk(composite);
      final leg =
          '${theme == null ? "light" : "dark"} '
          '$locale ${selectedId ?? 'idle'} ${textScale}x';

      // Closed world: the test font's solid glyph boxes make the AA ink
      // dominate the interior, so the fill+ink pair must cover ~everything
      // inside the chip — no other surface (retired grays, wrong tints, the
      // bare card) may paint there.
      final interior = physicalOf(chipRect.deflate(1.0));
      final interiorPx = _pixelCount(interior);
      final compositeCount = countMatches(
        bytes,
        width,
        interior,
        compositePx,
        tol: 3,
      );
      final inkCount = countMatches(bytes, width, interior, ink.toARGB32());
      expect(
        compositeCount + inkCount,
        greaterThanOrEqualTo(interiorPx * 0.9),
        reason:
            '$leg: the composited swatch $composite and its AA ink must '
            'cover the chip interior ($compositeCount + $inkCount of '
            '$interiorPx px)',
      );
      expect(
        compositeCount,
        greaterThan(0),
        reason: '$leg: the composite paints inside the chip rect',
      );
      expect(
        inkCount,
        greaterThan(0),
        reason: '$leg: the chip label paints the AA ink $ink',
      );
      // Scanline through the chip's top padding band at 3x (above the
      // label glyphs): the composite spans the padded chip width.
      final scanY = ((chipRect.top + 1) * 3).round();
      final rowStart = (chipRect.left * 3).round();
      final rowEnd = (chipRect.right * 3).round();
      var compositeInRow = 0;
      for (var x = rowStart; x < rowEnd; x++) {
        final i = (scanY * width + x) * 4;
        final rgb = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        if (closeRgb(rgb, compositePx)) compositeInRow++;
      }
      expect(
        compositeInRow,
        greaterThanOrEqualTo((rowEnd - rowStart) * 0.7),
        reason:
            '$leg: the composite must span the chip scanline '
            '($compositeInRow of ${rowEnd - rowStart} px)',
      );
      expect(
        countMatches(bytes, width, physicalOf(sentenceRect), compositePx),
        greaterThan(0),
        reason: '$leg: the composite paints inside the sentence rect',
      );
    }

    await expectClassicChipPaints();
    await expectClassicChipPaints(selectedId: 's0');
    await expectClassicChipPaints(theme: AppTheme.dark);
    await expectClassicChipPaints(locale: const Locale('ru'), textScale: 2.0);
  });
}
