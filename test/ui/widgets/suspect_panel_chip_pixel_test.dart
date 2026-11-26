import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

/// Issue 89 render-path proof: removing the clue pill is a painting change
/// (the sentences' rasterized pixels must show the bare card surface where
/// the retired gray pill used to paint), so this test rasterizes the suspect
/// panel headless on both skins whose chips carried a distinct surface —
/// candy #D8E0EE (issue 87) and sticker #F1F3F5 (issue 26) — and asserts on
/// the raw pixels inside a clue sentence's box: zero pixels of the retired
/// chip surfaces, real card-background pixels where the pill body used to
/// sit.
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
  clues: const [InRoom(suspectId: 's0', roomId: 'r0', negated: false)],
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
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The capture boundary wraps the whole window root, so logical
      // tester.getRect coordinates map 1:1 onto physical pixels at 3x
      // (like game_screen_toolbar_pixel_test.dart).
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

      final sentence = tester.getRect(find.text('— in the Kitchen.'));

      // toImage submits to the real IO task queue, which the fake-async test
      // zone forbids: run the capture in runAsync (like the golden matchers'
      // captureImage does — same pattern as the toolbar pixel test).
      Uint8List bytes = Uint8List(0);
      var width = 0;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('panel-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 3.0);
        width = image.width;
        bytes = Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List(),
        );
        image.dispose();
      });

      final physical = Rect.fromLTRB(
        sentence.left * 3,
        sentence.top * 3,
        sentence.right * 3,
        sentence.bottom * 3,
      );

      // The retired pill surface: zero pixels anywhere in the sentence's
      // box — the pill body is gone, not merely re-colored or inset.
      for (final surface in surfaces) {
        final retired = countMatches(bytes, width, physical, surface);
        expect(
          retired,
          0,
          reason:
              '${tokens.skin}: the retired chip surface $surface still '
              'paints $retired pixels inside the clue sentence box',
        );
      }
      // The card surface shows through where the pill body used to sit:
      // the sentence renders directly on the card background.
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
            '${tokens.skin}: the card background must paint inside the '
            'clue sentence box once the pill is gone, measured '
            '$cardSurface pixels',
      );
    }
  });
}
