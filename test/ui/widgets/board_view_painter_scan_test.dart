import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/ui/widgets/board_view.dart';

/// Headless painter-pixel scans for the layered wall plate (issue 83).
///
/// KEY TEST (issue 83): render `SkinRoomPainter` through dart:ui
/// `PictureRecorder`/`Canvas` → `toImage` at device-DPR-equivalent scale →
/// `toByteData` raw-pixel scan, asserting a CLOSED WORLD inside the plate
/// region: every pixel is either `mortarColor` or one of the room tints
/// (badge/sprite layers are widget layers above the painter and excluded by
/// layering). `SkinRoomWallPainter` (the #82 cosmetic stroke overpass) is
/// excluded too: it only adds mortar; it cannot create a page-colored gap.
const double _cell = 40.0;

/// Device-pixel scale per skin: every tile inset × scale must be an integer
/// so the scan's rect edges land exactly on pixel boundaries (no AA).
/// Sticker's half-inset 1.75 needs 4; the 4.0-wide tokens need any integer.
double _scaleFor(SkinTokens tokens) => tokens == stickerTokens ? 4.0 : 3.0;

/// Grid-shorthand.
Pos _p(int row, int col) => (row: row, col: col);

/// [layout]'s rooms plus a singleton filler room for every other cell of the
/// G×G board, so the board is fully tiled like the generator produces.
List<RoomDef> _roomsFor(int g, Map<String, List<Pos>> layout) {
  final named = layout.values.expand((cells) => cells).toSet();
  return [
    for (final entry in layout.entries)
      RoomDef(id: entry.key, name: entry.key, cells: entry.value),
    for (var row = 0; row < g; row++)
      for (var col = 0; col < g; col++)
        if (!named.contains(_p(row, col)))
          RoomDef(id: 'f${row}_$col', name: 'filler', cells: [_p(row, col)]),
  ];
}

/// Four singleton rooms around the interior vertex (1,1): the 4-way X
/// junction where the #82 hull fills left a page-colored pocket.
final List<RoomDef> _x4Rooms = _roomsFor(2, {
  'r0': [_p(0, 0)],
  'r1': [_p(0, 1)],
  'r2': [_p(1, 0)],
  'r3': [_p(1, 1)],
});

/// A 3-way T around vertex (1,1): the room 'a' wraps the whole top row, with
/// singleton rooms 'b' and 'c' as the two lower quadrants.
final List<RoomDef> _t3Rooms = _roomsFor(2, {
  'a': [_p(0, 0), _p(0, 1)],
  'b': [_p(1, 0)],
  'c': [_p(1, 1)],
});

/// The issue 83 scan battery: every junction shape the wall bed must close:
/// 4-way X, 3-way T, L crook (concave), straight run, the outer board ring
/// (two L rooms hugging all four board edges), a single-cell room, the
/// donut fallback and the full-plate board (rounded corners).
final Map<String, (int, List<RoomDef>)> _fixtures = {
  'x4': (2, _x4Rooms),
  't3': (2, _t3Rooms),
  'lCrook': (
    3,
    _roomsFor(3, {
      'r0': [_p(0, 0), _p(1, 0), _p(1, 1)],
    }),
  ),
  'straight': (
    4,
    _roomsFor(4, {
      'r0': [_p(1, 0), _p(1, 1), _p(1, 2), _p(1, 3)],
    }),
  ),
  'ring': (
    3,
    _roomsFor(3, {
      'r0': [_p(0, 0), _p(0, 1), _p(0, 2), _p(1, 0), _p(2, 0)],
      'r1': [_p(1, 2), _p(2, 1), _p(2, 2)],
    }),
  ),
  'single': (
    3,
    _roomsFor(3, {
      'r0': [_p(1, 1)],
    }),
  ),
  'donut': (
    5,
    _roomsFor(5, {
      'r0': [
        _p(0, 0), _p(0, 1), _p(0, 2), //
        _p(1, 0), _p(1, 2), //
        _p(2, 0), _p(2, 1), _p(2, 2),
      ],
    }),
  ),
  'plate2x2': (
    2,
    _roomsFor(2, {
      'r0': [_p(0, 0), _p(0, 1), _p(1, 0), _p(1, 1)],
    }),
  ),
};

/// The positional room index for [p] (drives the tint palette index).
int _roomIndexOf(List<RoomDef> rooms, Pos p) =>
    rooms.indexWhere((room) => room.contains(p));

/// The skin's tint of the room at [p], as a raw ARGB32 value.
int _tintAt(SkinTokens tokens, List<RoomDef> rooms, Pos p) => tokens
    .roomTints[_roomIndexOf(rooms, p) % tokens.roomTints.length]
    .toARGB32();

/// A rendered painter raster: raw RGBA bytes, image side in device pixels,
/// the device scale, and the plate's rounded region (device px).
class _Scan {
  const _Scan({
    required this.bytes,
    required this.n,
    required this.s,
    required this.region,
  });

  final Uint8List bytes;
  final int n;
  final double s;
  final ui.RRect region;
}

/// The canary seed for leak scans: a pixel that depends on what the board is
/// painted over is an uncovered gap (the artifact class issue 83 forbids).
const Color _canary = Color(0xFFB400DC);

/// Renders `SkinRoomPainter` headless over an optional [seed] background;
/// [withStrokes] composes the #82 wall stroke overpass after it (the live
/// stack's painters), for the tile↔stroke interaction composite.
Future<_Scan> _render({
  required SkinTokens tokens,
  required int g,
  required List<RoomDef> rooms,
  required Color? seed,
  bool withStrokes = false,
}) async {
  final side = g * _cell;
  final s = _scaleFor(tokens);
  final n = (side * s).round();
  final recorder = ui.PictureRecorder();
  // Cull in DEVICE space: a logical-size cull would clip the picture at
  // logical bounds and swallow every scaled operation beyond it.
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()),
  );
  canvas.scale(s);
  if (seed != null) {
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, side, side), Paint()..color = seed);
  }
  SkinRoomPainter(
    rooms: rooms,
    gridSize: g,
    cellSize: _cell,
    tints: tokens.roomTints,
    mortarColor: tokens.mortarColor,
    lineWidth: tokens.roomLineWidth,
    radius: tokens.roomRadius,
  ).paint(canvas, ui.Size(side, side));
  if (withStrokes) {
    SkinRoomWallPainter(
      rooms: rooms,
      gridSize: g,
      cellSize: _cell,
      mortarColor: tokens.mortarColor,
      lineWidth: tokens.roomLineWidth,
      radius: tokens.roomRadius,
    ).paint(canvas, ui.Size(side, side));
  }
  final image = await recorder.endRecording().toImage(n, n);
  // rawRgba (the default) matches Color's ARGB32 layout byte-wise.
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return _Scan(
    bytes: bytes,
    n: n,
    s: s,
    region: ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(0, 0, side * s, side * s),
      ui.Radius.circular(tokens.roomRadius * s),
    ),
  );
}

/// The RGBA value of device pixel (x, y).
int _pixelAt(_Scan scan, int x, int y) {
  final i = (y * scan.n + x) * 4;
  return scan.bytes[i + 3] << 24 | // A
      scan.bytes[i] << 16 | // R
      scan.bytes[i + 1] << 8 | // G
      scan.bytes[i + 2]; // B
}

/// Pixel (x, y) is scanned when its full 3×3 center-neighborhood (centers x/dy
/// + 0.5) sits inside the plate: a one-device-pixel erosion that excludes the
/// plate's own AA arc halo and the page zone outside the map.
bool _regionAt(_Scan scan, int x, int y) {
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      if (!scan.region.contains(ui.Offset(x + dx + 0.5, y + dy + 0.5))) {
        return false;
      }
    }
  }
  return true;
}

/// Every plate-region pixel must be the same in both rasters: a difference is
/// a gap that lets the background (page vs canary) show through.
void _assertLeakFree(_Scan page, _Scan canary) {
  expect(page.n, canary.n, reason: 'same scale per skin');
  expect(page.region, canary.region);
  for (var y = 0; y < page.n; y++) {
    for (var x = 0; x < page.n; x++) {
      if (!_regionAt(page, x, y)) continue;
      expect(
        _pixelAt(page, x, y),
        _pixelAt(canary, x, y),
        reason:
            'device pixel ($x, $y) depends on what the board was painted '
            'over: a gap leaked the canvas seed through',
      );
    }
  }
}

/// The closed-world scan: inside the plate region every pixel is mortar or
/// one of the room tints. [strict] requires that exactness; blend mode (the
/// legacy fallback only — its Skia AA on the per-cell arcs) additionally
/// accepts 8-bit-rounded α-lerps between two allowed colors. AA blending
/// between allowed colors can never reproduce a foreign ink like the page.
void _assertClosedWorld(_Scan scan, SkinTokens tokens, {required bool strict}) {
  final allowed = <int>[
    tokens.mortarColor.toARGB32(),
    for (final tint in tokens.roomTints) tint.toARGB32(),
  ];
  final exact = allowed.toSet();
  for (var y = 0; y < scan.n; y++) {
    for (var x = 0; x < scan.n; x++) {
      if (!_regionAt(scan, x, y)) continue;
      final v = _pixelAt(scan, x, y);
      if (exact.contains(v)) continue;
      if (strict) {
        fail(
          'device pixel ($x, $y) inside the plate region is '
          '${_hex(v)} — no mortar or room tint',
        );
      }
      if (!_blendAllowed(v, allowed)) {
        fail(
          'device pixel ($x, $y) inside the plate region is '
          '${_hex(v)} — not a mortar/tint blend',
        );
      }
    }
  }
}

/// True when [v] is an α-lerp of some allowed pair, ±1 per 8-bit channel
/// (Skia rounds each channel independently).
bool _blendAllowed(int v, List<int> allowed) {
  final r = (v >> 16) & 0xFF;
  final g = (v >> 8) & 0xFF;
  final b = v & 0xFF;
  for (var i = 0; i < allowed.length; i++) {
    for (var j = i + 1; j < allowed.length; j++) {
      final cr = (allowed[i] >> 16) & 0xFF;
      final cg = (allowed[i] >> 8) & 0xFF;
      final cb = allowed[i] & 0xFF;
      final dr = ((allowed[j] >> 16) & 0xFF) - cr;
      final dg = ((allowed[j] >> 8) & 0xFF) - cg;
      final db = (allowed[j] & 0xFF) - cb;
      // Solve α on the widest channel (least quantization), verify the rest.
      final span = [dr.abs(), dg.abs(), db.abs()].reduce(math.max);
      if (span == 0) continue; // colors with identical widest channel
      var t = 0.0;
      if (dr.abs() == span) {
        t = (r - cr) / dr;
      } else if (dg.abs() == span) {
        t = (g - cg) / dg;
      } else {
        t = (b - cb) / db;
      }
      if (t < -2 / span || t > 1 + 2 / span) continue;
      final lr = cr + t * dr;
      final lg = cg + t * dg;
      final lb = cb + t * db;
      if ((lr - r).abs() <= 1 && (lg - g).abs() <= 1 && (lb - b).abs() <= 1) {
        return true;
      }
    }
  }
  return false;
}

/// The 0xrrggbb form of a raw pixel (alpha masked out) for failure messages.
String _hex(int v) => '0x${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The junction's mortar square is pure mortar: the tiles of all four
/// quadrants are inset half a line from the shared vertex, so the plate shows
/// through an exactly-lineWidth-wide device square.
void _assertJunctionMortar(_Scan scan, Pos vertex, SkinTokens tokens) {
  final cx = (vertex.col * _cell * scan.s).round();
  final cy = (vertex.row * _cell * scan.s).round();
  final half = (tokens.roomLineWidth * scan.s / 2).round();
  final mortar = tokens.mortarColor.toARGB32();
  for (var y = cy - half; y < cy + half; y++) {
    for (var x = cx - half; x < cx + half; x++) {
      expect(
        _pixelAt(scan, x, y),
        mortar,
        reason: 'junction center pixel ($x, $y) is not mortar',
      );
    }
  }
}

/// Asserts the mortar run across the shared boundary centered at device
/// [center] is exactly one wall line wide along [alongX], flanked by the two
/// boundary rooms' tints ([tintA] behind the run, [tintB] ahead of it).
void _assertMortarRun(
  _Scan scan, {
  required bool alongX,
  required Offset center,
  required SkinTokens tokens,
  required int tintA,
  required int tintB,
}) {
  final half = (tokens.roomLineWidth * scan.s / 2).round();
  final mortar = tokens.mortarColor.toARGB32();
  final (sx, sy) = alongX ? (1, 0) : (0, 1);
  final cx = center.dx.round();
  final cy = center.dy.round();
  for (var i = -half; i < half; i++) {
    expect(
      _pixelAt(scan, cx + sx * i, cy + sy * i),
      mortar,
      reason:
          'shared wall pixel $i across the boundary is not mortar '
          '(run must be exactly lineWidth wide)',
    );
  }
  expect(
    _pixelAt(scan, cx - sx * (half + 1), cy - sy * (half + 1)),
    tintA,
    reason: 'tile tint behind the shared wall',
  );
  expect(
    _pixelAt(scan, cx + sx * half, cy + sy * half),
    tintB,
    reason: 'tile tint ahead of the shared wall',
  );
}

/// Asserts the outer wall band: from [origin] (a device pixel on the map
/// edge) marching inward along [step], exactly round(lineWidth·s) pixels are
/// mortar and the next one is the room's [tintBeyond] (the full lineWidth —
/// no opposite tile contributes the other half at the border).
void _assertOuterBand(
  _Scan scan, {
  required (int, int) origin,
  required (int, int) step,
  required SkinTokens tokens,
  required int tintBeyond,
}) {
  final depth = (tokens.roomLineWidth * scan.s).round();
  final mortar = tokens.mortarColor.toARGB32();
  final (ox, oy) = origin;
  final (sx, sy) = step;
  for (var i = 0; i < depth; i++) {
    expect(
      _pixelAt(scan, ox + sx * i, oy + sy * i),
      mortar,
      reason: 'outer wall band pixel $i from the map edge is not mortar',
    );
  }
  expect(
    _pixelAt(scan, ox + sx * depth, oy + sy * depth),
    tintBeyond,
    reason: 'tile tint begins exactly one lineWidth inside the map edge',
  );
}

void main() {
  /// The three cartoon skins' token pairs from SkinsTokens (classic has
  /// solidRooms: false and never uses the painter).
  const allSkins = [stickerTokens, comicTokens, candyTokens];

  testWidgets('closed-world scan: 4-way X junction leaks nothing '
      '(sticker, comic, candy) (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final page = await _render(
          tokens: tokens,
          g: 2,
          rooms: _x4Rooms,
          seed: tokens.pageColor,
        );
        final canary = await _render(
          tokens: tokens,
          g: 2,
          rooms: _x4Rooms,
          seed: _canary,
        );
        _assertLeakFree(page, canary);
      }
    });
  });

  testWidgets('closed-world scan: X and T interiors are exactly mortar or '
      'the rooms\' tints (all skins) (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        for (final (g, rooms) in [(2, _x4Rooms), (2, _t3Rooms)]) {
          final scan = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: null,
          );
          _assertClosedWorld(scan, tokens, strict: true);
        }
      }
    });
  });

  testWidgets('scan: shared walls render exactly lineWidth wide '
      '(all skins) (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final scan = await _render(
          tokens: tokens,
          g: 2,
          rooms: _x4Rooms,
          seed: null,
        );
        // Vertical boundary col 1: r0 | r1 at row 0's mid-tile.
        _assertMortarRun(
          scan,
          alongX: true,
          center: Offset(1 * _cell * scan.s, 0.5 * _cell * scan.s),
          tokens: tokens,
          tintA: _tintAt(tokens, _x4Rooms, _p(0, 0)),
          tintB: _tintAt(tokens, _x4Rooms, _p(0, 1)),
        );
        // Horizontal boundary row 1: r0 above r2 at col 0's mid-tile.
        _assertMortarRun(
          scan,
          alongX: false,
          center: Offset(0.5 * _cell * scan.s, 1 * _cell * scan.s),
          tokens: tokens,
          tintA: _tintAt(tokens, _x4Rooms, _p(0, 0)),
          tintB: _tintAt(tokens, _x4Rooms, _p(1, 0)),
        );
        // T fixture: vertical boundary col 1 in the bottom row: b | c.
        final t3 = await _render(
          tokens: tokens,
          g: 2,
          rooms: _t3Rooms,
          seed: null,
        );
        _assertMortarRun(
          t3,
          alongX: true,
          center: Offset(1 * _cell * t3.s, 1.5 * _cell * t3.s),
          tokens: tokens,
          tintA: _tintAt(tokens, _t3Rooms, _p(1, 0)),
          tintB: _tintAt(tokens, _t3Rooms, _p(1, 1)),
        );
      }
    });
  });

  testWidgets('scan: outer board edges render the full lineWidth band '
      '(all skins) (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final scan = await _render(
          tokens: tokens,
          g: 2,
          rooms: _x4Rooms,
          seed: null,
        );
        final n = scan.n;
        final midTop = _tintAt(tokens, _x4Rooms, _p(0, 0));
        final midBottom = _tintAt(tokens, _x4Rooms, _p(1, 0));
        final midRight = _tintAt(tokens, _x4Rooms, _p(0, 1));
        _assertOuterBand(
          scan,
          origin: (n ~/ 4, 0),
          step: (0, 1),
          tokens: tokens,
          tintBeyond: midTop,
        );
        _assertOuterBand(
          scan,
          origin: (n ~/ 4, n - 1),
          step: (0, -1),
          tokens: tokens,
          tintBeyond: midBottom,
        );
        _assertOuterBand(
          scan,
          origin: (0, n ~/ 4),
          step: (1, 0),
          tokens: tokens,
          tintBeyond: midTop,
        );
        _assertOuterBand(
          scan,
          origin: (n - 1, n ~/ 4),
          step: (-1, 0),
          tokens: tokens,
          tintBeyond: midRight,
        );
      }
    });
  });

  testWidgets('scan: junction centers are pure mortar (all skins) (issue 83)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        for (final (g, rooms) in [(2, _x4Rooms), (2, _t3Rooms)]) {
          final scan = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: null,
          );
          _assertJunctionMortar(scan, _p(1, 1), tokens);
        }
      }
    });
  });

  testWidgets('scan battery: every fixture × every cartoon skin leaks '
      'nothing (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        for (final entry in _fixtures.entries) {
          final (g, rooms) = entry.value;
          final page = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: tokens.pageColor,
          );
          final canary = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: _canary,
          );
          _assertLeakFree(page, canary);
        }
      }
    });
  });

  testWidgets('scan battery: interiors are exactly mortar or room tints; '
      'the donut fallback admits strict-color blends only (issue 83)', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        for (final entry in _fixtures.entries) {
          final (g, rooms) = entry.value;
          final scan = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: null,
          );
          // The donut renders through the legacy per-cell fallback whose
          // anti-aliased arcs blend allowed colors (tint↔mortar↔tint); the
          // blend classifier accepts exactly those 8-bit lerp pairs, never
          // the page. Traced fixtures stay strictly exact.
          _assertClosedWorld(scan, tokens, strict: entry.key != 'donut');
        }
      }
    });
  });

  testWidgets('scan battery: shared and outer wall widths hold across '
      'fixtures and skins (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final crook = await _render(
          tokens: tokens,
          g: 3,
          rooms: _fixtures['lCrook']!.$2,
          seed: null,
        );
        // Vertical boundary col 2 at row 1: r0 | its east filler room.
        _assertMortarRun(
          crook,
          alongX: true,
          center: Offset(2 * _cell * crook.s, 1.5 * _cell * crook.s),
          tokens: tokens,
          tintA: _tintAt(tokens, _fixtures['lCrook']!.$2, _p(1, 1)),
          tintB: _tintAt(tokens, _fixtures['lCrook']!.$2, _p(1, 2)),
        );

        final straight = await _render(
          tokens: tokens,
          g: 4,
          rooms: _fixtures['straight']!.$2,
          seed: null,
        );
        // The same-room edge inside the run (col 1, row 1) tints through
        // with zero inset: no wall, no fringe — just the room's color.
        final runTint = _tintAt(tokens, _fixtures['straight']!.$2, _p(1, 1));
        final edgeX = (1 * _cell * straight.s).round();
        for (var dx = -2; dx <= 2; dx++) {
          expect(
            _pixelAt(straight, edgeX + dx, (1.5 * _cell * straight.s).round()),
            runTint,
            reason: 'same-room tiles abut exactly: no seam at the shared edge',
          );
        }
        // Shared boundary above the run (row 1 at col 1): filler | r0.
        _assertMortarRun(
          straight,
          alongX: false,
          center: Offset(1.5 * _cell * straight.s, 1 * _cell * straight.s),
          tokens: tokens,
          tintA: _tintAt(tokens, _fixtures['straight']!.$2, _p(0, 1)),
          tintB: _tintAt(tokens, _fixtures['straight']!.$2, _p(1, 1)),
        );

        final ring = await _render(
          tokens: tokens,
          g: 3,
          rooms: _fixtures['ring']!.$2,
          seed: null,
        );
        final n = ring.n;
        final ringRooms = _fixtures['ring']!.$2;
        _assertOuterBand(
          ring,
          origin: (n ~/ 2 + 2, 0),
          step: (0, 1),
          tokens: tokens,
          tintBeyond: _tintAt(tokens, ringRooms, _p(0, 1)),
        );
        _assertOuterBand(
          ring,
          origin: (n ~/ 2 + 2, n - 1),
          step: (0, -1),
          tokens: tokens,
          tintBeyond: _tintAt(tokens, ringRooms, _p(2, 1)),
        );
        _assertOuterBand(
          ring,
          origin: (0, n ~/ 2 + 2),
          step: (1, 0),
          tokens: tokens,
          tintBeyond: _tintAt(tokens, ringRooms, _p(1, 0)),
        );
        _assertOuterBand(
          ring,
          origin: (n - 1, n ~/ 2 + 2),
          step: (-1, 0),
          tokens: tokens,
          tintBeyond: _tintAt(tokens, ringRooms, _p(1, 2)),
        );
        // The r1 room's shared boundary with the singleton at (1,1):
        // vertical col 2 at row 1: filler | r1.
        _assertMortarRun(
          ring,
          alongX: true,
          center: Offset(2 * _cell * ring.s, 1.5 * _cell * ring.s),
          tokens: tokens,
          tintA: _tintAt(tokens, ringRooms, _p(1, 1)),
          tintB: _tintAt(tokens, ringRooms, _p(1, 2)),
        );

        final single = await _render(
          tokens: tokens,
          g: 3,
          rooms: _fixtures['single']!.$2,
          seed: null,
        );
        // Both shared sides of the single-cell room: behind | ahead.
        final roomsSingle = _fixtures['single']!.$2;
        _assertMortarRun(
          single,
          alongX: true,
          center: Offset(1 * _cell * single.s, 1.5 * _cell * single.s),
          tokens: tokens,
          tintA: _tintAt(tokens, roomsSingle, _p(1, 0)),
          tintB: _tintAt(tokens, roomsSingle, _p(1, 1)),
        );
        _assertMortarRun(
          single,
          alongX: true,
          center: Offset(2 * _cell * single.s, 1.5 * _cell * single.s),
          tokens: tokens,
          tintA: _tintAt(tokens, roomsSingle, _p(1, 1)),
          tintB: _tintAt(tokens, roomsSingle, _p(1, 2)),
        );
        _assertMortarRun(
          single,
          alongX: false,
          center: Offset(1.5 * _cell * single.s, 2 * _cell * single.s),
          tokens: tokens,
          tintA: _tintAt(tokens, roomsSingle, _p(1, 1)),
          tintB: _tintAt(tokens, roomsSingle, _p(2, 1)),
        );

        final plate = await _render(
          tokens: tokens,
          g: 2,
          rooms: _fixtures['plate2x2']!.$2,
          seed: null,
        );
        // One room covering the whole board: the full plate bands, and the
        // interior is one seamless tint (no same-room seams anywhere).
        _assertOuterBand(
          plate,
          origin: (n ~/ 2, 0),
          step: (0, 1),
          tokens: tokens,
          tintBeyond: _tintAt(tokens, _fixtures['plate2x2']!.$2, _p(0, 1)),
        );
        expect(
          _pixelAt(plate, plate.n ~/ 2, plate.n ~/ 2),
          _tintAt(tokens, _fixtures['plate2x2']!.$2, _p(0, 0)),
          reason: 'the full-plate board interior is its room tint, seamless',
        );
      }
    });
  });

  testWidgets('scan: T-junction pockets are mortar, never the page '
      '(issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final page = await _render(
          tokens: tokens,
          g: 2,
          rooms: _t3Rooms,
          seed: tokens.pageColor,
        );
        final canary = await _render(
          tokens: tokens,
          g: 2,
          rooms: _t3Rooms,
          seed: _canary,
        );
        _assertLeakFree(page, canary);
        _assertJunctionMortar(page, _p(1, 1), tokens);
      }
    });
  });

  testWidgets('scan: the outer border band is one solid mortar line, no dot '
      'band (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final (g, rooms) = _fixtures['ring']!;
        final ring = await _render(
          tokens: tokens,
          g: g,
          rooms: rooms,
          seed: null,
        );
        final n = ring.n;
        // March the whole border ring, skipping the rounded corner notches
        // (outside the plate by design): every pixel of the four outer
        // bands is exactly mortar; no page dot inside the border band.
        final notch = (tokens.roomRadius * ring.s).ceil();
        for (var i = notch; i < n - notch; i++) {
          for (final (x, y) in [(i, 0), (i, n - 1), (0, i), (n - 1, i)]) {
            expect(
              _pixelAt(ring, x, y),
              tokens.mortarColor.toARGB32(),
              reason: 'outer border pixel ($x, $y) is not mortar',
            );
          }
          for (final (x, y) in [
            (i, n ~/ 3),
            (i, 2 * n ~/ 3),
            (n ~/ 3, i),
            (2 * n ~/ 3, i),
          ]) {
            expect(
              _pixelAt(ring, x, y),
              isNot(tokens.pageColor.toARGB32()),
              reason:
                  'no page-colored dot may sit inside the border band '
                  'at ($x, $y)',
            );
          }
        }
        expect(
          _pixelAt(ring, n ~/ 4, n ~/ 4),
          _tintAt(tokens, rooms, _p(0, 0)),
          reason: 'the tile tint begins inside the border band',
        );
      }
    });
  });

  testWidgets('scan: plate corners stay covered on the full-plate board '
      '(issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        final (g, rooms) = _fixtures['plate2x2']!;
        final page = await _render(
          tokens: tokens,
          g: g,
          rooms: rooms,
          seed: tokens.pageColor,
        );
        final canary = await _render(
          tokens: tokens,
          g: g,
          rooms: rooms,
          seed: _canary,
        );
        // No page (and no canary) shows through anywhere in the plate
        // region, rounded corners included: one device pixel past the
        // plate's arc the plate is already mortar.
        _assertLeakFree(page, canary);
        _assertClosedWorld(page, tokens, strict: true);
        // The corner band: along the 45° diagonal the plate's arc sits at
        // ~(1 − 1/√2)·r device px from the corner; any pixel between that
        // arc and the tile's corner (device width·s) is exact plate mortar.
        // (Candy's 14/4 pair leaves no sliver — its tile corner reaches past
        // the arc, which is the pairing the issue verified, unaltered.)
        final arcCoord = (1 - math.sqrt(2) / 2) * tokens.roomRadius * page.s;
        final tileEdge = (tokens.roomLineWidth * page.s).round();
        for (var k = arcCoord.ceil(); k < tileEdge; k++) {
          expect(
            _pixelAt(page, k, k),
            tokens.mortarColor.toARGB32(),
            reason:
                'plate corner sliver pixel ($k, $k) along the diagonal '
                'is not mortar',
          );
        }
        expect(
          _pixelAt(page, tileEdge, tileEdge),
          _tintAt(tokens, rooms, _p(0, 0)),
          reason:
              'the room tint begins exactly one lineWidth inside the '
              'map corner',
        );
      }
    });
  });

  testWidgets('scan: candy token pairing survives the layered repaint '
      '(issue 83)', (tester) async {
    await tester.runAsync(() async {
      // Candy keeps its design (radius 14, width 4): verify it, don't alter
      // it — leak-free junctions, border and corners with candy's tokens.
      expect(candyTokens.roomRadius, 14.0);
      expect(candyTokens.roomLineWidth, 4.0);
      expect(candyTokens.mortarColor, const Color(0xFFFFFFFF));
      for (final (g, rooms) in [_fixtures['t3']!, _fixtures['plate2x2']!]) {
        final page = await _render(
          tokens: candyTokens,
          g: g,
          rooms: rooms,
          seed: candyTokens.pageColor,
        );
        final canary = await _render(
          tokens: candyTokens,
          g: g,
          rooms: rooms,
          seed: _canary,
        );
        _assertLeakFree(page, canary);
        _assertClosedWorld(page, candyTokens, strict: true);
      }
      final x4 = await _render(
        tokens: candyTokens,
        g: 2,
        rooms: _x4Rooms,
        seed: null,
      );
      _assertJunctionMortar(x4, _p(1, 1), candyTokens);
    });
  });

  testWidgets('scan composite: plate + tiles + wall strokes together leak '
      'nothing across fixtures and skins (issue 83)', (tester) async {
    await tester.runAsync(() async {
      for (final tokens in allSkins) {
        for (final entry in _fixtures.entries) {
          final (g, rooms) = entry.value;
          final page = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: tokens.pageColor,
            withStrokes: true,
          );
          final canary = await _render(
            tokens: tokens,
            g: g,
            rooms: rooms,
            seed: _canary,
            withStrokes: true,
          );
          _assertLeakFree(page, canary);
        }
      }
    });
  });
}
