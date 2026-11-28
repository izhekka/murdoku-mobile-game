// Heavy raster battery (issue 105): skipped by intermediate runs
// (`flutter test --exclude-tags=raster`); the final `make quality` gate
// still executes it.
@Tags(['raster'])
library;

import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

/// Issue 103 render-path proof: the landscape panel rearrangement is a
/// painting change (the header band must give way to the grid's first card
/// border, the 2-column gutter must sit at the 2-column position, and a
/// second content-height row must paint inside the 277px slot), so this test
/// rasterizes the header-less panel headless at the issue's reference
/// geometry — 575×277, the sticker skin — and asserts on the raw pixels.
/// Prose and widget-rect claims cannot make these three specific claims.
Pos p(int row, int col) => (row: row, col: col);

/// The 5x5 fixture board with one clue per suspect (same shape as the panel
/// test's fixture; self-contained here so the raster geometry stays local to
/// this file).
final CaseData pixelCase = CaseData(
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
  suspects: const [
    Suspect(id: 's0', name: 'Ash'),
    Suspect(id: 's1', name: 'Blair'),
    Suspect(id: 's2', name: 'Casey'),
    Suspect(id: 's3', name: 'Drew'),
    Suspect(id: 's4', name: 'Ellis'),
  ],
  victimPos: p(2, 2),
  murdererId: 's2',
  clues: const [
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
  ],
  solution: {
    's0': p(0, 0),
    's1': p(1, 4),
    's2': p(2, 1),
    's3': p(3, 3),
    's4': p(4, 2),
  },
);

/// Pixels along the horizontal run [x0]..[x1] at scanline [y] whose RGB
/// matches [target] within [tol] per channel.
int countRunMatches(
  Uint8List bytes,
  int width,
  int y,
  int x0,
  int x1,
  int target, {
  int tol = 0,
}) {
  final tr = (target >> 16) & 0xFF;
  final tg = (target >> 8) & 0xFF;
  final tb = target & 0xFF;
  var count = 0;
  for (var x = x0; x < x1; x++) {
    final i = (y * width + x) * 4;
    if ((bytes[i] - tr).abs() <= tol &&
        (bytes[i + 1] - tg).abs() <= tol &&
        (bytes[i + 2] - tb).abs() <= tol) {
      count++;
    }
  }
  return count;
}

/// The single pixel at ([x], [y]) as a packed RGB int (no alpha byte).
int pixelAt(Uint8List bytes, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
}

void main() {
  testWidgets('landscape panel raster: header band gone, 2-column gutter, '
      'content-height rows (issue 103)', (tester) async {
    // dpr 1.0 rasterizes 1:1, so raw-pixel coordinates equal the logical
    // panel coordinates (575×277 — the issue's reference host).
    tester.view.physicalSize = const Size(575, 277);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('landscape-capture'),
        child: MaterialApp(
          // The app's real theme: the Scaffold page must be the sticker
          // cream (the gutter assertion samples the page backdrop).
          theme: AppTheme.forSkin(SkinSetting.sticker, Brightness.light),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              SkinScope(tokens: stickerTokens, child: child!),
          home: Scaffold(
            body: SuspectPanel(
              caseData: pixelCase,
              placed: {},
              selectedSuspectId: null,
              onSuspectTap: _noopTap,
              showHeader: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // toImage submits to the real IO task queue, which the fake-async test
    // zone forbids: run the capture in runAsync (same pattern as the chip
    // pixel test).
    Uint8List bytes = Uint8List(0);
    var width = 0;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('landscape-capture')),
      );
      final image = await boundary.toImage();
      width = image.width;
      bytes = Uint8List.fromList(
        (await image.toByteData())!.buffer.asUint8List(),
      );
      image.dispose();
    });

    // RGB constants (no alpha byte — pixelAt packs RGB only).
    const navy = 0x1D3557; // sticker card border + shadow ink
    const cream = 0xFFF8EF; // sticker app page (the grid's backdrop)

    // 1. No header band: the grid's FIRST row card top border (sticker
    //    border 3px on the container y∈[8,11]) paints a solid navy run
    //    across the card at scanline y=9 — a ~230px contiguous run the
    //    header's text glyphs could never produce. (Header padding starts
    //    the grid at y≈40+ under the pre-issue header-bearing layout.)
    final row1Border = countRunMatches(bytes, width, 9, 30, 260, navy);
    expect(
      row1Border,
      greaterThan(200),
      reason:
          'the first card border paints at y=9 ($row1Border/230 navy '
          'pixels): the grid starts at the panel top — no header band',
    );

    // 2. Two columns: the gutter between column 1 (container right edge
    //    281.5, its +6px shadow ends at x≈287.5) and column 2 (container
    //    starts 293.5) shows the cream page at (290, 50). The old 3-column
    //    grid's second card covered this exact pixel with its white surface.
    expect(
      pixelAt(bytes, width, 290, 50),
      cream,
      reason:
          'the pixel between the two columns is the page backdrop, '
          'not a third column card surface',
    );

    // 3. Content-height rows: with the header gone the slot fits 2 of the
    //    3 grown rows (~92px tall tiles — the retired cardWidth/1.05 floor
    //    would stretch them to ~268px), so the SECOND row's top border
    //    paints at scanline y=103 (row-2 card container y∈[102,184] inside
    //    the 277px slot); under the retired floor the second row starts
    //    below the fold and this scanline is row-1 card interior.
    final row2Border = countRunMatches(bytes, width, 103, 30, 260, navy);
    expect(
      row2Border,
      greaterThan(200),
      reason:
          'the second row\'s border paints at y=103 ($row2Border/230 '
          'navy pixels): rows are content-height, not 1.05-ratio stretched',
    );
  });
}

void _noopTap(String id) {}
