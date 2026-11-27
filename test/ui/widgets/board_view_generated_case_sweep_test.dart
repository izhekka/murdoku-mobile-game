import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/ui/widgets/board_view.dart';

/// The generated-case thorn sweep (issue 101 AC: the permanent cure).
///
/// The owner's serrated wrapper corner returned on a generated board after
/// issue 94 because the scan batteries enumerate junction shapes by hand and
/// the color-set closed-world scans are shape-blind to mortar wedges. This
/// suite renders generated boards through the REAL painters
/// (`SkinRoomPainter` tiles + `SkinRoomWallPainter` strokes) at
/// device-DPR-equivalent scale and scans the raw pixels for the thorn
/// signature: mortar protruding into a room beyond the wall's lineWidth
/// footprint along any band edge or seam.
///
/// Signature definition (tight): a solid mortar pixel strictly inside a
/// cell's tile rect (beyond the per-side inset + a small AA margin) is a
/// thorn, UNLESS it is the stroke's own rounded inner-corner band at a
/// convex outline corner — allowed only when the pixel's own room occupies
/// exactly one quadrant at the nearest lattice vertex (that is exactly what
/// makes the outline corner convex there) AND the pixel lies within the
/// band slack of that corner's quadratic — the stroke's exact centerline
/// arc (from `V + (k·dqCol, 0)` control `V` to `V + (0, k·dqRow)`; every
/// band pixel is within h of it). This shape-aware analytic bound replaced
/// the bounce-round [P2]'s shape-blind Chebyshev-k disc, which admitted any
/// mortar blob near a one-quadrant vertex regardless of shape (the #94
/// kink recurrence class); the distance test is exact to the band —
/// sampled points lie on the curve so the estimate never underestimates,
/// and 64 samples keep the overestimate ≈ 0.1 px, inside the slack.
///
/// The pinned fixture is the stage-1 sweep's worst arrangement (hard seed 1,
/// g 7): the wrapper room r3 wraps the lattice vertex (4, 5) around the odd
/// room r5's cell (3, 5); the wrapper corner tile (4, 4)'s NE corner was the
/// reproduction of the owner's crop. The probes pin the exact-A emission
/// there (pocket absorbed, tile hugging the band edges tangentially along
/// the analytic arc) and the scan pins the wedge's absence on every
/// generated case.
///
/// Seed determinism: the pinned fixture and the sweep's room arrangements
/// are a PRNG snapshot of the current Dart SDK's `Random` stream — re-pin
/// the seeds (and this file's geometry assumptions) after a Dart SDK
/// upgrade if the generated boards drift.
const double _cell = 40.0;

/// Device scale per skin (matches the painter-scan battery): every tile
/// inset × scale is an integer so rect edges land on pixel boundaries.
double _scaleFor(SkinTokens tokens) => tokens == stickerTokens ? 4.0 : 3.0;

final List<SkinTokens> _skins = [stickerTokens, comicTokens, candyTokens];

/// The pinned stage-1 fixture's arrangement.
const Difficulty _fixtureDifficulty = Difficulty.hard;
const int _fixtureSeed = 1;
const Pos _fixtureVertex = (row: 4, col: 5);

/// PRNG snapshot of the current Dart SDK's stream; re-pin after Dart
/// upgrades (see the file doc).
const int _seedsPerDifficulty = 25; // × 3 difficulties (issue 101 AC ≥ 25)

/// One headless painter raster: raw RGBA bytes, device side, device scale.
class _Raster {
  const _Raster({required this.bytes, required this.n, required this.s});

  final Uint8List bytes;
  final int n;
  final double s;
}

/// Renders [rooms] through the REAL painters at device scale. With
/// [withStrokes] the #82 wall stroke overpass composes after the tiles (the
/// live stack).
Future<_Raster> _renderBoard({
  required List<RoomDef> rooms,
  required int g,
  required SkinTokens tokens,
  bool withStrokes = true,
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
  final picture = recorder.endRecording();
  final image = await picture.toImage(n, n);
  picture.dispose();
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  return _Raster(bytes: bytes, n: n, s: s);
}

int _pixelAt(_Raster raster, int x, int y) {
  final i = (y * raster.n + x) * 4;
  return Color.fromARGB(
    raster.bytes[i + 3],
    raster.bytes[i],
    raster.bytes[i + 1],
    raster.bytes[i + 2],
  ).toARGB32();
}

/// The inset pair a corner (dRow, dCol) reads: (left, top) for NW, (top,
/// right) for NE, (right, bottom) for SE, (bottom, left) for SW — the same
/// pairs `SkinRoomPainter._tileCornerRounding` feeds the predicate.
(double, double) _cornerInsets(
  (double, double, double, double) insets,
  int dRow,
  int dCol,
) => switch ((dRow, dCol)) {
  (-1, -1) => (insets.$1, insets.$2),
  (-1, 1) => (insets.$2, insets.$3),
  (1, 1) => (insets.$3, insets.$4),
  _ => (insets.$4, insets.$1),
};

/// The wrapper corner of the [vertex] — the cell owning it and the diagonal
/// (dRow, dCol) it faces — or null when the junction has none.
(Pos, int, int)? _roundingCornerAt(List<RoomDef> rooms, int g, Pos vertex) {
  for (final room in rooms) {
    for (final cell in room.cells) {
      for (final (dr, dc) in const [(-1, -1), (-1, 1), (1, 1), (1, -1)]) {
        final cornerCol = dc > 0 ? cell.col + 1 : cell.col;
        final cornerRow = dr > 0 ? cell.row + 1 : cell.row;
        if (cornerCol != vertex.col || cornerRow != vertex.row) continue;
        final insets = roomTileInsets(rooms, g, cell.row, cell.col, 4.0);
        final (a, b) = _cornerInsets(insets, dr, dc);
        if (roomTileCornerRounds(rooms, g, cell.row, cell.col, dr, dc, a, b)) {
          return (cell, dr, dc);
        }
      }
    }
  }
  return null;
}

/// The band slack around the stroke's centerline: covers the rasterized
/// edge's AA fringe and the 64-sample distance overestimate (≈ 0.1 px).
const double _bandSlack = 0.5;

/// The point of the quadratic [p0] → [c] → [p1] at parameter [t].
ui.Offset _quadAt(ui.Offset p0, ui.Offset c, ui.Offset p1, double t) {
  final u = 1 - t;
  return ui.Offset(
    u * u * p0.dx + 2 * t * u * c.dx + t * t * p1.dx,
    u * u * p0.dy + 2 * t * u * c.dy + t * t * p1.dy,
  );
}

/// The min distance from (x, y) to the quadratic arc [p0] → [c] → [p1], by
/// sampling (samples lie ON the curve, so the estimate never
/// underestimates; 64 samples keep the overestimate ≈ 0.1 px).
double _distToQuadArc(
  double x,
  double y,
  ui.Offset p0,
  ui.Offset c,
  ui.Offset p1,
) {
  var best = double.infinity;
  const n = 64;
  for (var i = 0; i <= n; i++) {
    final point = _quadAt(p0, c, p1, i / n);
    final dx = x - point.dx;
    final dy = y - point.dy;
    final d2 = dx * dx + dy * dy;
    if (d2 < best) best = d2;
  }
  return math.sqrt(best);
}

/// The 0-255 RGBA channel triple of [c].
(int, int, int) _channels(Color c) =>
    ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

/// One flagged junction: the room the wedge protrudes into, the nearest
/// lattice vertex, the thorn pixel count and the deepest sampled reach.
class _JunctionThorn {
  const _JunctionThorn({
    required this.room,
    required this.vertex,
    required this.pixels,
    required this.maxCheb,
  });

  final String room;
  final Pos vertex;
  final int pixels;
  final double maxCheb;
}

/// Scans a full-board raster for the thorn signature (see the file doc for
/// the tightened analytic allowance).
List<_JunctionThorn> _scanThorns(
  _Raster raster, {
  required List<RoomDef> rooms,
  required int g,
  required SkinTokens tokens,
}) {
  const tol = 20;
  const margin = 0.35;
  final s = raster.s;
  final lw = tokens.roomLineWidth;
  final h = lw / 2;
  final k = math.min(tokens.roomRadius, _cell / 2);
  final (mr, mg, mb) = _channels(tokens.mortarColor);
  final thorns = <String, _JunctionThorn>{};
  for (var py = 0; py < raster.n; py++) {
    final y = (py + 0.5) / s;
    for (var px = 0; px < raster.n; px++) {
      final i = (py * raster.n + px) * 4;
      final (r8, g8, b8) = (
        raster.bytes[i],
        raster.bytes[i + 1],
        raster.bytes[i + 2],
      );
      // Only solid mortar matters; AA blends fall outside tol.
      if ((r8 - mr).abs() > tol ||
          (g8 - mg).abs() > tol ||
          (b8 - mb).abs() > tol) {
        continue;
      }
      final x = (px + 0.5) / s;
      final row = (y / _cell).floor();
      final col = (x / _cell).floor();
      if (row < 0 || col < 0 || row >= g || col >= g) continue;
      final insets = roomTileInsets(rooms, g, row, col, lw);
      final left = col * _cell + insets.$1;
      final top = row * _cell + insets.$2;
      final right = (col + 1) * _cell - insets.$3;
      final bottom = (row + 1) * _cell - insets.$4;
      if (x < left + margin ||
          x > right - margin ||
          y < top + margin ||
          y > bottom - margin) {
        continue; // wall band footprint / AA fringe
      }
      final vx = (x - col * _cell < (col + 1) * _cell - x)
          ? col * _cell
          : (col + 1) * _cell;
      final vy = (y - row * _cell < (row + 1) * _cell - y)
          ? row * _cell
          : (row + 1) * _cell;
      final vr = (vy / _cell).round();
      final vc = (vx / _cell).round();
      final roomQ = roomOf(rooms, (row: row, col: col)) ?? '';
      var same = 0;
      for (final (qr, qc) in const [(-1, -1), (-1, 0), (0, -1), (0, 0)]) {
        final r2 = vr + qr;
        final c2 = vc + qc;
        if (r2 < 0 || c2 < 0 || r2 >= g || c2 >= g) continue;
        if (roomOf(rooms, (row: r2, col: c2)) == roomQ) same++;
      }
      final cheb = math.max((x - vx).abs(), (y - vy).abs());
      if (same == 1) {
        // Strict analytic allowance (bounce [P2, source: visual]): only the
        // stroke's own inner-corner band may cut in — pixels within the
        // band slack of the corner's centerline quadratic (the exact arc,
        // not a shape-blind distance disc).
        final dRowQ = vy == row * _cell ? 1 : -1;
        final dColQ = vx == col * _cell ? 1 : -1;
        final p0 = Offset(vx + k * dColQ, vy);
        final p1 = Offset(vx, vy + k * dRowQ);
        if (_distToQuadArc(x, y, p0, Offset(vx, vy), p1) <= h + _bandSlack) {
          continue;
        }
      }
      final key = '$roomQ@$vr,$vc';
      final hit = thorns[key];
      thorns[key] = hit == null
          ? _JunctionThorn(
              room: roomQ,
              vertex: (row: vr, col: vc),
              pixels: 1,
              maxCheb: cheb,
            )
          : _JunctionThorn(
              room: roomQ,
              vertex: hit.vertex,
              pixels: hit.pixels + 1,
              maxCheb: math.max(hit.maxCheb, cheb),
            );
    }
  }
  return thorns.values.toList();
}

/// Fails with the flagged junctions, for fast diagnosis.
void _expectNoThorns(List<_JunctionThorn> thorns, String what) {
  final detail = thorns
      .map(
        (t) =>
            '${t.room}@(${t.vertex.row},${t.vertex.col}): ${t.pixels}px '
            '(max reach ${t.maxCheb.toStringAsFixed(1)})',
      )
      .join(', ');
  expect(thorns, isEmpty, reason: '$what — thorn signature present: $detail');
}

void main() {
  test('generated-case sweep: the strict arc-distance allowance admits the '
      'stroke band itself on every skin and corner orientation (issue 101 '
      'bounce [P2])', () {
    for (final tokens in _skins) {
      final h = tokens.roomLineWidth / 2;
      final k = math.min(tokens.roomRadius, _cell / 2);
      for (final (dRow, dCol) in const [(-1, -1), (-1, 1), (1, 1), (1, -1)]) {
        // An interior vertex; the owning quadrant carries the stroke's
        // corner arc (P0 on the horizontal arm's band edge, control at the
        // vertex, P1 on the vertical arm's).
        const vx = 2 * _cell;
        const vy = 3 * _cell;
        final p0 = Offset(vx + k * dCol, vy);
        final p1 = Offset(vx, vy + k * dRow);
        for (var i = 0; i <= 24; i++) {
          final center = _quadAt(p0, Offset(vx, vy), p1, i / 25);
          final next = _quadAt(p0, Offset(vx, vy), p1, (i + 1) / 25);
          final tangent = Offset(next.dx - center.dx, next.dy - center.dy);
          final len = math.sqrt(
            tangent.dx * tangent.dx + tangent.dy * tangent.dy,
          );
          // The stroke band's edges: the centerline ± lineWidth/2 along
          // the local normal. Every rasterized band pixel lies between
          // them, so the strict allowance must admit both edges here.
          final normal = Offset(tangent.dy / len, -tangent.dx / len);
          for (final sign in [1.0, -1.0]) {
            final edgeX = center.dx + sign * normal.dx * h;
            final edgeY = center.dy + sign * normal.dy * h;
            expect(
              _distToQuadArc(edgeX, edgeY, p0, Offset(vx, vy), p1),
              lessThanOrEqualTo(h + _bandSlack),
              reason:
                  'skin ${tokens.skin.name}, corner '
                  '($dRow,$dCol): the strict allowance rejects the '
                  'legitimate stroke band edge at t=${(i / 25).toStringAsFixed(2)} '
                  '(${edgeX.toStringAsFixed(2)}, ${edgeY.toStringAsFixed(2)})',
            );
          }
        }
      }
    }
  });

  testWidgets('generated-case sweep: the pinned stage-1 fixture emits the exact-A '
      'junction (pocket absorbed, tangential band edges) and scans clean '
      '(issue 101)', (tester) async {
    await tester.runAsync(() async {
      final caseData = generateCase(
        difficulty: _fixtureDifficulty,
        seed: _fixtureSeed,
      );
      final rooms = caseData.rooms;
      final g = caseData.gridSize;
      final corner = _roundingCornerAt(rooms, g, _fixtureVertex);
      expect(
        corner,
        isNotNull,
        reason:
            'the pinned fixture junction must remain a wrapper corner '
            'under the unchanged predicate',
      );
      final (cell, dr, dc) = corner!;
      final wrapperRoom = roomOf(rooms, cell)!;
      final vx = (dc > 0 ? cell.col + 1 : cell.col) * _cell;
      final vy = (dr > 0 ? cell.row + 1 : cell.row) * _cell;

      for (final tokens in _skins) {
        final s = _scaleFor(tokens);
        final h = tokens.roomLineWidth / 2;
        final k = math.min(tokens.roomRadius, _cell / 2);
        final tail = k - h;
        final pcx = vx - dc * h;
        final pcy = vy - dr * h;
        final dxPx = (pcx * s).round();
        final dyPx = (pcy * s).round();
        final wrapperIndex = rooms.indexWhere((r) => r.id == wrapperRoom);
        final wrapperTint = tokens
            .roomTints[wrapperIndex % tokens.roomTints.length]
            .toARGB32();
        // The odd-room side beyond the band: never the wrapper tint.
        final oddPx = (
          ((vx + dc * (h + 3)) * s).round(),
          ((vy + dr * (h + 3)) * s).round(),
        );
        // The exact-A arc: pc + (dc·tail·(1−t)²·... — parameterized by the
        // offset Δ along a band edge from pc: the crossing depth on the
        // other axis is tail·(1 − √(Δ/tail))².
        double depthOf(double delta) =>
            tail * math.pow(1 - math.sqrt(delta / tail), 2).toDouble();

        final fill = await _renderBoard(
          rooms: rooms,
          g: g,
          tokens: tokens,
          withStrokes: false,
        );
        final composite = await _renderBoard(
          rooms: rooms,
          g: g,
          tokens: tokens,
        );
        for (final (raster, layer) in [(fill, 'fill'), (composite, 'live')]) {
          // The junction pocket is absorbed: the pocket-corner pixel and
          // the just-inside-the-owning-tile pixel carry the wrapper tint
          // on both layers (the stroke band stays ≥ its radius/4 away
          // from the pocket corner, so it cannot cover them). The second
          // point sits radially inside the landed quad's lens depth, so
          // it discriminates the absorbed pocket from the recessed form.
          final nearQ = (
            ((vx - dc * 1.5) * s).round(),
            ((vy - dr * 1.5) * s).round(),
          );
          expect(
            _pixelAt(raster, dxPx, dyPx),
            wrapperTint,
            reason:
                'skin ${tokens.skin.name} ($layer): the pocket corner '
                '($pcx, $pcy) is not wrapper tint — the pocket is not '
                'absorbed',
          );
          expect(
            _pixelAt(raster, nearQ.$1, nearQ.$2),
            wrapperTint,
            reason:
                'skin ${tokens.skin.name} ($layer): the pocket quarter at '
                '(${vx - dc * 1.5}, ${vy - dr * 1.5}) is not wrapper tint '
                '— the pocket is not absorbed (or the tile still '
                'recesses)',
          );
          expect(
            _pixelAt(raster, oddPx.$1, oddPx.$2),
            isNot(wrapperTint),
            reason:
                'skin ${tokens.skin.name} ($layer): wrapper tint reaches '
                'past the band edge into the odd room',
          );
        }
        // Fill only: analytic exact-A arc probes (tangency within AA on
        // both legs). One pinned offset per leg, where the arc's depth is
        // safely inside AA margins on every skin.
        final mortar = tokens.mortarColor.toARGB32();
        final delta = tail * 0.3;
        final depth = depthOf(delta);
        // Leg along x (offset Δ toward (dc, 0) from pc): the arc crosses
        // at depth past pc on y; tile between the band edge through pc
        // and the arc, plate mortar just beyond the arc (still inside the
        // pocket box).
        final tileX = pcx + dc * delta;
        final tileY = pcy + dr * depth * 0.5;
        expect(
          _pixelAt(fill, (tileX * s).round(), (tileY * s).round()),
          wrapperTint,
          reason:
              'skin ${tokens.skin.name}: no wrapper tint hugging the band '
              'edge along the exact-A x-leg at Δ=${delta.toStringAsFixed(2)} '
              '(probe (${tileX.toStringAsFixed(2)}, '
              '${tileY.toStringAsFixed(2)})) — the boundary must be the '
              'tangential exact-A quadratic',
        );
        final mortarX = pcx + dc * delta;
        final mortarY = pcy + dr * (depth + 0.9);
        expect(
          _pixelAt(fill, (mortarX * s).round(), (mortarY * s).round()),
          mortar,
          reason:
              'skin ${tokens.skin.name}: the plate does not begin just '
              'beyond the exact-A arc on the x-leg (probe ('
              '${mortarX.toStringAsFixed(2)}, ${mortarY.toStringAsFixed(2)})) '
              '— the tile must not overshoot the arc',
        );
        // Leg along y (offset Δ toward (0, dr) from pc): mirrored.
        final tileY2 = pcy + dr * delta;
        final tileX2 = pcx + dc * depth * 0.5;
        expect(
          _pixelAt(fill, (tileX2 * s).round(), (tileY2 * s).round()),
          wrapperTint,
          reason:
              'skin ${tokens.skin.name}: no wrapper tint hugging the band '
              'edge along the exact-A y-leg at Δ=${delta.toStringAsFixed(2)} '
              '— the boundary must be the tangential exact-A quadratic',
        );
        final mortarX2 = pcx + dc * (depth + 0.9);
        final mortarY2 = pcy + dr * delta;
        expect(
          _pixelAt(fill, (mortarX2 * s).round(), (mortarY2 * s).round()),
          mortar,
          reason:
              'skin ${tokens.skin.name}: the plate does not begin just '
              'beyond the exact-A arc on the y-leg — the tile must not '
              'overshoot the arc',
        );
        // And both layers scan clean of the thorn signature.
        _expectNoThorns(
          _scanThorns(fill, rooms: rooms, g: g, tokens: tokens),
          'pinned fixture, fill layer (skin ${tokens.skin.name})',
        );
        _expectNoThorns(
          _scanThorns(composite, rooms: rooms, g: g, tokens: tokens),
          'pinned fixture, live layer (skin ${tokens.skin.name})',
        );
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets(
    'generated-case sweep: 25 seeds × 3 difficulties × 3 skins through the '
    'real painters show no thorn signature (issue 101 AC)',
    (tester) async {
      await tester.runAsync(() async {
        var scanned = 0;
        for (final difficulty in Difficulty.values) {
          for (var seed = 1; seed <= _seedsPerDifficulty; seed++) {
            final caseData = generateCase(difficulty: difficulty, seed: seed);
            final rooms = caseData.rooms;
            final g = caseData.gridSize;
            for (final room in rooms) {
              expect(
                traceRoomOutline(rooms, g, room.id),
                isNotNull,
                reason:
                    '${difficulty.name} seed $seed: room ${room.id} does not '
                    'trace cleanly (the legacy per-cell render would bypass '
                    'the tile-scan premise)',
              );
            }
            for (final tokens in _skins) {
              final raster = await _renderBoard(
                rooms: rooms,
                g: g,
                tokens: tokens,
              );
              _expectNoThorns(
                _scanThorns(raster, rooms: rooms, g: g, tokens: tokens),
                '${difficulty.name} seed $seed, skin ${tokens.skin.name}',
              );
              scanned++;
            }
          }
        }
        expect(scanned, 3 * _seedsPerDifficulty * 3);
      });
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
