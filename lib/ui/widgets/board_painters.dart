import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:murdoku/domain/models.dart';
import 'package:murdoku/ui/widgets/board_geometry.dart';

/// The skin painters: the cartoon board's wall bed, wall stroke overpass and
/// victim stripes. Classic boards never use these painters.

/// Paints the cartoon board's wall bed (issue 23/83): the mortar plate (one
/// rounded bar over the whole map — any gap in the layers above reveals
/// mortar, never the page, so the page-colored pocket-artifact class is
/// unrepresentable by construction), then per-cell room-tint tiles inset by
/// the wall band (half a line on shared boundaries, the full line on outer
/// edges, zero within a room), then the legacy per-cell fallback (fills,
/// boundary lines and corner arcs) for a room whose loop fails to trace —
/// unreachable on generated data. The [SkinRoomWallPainter] stroke overpass
/// stays the cosmetic layer above the cells. Classic boards never use this
/// painter.
class SkinRoomPainter extends CustomPainter {
  SkinRoomPainter({
    required this.rooms,
    required this.gridSize,
    required this.cellSize,
    required this.tints,
    required this.mortarColor,
    required this.lineWidth,
    required this.radius,
  });

  final List<RoomDef> rooms;
  final int gridSize;
  final double cellSize;
  final List<Color> tints;
  final Color mortarColor;
  final double lineWidth;
  final double radius;

  int get roomCount => rooms.length;

  int _roomIndexAt((int, int) pos) {
    final (row, col) = pos;
    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return -1;
    return rooms.indexWhere((r) => r.contains((row: row, col: col)));
  }

  /// True when the neighbor across (dr, dc) is off the board or belongs to
  /// another room.
  bool _boundary(int row, int col, int dr, int dc) {
    final neighbor = _roomIndexAt((row + dr, col + dc));
    return neighbor == -1 || neighbor != _roomIndexAt((row, col));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintPlate(canvas);
    final fill = Paint();
    _paintTiles(canvas, fill);
    for (final (index, room) in rooms.indexed) {
      if (traceRoomOutline(rooms, gridSize, room.id) == null) {
        _paintRoomLegacy(canvas, fill, room, index);
      }
    }
  }

  /// The wall-color plate (issue 83, layer 1): one rounded bar covering the
  /// whole map bounds in [mortarColor], corner radius from the skin's
  /// tokens; painted first so every later layer's gaps show mortar.
  void _paintPlate(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, gridSize * cellSize, gridSize * cellSize),
        Radius.circular(radius),
      ),
      Paint()..color = mortarColor,
    );
  }

  /// The room-tint tiles (issue 83, layer 2): the union of per-cell rects,
  /// each side inset by the wall band, drawn as one path per room. Abutting
  /// zero-inset same-room edges are the same coordinate, so they cancel
  /// inside the union fill: same-color rects meet exactly, with no
  /// fractional AA fringe across a room in the live app, and the band edges
  /// sit exactly on their insets. A cell corner that wraps a junction per
  /// the issue 90 predicate ([roomTileCornerRounds] is unchanged) keeps its
  /// square corner — the room owns the pocket — and each wrapper junction
  /// appends the owner-approved exact-A fill ([_exactAFill], issue 101): the
  /// tile union covers the junction pocket, and only the band outside the
  /// tangential arc stays mortar, so the wall band reads as one
  /// constant-width rounded ribbon with square T junctions (the #82-era
  /// junction mortar pocket remains at every NON-wrapper junction class,
  /// which the fill never touches).
  void _paintTiles(Canvas canvas, Paint tiles) {
    for (final (index, room) in rooms.indexed) {
      final path = Path();
      for (final cell in room.cells) {
        path.addPath(_cellTilePath(cell.row, cell.col), Offset.zero);
      }
      tiles.color = tints[index % tints.length];
      canvas.drawPath(path, tiles);
    }
  }

  /// The corner diagonals a tile's rounding flags are indexed against —
  /// clockwise from the top-left, matching [_tileCornerRounding]'s tuple.
  static const List<(int, int)> _cornerDiagonals = [
    (-1, -1),
    (-1, 1),
    (1, 1),
    (1, -1),
  ];

  /// The cell's tile subpath: the plain rect plus the exact-A junction
  /// fills of its wrapper corners (issue 101; see [_exactAFill]).
  Path _cellTilePath(int row, int col) {
    final insets = _tileInsets(row, col);
    final path = _tilePath(row, col, insets);
    final (nw, ne, se, sw) = _tileCornerRounding(row, col, insets);
    final rounds = [nw, ne, se, sw];
    for (final (i, (dRow, dCol)) in _cornerDiagonals.indexed) {
      if (!rounds[i]) continue;
      path.addPath(_exactAFill(row, col, dRow, dCol), Offset.zero);
    }
    return path;
  }

  /// The tile's outline at (row, col) with per-side [insets]: a plain rect
  /// (issue 101 — the former wrapper-corner recess is replaced by the
  /// exact-A junction fills; see [_exactAFill]).
  Path _tilePath(int row, int col, (double, double, double, double) insets) {
    final (l, t, r, b) = insets;
    final left = col * cellSize + l;
    final top = row * cellSize + t;
    final right = (col + 1) * cellSize - r;
    final bottom = (row + 1) * cellSize - b;
    return Path()..addRect(Rect.fromLTRB(left, top, right, bottom));
  }

  /// The tile's four corner-round flags at (row, col), clockwise from the
  /// top-left (issue 90).
  (bool, bool, bool, bool) _tileCornerRounding(
    int row,
    int col,
    (double, double, double, double) insets,
  ) {
    final (l, t, r, b) = insets;
    return (
      roomTileCornerRounds(rooms, gridSize, row, col, -1, -1, l, t),
      roomTileCornerRounds(rooms, gridSize, row, col, -1, 1, t, r),
      roomTileCornerRounds(rooms, gridSize, row, col, 1, 1, r, b),
      roomTileCornerRounds(rooms, gridSize, row, col, 1, -1, b, l),
    );
  }

  /// The exact-A junction fill (issue 101, owner-approved variant A): at a
  /// wrapper junction the tile facing the diagonal (dRow, dCol) keeps its
  /// square corner — the room wraps the vertex, so the tile union covers the
  /// pocket — and this fill appends the junction-side region bounded by the
  /// tangential quadratic: from the band edge at tail `k − h` past the
  /// pocket corner `(V − h, V − h)` (control at the pocket corner), landing
  /// on the other band edge, then closing back through the vertex `V`. Both
  /// end tangents lie along the band edges (no angular kink), the arc's
  /// diagonal apex stays inside the pocket box, and the leg reach `k − 2h`
  /// from the vertex is under one cell edge (k ≤ cellSize/2), so the arc can
  /// never encroach an adjacent junction's pocket — T junctions keep their
  /// square corners and every other junction class keeps the #82 mortar
  /// pocket untouched. Replaces the landed `h + k`-tail quad (issues 90–94).
  Path _exactAFill(int row, int col, int dRow, int dCol) {
    final h = lineWidth / 2;
    final k = math.min(radius, cellSize / 2);
    final vx = dCol > 0 ? (col + 1) * cellSize : col * cellSize;
    final vy = dRow > 0 ? (row + 1) * cellSize : row * cellSize;
    final pcx = vx - dCol * h;
    final pcy = vy - dRow * h;
    final tail = k - h;
    final p1 = Offset(vx, pcy);
    final ps = Offset(pcx + dCol * tail, pcy);
    final pe = Offset(pcx, pcy + dRow * tail);
    final p3 = Offset(pcx, vy);
    return Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(ps.dx, ps.dy)
      ..quadraticBezierTo(pcx, pcy, pe.dx, pe.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(vx, vy)
      ..close();
  }

  /// The tile's per-side wall insets (issue 90): delegated to the shared
  /// top-level helper — the same math the cartoon victim's backdrop uses.
  (double, double, double, double) _tileInsets(int row, int col) =>
      roomTileInsets(rooms, gridSize, row, col, lineWidth);

  /// The legacy per-cell render for a room whose trace failed: today's
  /// rounded fill, boundary lines and corner arcs (issue 82 fallback).
  void _paintRoomLegacy(Canvas canvas, Paint fill, RoomDef room, int index) {
    final mortar = Paint()
      ..color = mortarColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final cell in room.cells) {
      final rect = Rect.fromLTWH(
        cell.col * cellSize,
        cell.row * cellSize,
        cellSize,
        cellSize,
      );
      _paintCell(
        canvas,
        fill,
        mortar,
        lineWidth,
        rect,
        index,
        cell.row,
        cell.col,
      );
    }
  }

  /// One cell: rounded fill, boundary lines hugging the fill edge, then the
  /// corner arcs — the original per-cell draw order (issue 35).
  void _paintCell(
    Canvas canvas,
    Paint fill,
    Paint mortar,
    double w,
    Rect rect,
    int roomIndex,
    int row,
    int col,
  ) {
    final north = _boundary(row, col, -1, 0);
    final south = _boundary(row, col, 1, 0);
    final west = _boundary(row, col, 0, -1);
    final east = _boundary(row, col, 0, 1);
    final (tl, tr, br, bl) = _cornerRadii(north, south, west, east);
    _paintCellFill(canvas, fill, rect, roomIndex, tl, tr, br, bl);
    _paintCellEdges(
      canvas,
      mortar,
      w,
      rect,
      row,
      col,
      north,
      south,
      west,
      east,
      tl,
      tr,
      br,
      bl,
    );
    _paintCornerArcs(canvas, mortar, w, rect, tl, tr, br, bl);
  }

  /// Rounded only at outer room corners: both adjacent sides are
  /// boundaries. Same-room neighbors keep square corners so their fills
  /// meet seamlessly.
  (double, double, double, double) _cornerRadii(
    bool north,
    bool south,
    bool west,
    bool east,
  ) => (
    _corner(north, west),
    _corner(north, east),
    _corner(south, east),
    _corner(south, west),
  );

  /// A corner is rounded when both of its sides are room boundaries.
  double _corner(bool sideA, bool sideB) => sideA && sideB ? radius : 0.0;

  /// The cell's room fill: a plain rect for square-cornered cells, an RRect
  /// where an outer corner is rounded.
  void _paintCellFill(
    Canvas canvas,
    Paint fill,
    Rect rect,
    int roomIndex,
    double tl,
    double tr,
    double br,
    double bl,
  ) {
    fill.color = tints[roomIndex % tints.length];
    if (tl == 0 && tr == 0 && br == 0 && bl == 0) {
      canvas.drawRect(rect, fill);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(tl),
          topRight: Radius.circular(tr),
          bottomRight: Radius.circular(br),
          bottomLeft: Radius.circular(bl),
        ),
        fill,
      );
    }
  }

  /// The cell's boundary lines. North/west lines paint on every boundary;
  /// south/east only on the board's outer edge (one stroke per internal
  /// boundary).
  void _paintCellEdges(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    int row,
    int col,
    bool north,
    bool south,
    bool west,
    bool east,
    double tl,
    double tr,
    double br,
    double bl,
  ) {
    _paintNorthEdge(canvas, mortar, w, rect, tl, tr, north);
    _paintWestEdge(canvas, mortar, w, rect, tl, bl, west);
    if (south && row == gridSize - 1) {
      _paintSouthEdge(canvas, mortar, w, rect, bl, br);
    }
    if (east && col == gridSize - 1) {
      _paintEastEdge(canvas, mortar, w, rect, tr, br);
    }
  }

  /// Lines stop short of rounded corners where an arc takes over.
  double _inset(double corner, double w) => corner > 0 ? corner : w / 2;

  void _paintNorthEdge(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    double tl,
    double tr,
    bool boundary,
  ) {
    if (!boundary) return;
    canvas.drawLine(
      Offset(rect.left + _inset(tl, w), rect.top + w / 2),
      Offset(rect.right - _inset(tr, w), rect.top + w / 2),
      mortar,
    );
  }

  void _paintWestEdge(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    double tl,
    double bl,
    bool boundary,
  ) {
    if (!boundary) return;
    canvas.drawLine(
      Offset(rect.left + w / 2, rect.top + _inset(tl, w)),
      Offset(rect.left + w / 2, rect.bottom - _inset(bl, w)),
      mortar,
    );
  }

  void _paintSouthEdge(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    double bl,
    double br,
  ) {
    canvas.drawLine(
      Offset(rect.left + _inset(bl, w), rect.bottom - w / 2),
      Offset(rect.right - _inset(br, w), rect.bottom - w / 2),
      mortar,
    );
  }

  void _paintEastEdge(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    double tr,
    double br,
  ) {
    canvas.drawLine(
      Offset(rect.right - w / 2, rect.top + _inset(tr, w)),
      Offset(rect.right - w / 2, rect.bottom - _inset(br, w)),
      mortar,
    );
  }

  /// Corner arcs: the stroke follows the rounded fill corner.
  void _paintCornerArcs(
    Canvas canvas,
    Paint mortar,
    double w,
    Rect rect,
    double tl,
    double tr,
    double br,
    double bl,
  ) {
    void arc(Offset center, double startAngle) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - w / 2),
        startAngle,
        math.pi / 2,
        false,
        mortar,
      );
    }

    if (tl > 0) arc(rect.topLeft + Offset(radius, radius), math.pi);
    if (tr > 0) arc(rect.topRight + Offset(-radius, radius), -math.pi / 2);
    if (br > 0) arc(rect.bottomRight + Offset(-radius, -radius), 0);
    if (bl > 0) arc(rect.bottomLeft + Offset(radius, -radius), math.pi / 2);
  }

  @override
  bool shouldRepaint(SkinRoomPainter oldDelegate) => _fieldsChanged(
    [rooms, gridSize, cellSize, tints, mortarColor, lineWidth, radius],
    [
      oldDelegate.rooms,
      oldDelegate.gridSize,
      oldDelegate.cellSize,
      oldDelegate.tints,
      oldDelegate.mortarColor,
      oldDelegate.lineWidth,
      oldDelegate.radius,
    ],
  );
}

/// True when any painter field changed. The `!=` comparisons keep each
/// field's exact identity semantics from the former `||` chain (issue 35).
bool _fieldsChanged(List<Object?> a, List<Object?> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

/// Strokes one continuous rounded wall outline per traced room, ABOVE the
/// cell layer (issue 82): a single path per room, `strokeJoin`/`strokeCap`
/// round, quadratic K-rounding at every 90° turn (convex and concave) with
/// `radius` clamped to the unit segment — so walls always read as one
/// solid line, including over the victim's chalk sprite. Paints nothing for
/// a room whose trace fails ([SkinRoomPainter]'s legacy pass renders
/// those per-cell). Classic boards never use this painter.
class SkinRoomWallPainter extends CustomPainter {
  SkinRoomWallPainter({
    required this.rooms,
    required this.gridSize,
    required this.cellSize,
    required this.mortarColor,
    required this.lineWidth,
    required this.radius,
  });

  final List<RoomDef> rooms;
  final int gridSize;
  final double cellSize;
  final Color mortarColor;
  final double lineWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final mortar = Paint()
      ..color = mortarColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final room in rooms) {
      final loop = traceRoomOutline(rooms, gridSize, room.id);
      if (loop == null) continue;
      canvas.drawPath(_roomOutlinePath(loop, cellSize, radius), mortar);
    }
  }

  @override
  bool shouldRepaint(SkinRoomWallPainter oldDelegate) => _fieldsChanged(
    [rooms, gridSize, cellSize, mortarColor, lineWidth, radius],
    [
      oldDelegate.rooms,
      oldDelegate.gridSize,
      oldDelegate.cellSize,
      oldDelegate.mortarColor,
      oldDelegate.lineWidth,
      oldDelegate.radius,
    ],
  );
}

/// Diagonal stripes for the cartoon victim cell (issue 23 mockups). Painted
/// inside a ClipRect so the stripes never bleed into neighboring cells.
class SkinVictimStripePainter extends CustomPainter {
  SkinVictimStripePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.butt;
    const spacing = 12.0;
    for (var d = -size.height; d < size.width + size.height; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SkinVictimStripePainter oldDelegate) =>
      color != oldDelegate.color;
}

/// Grid vertex [p] in board pixels at [cell] per cell.
Offset _roomVertexPixel(Pos p, double cell) =>
    Offset(p.col * cell, p.row * cell);

/// The pixel step of [length] along axis direction [d].
Offset _roomDirPixel(Pos d, double length) =>
    Offset(d.col * length, d.row * length);

/// The unit-step direction of the loop's j-th segment (vertex j → j+1,
/// wrapping).
Pos _segDir(List<Pos> loop, int j) => (
  row: loop[(j + 1) % loop.length].row - loop[j].row,
  col: loop[(j + 1) % loop.length].col - loop[j].col,
);

/// The pixel path over the traced [loop]: unit straight runs joined by
/// quadratic K-rounding at every 90° turn — the mock's continuous rounded
/// silhouette the wall stroke traces; K = [radius] clamped to the unit
/// segment (mock K-rounding, issue 82; since issue 83 the tile layer is the
/// only fill, so the painter's one remaining caller always rounds corners).
Path _roomOutlinePath(List<Pos> loop, double cellSize, double radius) {
  final path = Path();
  final n = loop.length;
  if (n < 3) return path;
  final k = math.min(radius, cellSize / 2);
  final start =
      _roomVertexPixel(loop[0], cellSize) + _roomDirPixel(_segDir(loop, 0), k);
  path.moveTo(start.dx, start.dy);
  for (var i = 1; i <= n; i++) {
    final j = i % n;
    final vertex = _roomVertexPixel(loop[j], cellSize);
    final prevDir = _segDir(loop, (j + n - 1) % n);
    final outDir = _segDir(loop, j);
    final back = vertex - _roomDirPixel(prevDir, k);
    final out = vertex + _roomDirPixel(outDir, k);
    path.lineTo(back.dx, back.dy);
    path.quadraticBezierTo(vertex.dx, vertex.dy, out.dx, out.dy);
  }
  path.close();
  return path;
}
