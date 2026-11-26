import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/avatar.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';

/// The mansion map: G×G rooms with suspects, the victim, objects and X marks.
/// Square by construction; scales to any width. All cells are tappable with
/// semantics labels; drags are tracked at board level so sweeping across
/// cells works for the X and erase tools.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.caseData,
    required this.placed,
    required this.xMarks,
    required this.selectedSuspectId,
    required this.onCellTap,
    required this.onCellDrag,
  });

  final CaseData caseData;
  final Map<String, Pos> placed;
  final Set<Pos> xMarks;
  final String? selectedSuspectId;
  final void Function(Pos) onCellTap;
  final void Function(Pos) onCellDrag;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  Pos? _lastDragCell;

  void _fireDrag(Offset local, double cell, int g) {
    var col = (local.dx / cell).floor().clamp(0, g - 1);
    var row = (local.dy / cell).floor().clamp(0, g - 1);
    final p = (row: row, col: col);
    if (p == _lastDragCell) return;
    _lastDragCell = p;
    widget.onCellDrag(p);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.caseData.gridSize;
    // Cartoon skins repaint the board as solid room blocks (issue 23); the
    // classic skin keeps its per-cell borders (maybeOf null → classic).
    final tokens = SkinScope.maybeOf(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Square by construction: fit the smaller constraint so a
          // landscape window (wider than tall) shrinks the grid instead of
          // height-clamping the box, which would clip the bottom row and
          // leave its cells untappable.
          final side = math.min(constraints.maxWidth, constraints.maxHeight);
          final cell = side / g;
          final anchors = _roomAnchors(widget.caseData);
          final scheme = Theme.of(context).colorScheme;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _lastDragCell = null;
              _fireDrag(details.localPosition, cell, g);
            },
            onPanUpdate: (details) => _fireDrag(details.localPosition, cell, g),
            child: SizedBox(
              key: const Key('board_view'),
              width: side,
              height: side,
              child: Stack(
                children: [
                  // The wall bed (plate + room tiles) under the cells
                  // (issue 23/82/83).
                  ?_fillLayer(tokens, g, side, cell),
                  for (var row = 0; row < g; row++)
                    for (var col = 0; col < g; col++)
                      Positioned(
                        left: col * cell,
                        top: row * cell,
                        width: cell,
                        height: cell,
                        child: _Cell(
                          key: Key('cell_${row}_$col'),
                          caseData: widget.caseData,
                          cellSize: cell,
                          pos: (row: row, col: col),
                          placed: widget.placed,
                          xMarks: widget.xMarks,
                          selectedSuspectId: widget.selectedSuspectId,
                          onCellTap: widget.onCellTap,
                        ),
                      ),
                  // The wall pass strokes over the cell content (issue 82).
                  ?_wallLayer(tokens: tokens, g: g, side: side, cell: cell),
                  // The room number badges top the stack (issue 90): moving
                  // them out of the guest content keeps every badge above
                  // furniture sprites and wall strokes on every skin; they
                  // are static per case, so there is no repaint churn.
                  for (final anchor in anchors)
                    Positioned(
                      key: Key('room_badge_${anchor.row}_${anchor.col}'),
                      left: anchor.col * cell,
                      top: anchor.row * cell,
                      width: cell,
                      height: cell,
                      child: IgnorePointer(
                        child: _RoomBadge(
                          roomNumber: _roomBadgeNumber(
                            anchors,
                            widget.caseData,
                            anchor,
                          ),
                          tokens: tokens,
                          scheme: scheme,
                          cartoon: tokens != null && tokens.solidRooms,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The wall bed under the cells (issue 23/83): `SkinRoomPainter`'s mortar
  /// plate + room-tint tiles; null for the classic skin, which keeps its
  /// per-cell borders.
  Widget? _fillLayer(SkinTokens? tokens, int g, double side, double cell) {
    if (tokens == null || !tokens.solidRooms) return null;
    return Positioned(
      left: 0,
      top: 0,
      width: side,
      height: side,
      child: CustomPaint(
        size: Size(side, side),
        painter: SkinRoomPainter(
          rooms: widget.caseData.rooms,
          gridSize: g,
          cellSize: cell,
          tints: tokens.roomTints,
          mortarColor: tokens.mortarColor,
          lineWidth: tokens.roomLineWidth,
          radius: tokens.roomRadius,
        ),
      ),
    );
  }

  /// The wall pass strokes over the cell content (issue 82): one continuous
  /// rounded outline per room, clipped to the board so hull walls cut at
  /// the board edge like the mock; null for the classic skin.
  Widget? _wallLayer({
    required SkinTokens? tokens,
    required int g,
    required double side,
    required double cell,
  }) {
    if (tokens == null || !tokens.solidRooms) return null;
    return Positioned(
      left: 0,
      top: 0,
      width: side,
      height: side,
      child: ClipRect(
        // Taps pass through to the cells below the stroke.
        child: IgnorePointer(
          child: CustomPaint(
            size: Size(side, side),
            painter: SkinRoomWallPainter(
              rooms: widget.caseData.rooms,
              gridSize: g,
              cellSize: cell,
              mortarColor: tokens.mortarColor,
              lineWidth: tokens.roomLineWidth,
              radius: tokens.roomRadius,
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchor cell of each room (top-left-most, victim cell excluded): carries
/// the number badge shown in the legend.
Set<Pos> _roomAnchors(CaseData caseData) => {
  for (final room in caseData.rooms)
    ([...room.cells]
          ..sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col))
        .firstWhere((cell) => cell != caseData.victimPos),
};

/// The 1-based room number for a badge anchor cell, null elsewhere.
int? _roomBadgeNumber(Set<Pos> anchors, CaseData caseData, Pos pos) =>
    anchors.contains(pos)
    ? caseData.rooms.indexWhere((r) => r.contains(pos)) + 1
    : null;

/// The per-side wall insets of one room tile at (row, col): (left, top,
/// right, bottom) — the full [lineWidth] on the board's outer edge, half a
/// line across a room boundary, zero within the room. Single source for the
/// room painter's tiles and the cartoon victim's inset backdrop (issue 90).
(double, double, double, double) roomTileInsets(
  List<RoomDef> rooms,
  int gridSize,
  int row,
  int col,
  double lineWidth,
) => (
  roomTileInset(rooms, gridSize, row, col, 0, -1, lineWidth),
  roomTileInset(rooms, gridSize, row, col, -1, 0, lineWidth),
  roomTileInset(rooms, gridSize, row, col, 0, 1, lineWidth),
  roomTileInset(rooms, gridSize, row, col, 1, 0, lineWidth),
);

/// The tile's inset on the side of (row, col) facing (dRow, dCol): the full
/// [lineWidth] when the neighbor is off the board, half a line across a room
/// boundary, zero within the room.
double roomTileInset(
  List<RoomDef> rooms,
  int gridSize,
  int row,
  int col,
  int dRow,
  int dCol,
  double lineWidth,
) => _inBoard((row: row + dRow, col: col + dCol), gridSize)
    ? _tileInsetInsideBoard(rooms, row, col, row + dRow, col + dCol, lineWidth)
    : lineWidth;

/// The on-board branch of [roomTileInset]: zero within the room, half a
/// line across a room boundary.
double _tileInsetInsideBoard(
  List<RoomDef> rooms,
  int row,
  int col,
  int nRow,
  int nCol,
  double lineWidth,
) =>
    roomOf(rooms, (row: nRow, col: nCol)) == roomOf(rooms, (row: row, col: col))
    ? 0.0
    : lineWidth / 2;

/// True when the tile corner of the cell at (row, col) facing the diagonal
/// (dRow, dCol) rounds (issue 90): both adjacent tile sides are same-room
/// (zero insets — the room wraps the corner vertex) and the cell across the
/// vertex diagonally belongs to another room. Corners with a wall side stay
/// square — their stroke arcs cover them cleanly, and same-room butt joints
/// must stay exactly flush.
bool roomTileCornerRounds(
  List<RoomDef> rooms,
  int gridSize,
  int row,
  int col,
  int dRow,
  int dCol,
  double insetA,
  double insetB,
) =>
    _tileSidesInsideRoom(insetA, insetB) &&
    _tileDiagonalDiffers(rooms, gridSize, row, col, dRow, dCol);

/// True when a tile corner's two adjacent sides are same-room (both tile
/// insets zero): the vertex is inside the room's tile union.
bool _tileSidesInsideRoom(double insetA, double insetB) =>
    insetA == 0.0 && insetB == 0.0;

/// True when the diagonal cell across a corner vertex from (row, col) shifted
/// by (dRow, dCol) is on-board and belongs to another room.
bool _tileDiagonalDiffers(
  List<RoomDef> rooms,
  int gridSize,
  int row,
  int col,
  int dRow,
  int dCol,
) =>
    _inBoard((row: row + dRow, col: col + dCol), gridSize) &&
    roomOf(rooms, (row: row + dRow, col: col + dCol)) !=
        roomOf(rooms, (row: row, col: col));

/// One cell-edge spec relative to a cell: the traced half-edge walks from
/// the start vertex along [dir], and the edge is a boundary when the
/// neighbor across [neighbor] differs (mock-verified half-edge table:
/// north (r,c)→E, east (r,c+1)→S, south (r+1,c+1)→W, west (r+1,c)→N).
const List<({Pos dir, Pos start, Pos neighbor})> _edgeSpecs = [
  (dir: (row: 0, col: 1), start: (row: 0, col: 0), neighbor: (row: -1, col: 0)),
  (dir: (row: 1, col: 0), start: (row: 0, col: 1), neighbor: (row: 0, col: 1)),
  (dir: (row: 0, col: -1), start: (row: 1, col: 1), neighbor: (row: 1, col: 0)),
  (
    dir: (row: -1, col: 0),
    start: (row: 1, col: 0),
    neighbor: (row: 0, col: -1),
  ),
];

/// Grid-space vector addition (vertices, directions).
Pos _shift(Pos a, Pos b) => (row: a.row + b.row, col: a.col + b.col);

/// 90° clockwise rotation (screen space, y grows down): E→S→W→N→E.
Pos _rotateCW(Pos d) => (row: d.col, col: -d.row);

/// 90° counter-clockwise rotation.
Pos _rotateCCW(Pos d) => (row: -d.col, col: d.row);

/// True while [p] sits inside a G×G board.
bool _inBoard(Pos p, int g) =>
    p.row >= 0 && p.row < g && p.col >= 0 && p.col < g;

/// True when the cell edge across [neighbor] is a room boundary: the
/// neighbor is off-board or belongs to another room. The victim cell is a
/// room cell like any other (issue 82).
bool _edgeIsBoundary(
  List<RoomDef> rooms,
  int gridSize,
  String roomId,
  Pos neighbor,
) => _inBoard(neighbor, gridSize) ? roomOf(rooms, neighbor) != roomId : true;

/// The tiled room's cells, empty when [roomId] names no room.
List<Pos> _roomCells(List<RoomDef> rooms, String roomId) {
  for (final room in rooms) {
    if (room.id == roomId) return room.cells;
  }
  return const [];
}

/// The room's boundary half-edges grouped by start vertex: each entry keeps
/// the pending walking directions leaving that vertex. A LIST per vertex —
/// a corner vertex legitimately starts two edges (one per side).
Map<Pos, List<Pos>> _roomHalfEdges(
  List<RoomDef> rooms,
  int gridSize,
  String roomId,
) {
  final edges = <Pos, List<Pos>>{};
  for (final cell in _roomCells(rooms, roomId)) {
    for (final (dir: dir, start: relStart, neighbor: relNeighbor)
        in _edgeSpecs) {
      if (_edgeIsBoundary(rooms, gridSize, roomId, _shift(cell, relNeighbor))) {
        edges.putIfAbsent(_shift(cell, relStart), () => <Pos>[]).add(dir);
      }
    }
  }
  return edges;
}

/// Walks one closed clockwise boundary loop from [start], room interior on
/// the right (right turn, then straight, never reverse), consuming exactly
/// one pending half-edge per step; null when the walk cannot continue.
List<Pos>? _walkLoop(Map<Pos, List<Pos>> pending, Pos start) {
  final first = pending[start]?.removeAt(0);
  if (first == null) return null;
  final loop = <Pos>[start];
  var dir = first;
  var cur = _shift(start, first);
  while (cur != start) {
    final next = _advance(pending, cur, dir, loop);
    if (next == null) return null;
    dir = next;
    cur = _shift(cur, next);
  }
  return loop;
}

/// Consumes one pending half-edge at [cur] (turn priority in
/// [_pickNext]), records [cur] in [loop] and returns the next direction.
Pos? _advance(Map<Pos, List<Pos>> pending, Pos cur, Pos dir, List<Pos> loop) {
  final options = pending[cur];
  if (options == null || options.isEmpty) return null;
  final next = _pickNext(options, dir);
  if (next == null) return null;
  loop.add(cur);
  return next;
}

/// Removes and returns the option to walk next from [options]: the right
/// turn first, then straight, then the left turn; null leaves only the
/// reverse, which a clean room boundary never needs.
Pos? _pickNext(List<Pos> options, Pos incoming) {
  var i = options.indexOf(_rotateCW(incoming));
  if (i < 0) i = options.indexOf(incoming);
  if (i < 0) i = options.indexOf(_rotateCCW(incoming));
  if (i < 0) return null;
  return options.removeAt(i);
}

/// The room's boundary as one closed clockwise unit-edge loop — a cycle of
/// grid vertices whose consecutive deltas are unit cell-edge steps, room
/// interior on the right — or null when the boundary does not trace
/// cleanly (hole, disconnected pieces; such rooms render with the legacy
/// per-cell path, unreachable on generated data).
List<Pos>? traceRoomOutline(List<RoomDef> rooms, int gridSize, String roomId) {
  final pending = _roomHalfEdges(rooms, gridSize, roomId);
  if (pending.isEmpty) return null;
  final loop = _walkLoop(pending, pending.keys.first);
  if (loop == null || loop.length < 4) return null;
  return pending.values.every((left) => left.isEmpty) ? loop : null;
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

/// The suspect sitting at [p], or null when the cell is guest-free.
String? _suspectAt(Map<String, Pos> placed, Pos p) {
  for (final entry in placed.entries) {
    if (entry.value == p) return entry.key;
  }
  return null;
}

/// True when [objectHere] holds furniture a guest may not share.
bool _isBlocking(List<ObjectDef> objectHere) =>
    objectHere.isNotEmpty && !objectHere.first.occupiable;

/// The cell's Container decoration; null when neither fill nor border apply.
BoxDecoration? _cellDecoration(Color? fill, Border? border) =>
    fill == null && border == null
    ? null
    : BoxDecoration(color: fill, border: border);

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.caseData,
    required this.cellSize,
    required this.pos,
    required this.placed,
    required this.xMarks,
    required this.selectedSuspectId,
    required this.onCellTap,
  });

  final CaseData caseData;
  final double cellSize;
  final Pos pos;
  final Map<String, Pos> placed;
  final Set<Pos> xMarks;
  final String? selectedSuspectId;
  final void Function(Pos) onCellTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = caseData;
    final pos = this.pos;
    final g = c.gridSize;

    final roomIndex = c.rooms.indexWhere((r) => r.contains(pos));
    final room = c.rooms[roomIndex];
    final isVictim = pos == c.victimPos;
    final suspectIdHere = _suspectAt(placed, pos);
    final hasX = xMarks.contains(pos);
    final objectHere = c.objects.where((o) => o.pos == pos).toList();

    final rowBlocked = placed.values.any((p) => p.row == pos.row);
    final colBlocked = placed.values.any((p) => p.col == pos.col);

    final tokens = SkinScope.maybeOf(context);
    final cartoon = tokens != null && tokens.solidRooms;

    final scheme = Theme.of(context).colorScheme;
    final (cellFill, cellBorder) = _cellVisual(
      c: c,
      pos: pos,
      g: g,
      room: room,
      roomIndex: roomIndex,
      isVictim: isVictim,
      rowBlocked: rowBlocked,
      colBlocked: colBlocked,
      scheme: scheme,
      tokens: tokens,
      cartoon: cartoon,
    );

    var state = isVictim
        ? l10n.stateVictim
        : _cellState(
            l10n,
            c,
            suspectIdHere: suspectIdHere,
            hasX: hasX,
            objectHere: objectHere,
          );
    if (state.isEmpty) state = l10n.stateEmpty;
    final label = l10n.cellSemantics(pos.row, pos.col, room.name, state);

    final spritePad = _spritePad(cartoon, tokens);
    final content = isVictim
        ? _victimContent(
            l10n,
            label,
            scheme,
            tokens,
            cartoon,
            c,
            pos,
            spritePad: spritePad,
            cellSize: cellSize,
          )
        : _guestContent(
            c,
            suspectIdHere: suspectIdHere,
            hasX: hasX,
            objectHere: objectHere,
            selectedSuspectId: selectedSuspectId,
            scheme: scheme,
            tokens: tokens,
            cartoon: cartoon,
            spritePad: spritePad,
            cellSize: cellSize,
          );

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCellTap(pos),
        child: Container(
          key: _cellKey(isVictim),
          decoration: _cellDecoration(cellFill, cellBorder),
          child: content,
        ),
      ),
    );
  }

  /// The victim cell's test key; other cells are keyed by their board
  /// coordinates.
  Key? _cellKey(bool isVictim) => isVictim ? const Key('victim_cell') : null;

  /// The cell's fill (both skins) and border (classic only): cartoon cells
  /// keep only state overlays over the painter's room blocks (issue 23).
  (Color?, Border?) _cellVisual({
    required CaseData c,
    required Pos pos,
    required int g,
    required RoomDef room,
    required int roomIndex,
    required bool isVictim,
    required bool rowBlocked,
    required bool colBlocked,
    required ColorScheme scheme,
    required SkinTokens? tokens,
    required bool cartoon,
  }) {
    if (cartoon) {
      return (_cartoonFill(tokens!, isVictim, rowBlocked, colBlocked), null);
    }
    return (
      _classicFill(
        c,
        pos,
        g,
        roomIndex,
        isVictim,
        rowBlocked,
        colBlocked,
        scheme,
      ),
      _cellBorder(c, pos, g, room, scheme),
    );
  }

  /// Solid-room overlay fill: the row/column occupancy overlay; null keeps
  /// the cell undecorated (the painter carries the tint). The victim's fill
  /// paints inside the cell content, inset by the tile insets (issue 90) —
  /// never edge-to-edge over the wall band.
  Color? _cartoonFill(
    SkinTokens tokens,
    bool isVictim,
    bool rowBlocked,
    bool colBlocked,
  ) {
    if (isVictim) return null;
    if (rowBlocked || colBlocked) return tokens.ink.withValues(alpha: 0.10);
    return null;
  }

  /// Classic per-cell fill: room tint, victim container, occupancy blend.
  Color _classicFill(
    CaseData c,
    Pos pos,
    int g,
    int roomIndex,
    bool isVictim,
    bool rowBlocked,
    bool colBlocked,
    ColorScheme scheme,
  ) {
    var fill = AppTheme.roomColors(g)[roomIndex].withValues(alpha: 0.55);
    if (isVictim) fill = scheme.errorContainer;
    if (rowBlocked || colBlocked) {
      fill = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.10), fill);
    }
    return fill;
  }

  /// Room boundary: thicker edge where the neighbor belongs to another room.
  Border _cellBorder(
    CaseData c,
    Pos pos,
    int g,
    RoomDef room,
    ColorScheme scheme,
  ) {
    const thin = 0.5;
    const thick = 2.5;
    final northRoom = _adjacentRoom(c, pos, g, -1, 0);
    final westRoom = _adjacentRoom(c, pos, g, 0, -1);
    final southRoom = _adjacentRoom(c, pos, g, 1, 0);
    final eastRoom = _adjacentRoom(c, pos, g, 0, 1);
    return Border(
      top: BorderSide(
        width: _edgeWidth(northRoom != room.id, thick, thin),
        color: scheme.outline,
      ),
      left: BorderSide(
        width: _edgeWidth(westRoom != room.id, thick, thin),
        color: scheme.outline,
      ),
      right: BorderSide(
        width: _edgeWidth(eastRoom != room.id, thick, thin),
        color: scheme.outline,
      ),
      bottom: BorderSide(
        width: _edgeWidth(southRoom != room.id, thick, thin),
        color: scheme.outline,
      ),
    );
  }

  /// The room across (dRow, dCol), or null off the board edge.
  String? _adjacentRoom(CaseData c, Pos pos, int g, int dRow, int dCol) {
    final row = pos.row + dRow;
    final col = pos.col + dCol;
    final inside = row >= 0 && row < g && col >= 0 && col < g;
    return inside ? roomOf(c.rooms, (row: row, col: col)) : null;
  }

  double _edgeWidth(bool boundary, double thick, double thin) =>
      boundary ? thick : thin;

  /// The cell's semantics state text for a non-victim cell: guest name, or
  /// the exclusion/furniture/blocked descriptors.
  String _cellState(
    AppLocalizations l10n,
    CaseData c, {
    required String? suspectIdHere,
    required bool hasX,
    required List<ObjectDef> objectHere,
  }) {
    if (suspectIdHere != null) {
      return c.suspects.firstWhere((s) => s.id == suspectIdHere).name;
    }
    final furnitureName = objectHere.isNotEmpty
        ? NameForms.forLocale(
            l10n.localeName,
            c,
          ).objectNom(objectHere.first.kind)
        : null;
    return [
      if (hasX) l10n.stateExcluded,
      ?furnitureName,
      if (_isBlocking(objectHere)) l10n.stateBlocked,
    ].join(' · ');
  }

  /// The sprite inset per side: the wall pass plus the mock's 2px gap
  /// (issue 82); classic cells keep today's zero inset.
  double _spritePad(bool cartoon, SkinTokens? tokens) =>
      cartoon ? tokens!.roomLineWidth + 2 : 0;

  /// The victim sprite side: capped at 40, shrunk inside the cell's inner
  /// area (wall pass + 2px per side) on narrow boards (issue 82).
  double _victimSide(bool cartoon, double cellSize, double spritePad) =>
      cartoon ? math.min(40, math.max(0, cellSize - spritePad * 2)) : 40;

  /// The centered furniture sprite's [ItemSprite] size param capped at 28
  /// and shrunk inside the cell's inner area on narrow boards; the rendered
  /// image is 1.35× this (issue 82).
  double _furnitureSize(bool cartoon, double cellSize, double spritePad) =>
      cartoon
      ? math.min(28, math.max(0, (cellSize - spritePad * 2) / 1.35))
      : 28;

  /// The victim cell: striped cartoon backdrop under the chalk-outline
  /// image. The backdrop's flat fill + stripes stop at the tile insets
  /// (issue 90): no victim color paints over the wall band, at any edge.
  Widget _victimContent(
    AppLocalizations l10n,
    String label,
    ColorScheme scheme,
    SkinTokens? tokens,
    bool cartoon,
    CaseData c,
    Pos pos, {
    required double spritePad,
    required double cellSize,
  }) {
    final (l, t, r, b) = cartoon && tokens != null
        ? roomTileInsets(
            c.rooms,
            c.gridSize,
            pos.row,
            pos.col,
            tokens.roomLineWidth,
          )
        : (0.0, 0.0, 0.0, 0.0);
    return Semantics(
      label: '${l10n.victimLabel}: $label',
      child: Stack(
        children: [
          if (cartoon)
            // Striped victim cell per the cartoon mockups (issue 23),
            // inset by the room tile's wall band (issue 90).
            Positioned(
              left: l,
              top: t,
              right: r,
              bottom: b,
              child: ClipRect(
                child: ColoredBox(
                  color: tokens!.victimFill,
                  child: CustomPaint(
                    painter: SkinVictimStripePainter(
                      color: tokens.victimStripeColor,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(spritePad),
            child: ClipRect(
              child: Center(
                child: Image.asset(
                  'assets/items/victim.png',
                  width: _victimSide(cartoon, cellSize, spritePad),
                  height: _victimSide(cartoon, cellSize, spritePad),
                  // Chalk outline always beats a letter — the letter is a
                  // last-resort fallback if the asset is missing.
                  errorBuilder: (_, _, _) => Text(
                    'V',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A non-victim cell: furniture underlay and the occupant. The room
  /// number badge is a board-level layer above the walls (issue 90).
  Widget _guestContent(
    CaseData c, {
    required String? suspectIdHere,
    required bool hasX,
    required List<ObjectDef> objectHere,
    required String? selectedSuspectId,
    required ColorScheme scheme,
    required SkinTokens? tokens,
    required bool cartoon,
    required double spritePad,
    required double cellSize,
  }) {
    final itemIcon = objectHere.isNotEmpty
        ? objectIcon(objectHere.first.kind)
        : null;
    final suspectIndexHere = suspectIdHere == null
        ? null
        : c.suspects.indexWhere((s) => s.id == suspectIdHere);
    final dimmed = _isBlocking(objectHere) && !hasX;
    final underlay = _furnitureUnderlay(
      objectHere,
      itemIcon,
      suspectIndexHere,
      dimmed,
    );
    return Stack(
      children: [
        // Furniture renders under everything in the cell.
        ?underlay,
        // The occupant layer is inset and clipped so sprites never cross
        // the border band (issue 82).
        Padding(
          padding: EdgeInsets.all(spritePad),
          child: ClipRect(
            child: _occupant(
              c,
              suspectIdHere,
              suspectIndexHere,
              hasX,
              itemIcon,
              objectHere,
              selectedSuspectId,
              dimmed,
              scheme,
              tokens,
              cartoon,
              furnitureSize: _furnitureSize(cartoon, cellSize, spritePad),
            ),
          ),
        ),
      ],
    );
  }

  /// The small furniture sprite pinned top-left when a guest or X shares
  /// the cell with the item; null otherwise.
  Widget? _furnitureUnderlay(
    List<ObjectDef> objectHere,
    IconData? itemIcon,
    int? suspectIndexHere,
    bool dimmed,
  ) {
    if (itemIcon == null) return null;
    if (suspectIndexHere == null) return null;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _furnitureSprite(objectHere.first.kind, 12, dimmed: dimmed),
      ),
    );
  }

  /// The cell's main occupant: guest avatar, X mark, centered furniture, or
  /// nothing.
  Widget _occupant(
    CaseData c,
    String? suspectIdHere,
    int? suspectIndexHere,
    bool hasX,
    IconData? itemIcon,
    List<ObjectDef> objectHere,
    String? selectedSuspectId,
    bool dimmed,
    ColorScheme scheme,
    SkinTokens? tokens,
    bool cartoon, {
    required double furnitureSize,
  }) {
    if (suspectIndexHere != null) {
      return Center(
        child: Avatar(
          color: suspectColor(suspectIndexHere),
          selected: suspectIdHere == selectedSuspectId,
          size: 30,
        ),
      );
    }
    if (hasX) {
      return Center(
        child: Icon(
          Icons.close,
          color: cartoon ? tokens!.ink : scheme.error,
          size: 22,
        ),
      );
    }
    if (itemIcon != null) {
      return Center(
        child: _furnitureSprite(
          objectHere.first.kind,
          furnitureSize,
          dimmed: dimmed,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// The furniture sprite, dimmed while sharing a cell with a guest or X.
  Widget _furnitureSprite(
    ObjectKind kind,
    double size, {
    required bool dimmed,
  }) => ItemSprite(kind: kind, size: size, opacity: dimmed ? 0.85 : 1.0);
}

/// The room number badge on a board cell's top-right corner; hidden without
/// a number.
class _RoomBadge extends StatelessWidget {
  const _RoomBadge({
    required this.roomNumber,
    required this.tokens,
    required this.scheme,
    required this.cartoon,
  });

  final int? roomNumber;
  final SkinTokens? tokens;
  final ColorScheme scheme;
  final bool cartoon;

  @override
  Widget build(BuildContext context) {
    if (roomNumber == null) return const SizedBox.shrink();
    final size = cartoon ? 20.0 : 16.0;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          width: size,
          height: size,
          decoration: _badgeDecoration(),
          child: Center(child: Text('$roomNumber', style: _badgeStyle())),
        ),
      ),
    );
  }

  BoxDecoration _badgeDecoration() => BoxDecoration(
    shape: BoxShape.circle,
    color: cartoon ? tokens!.badge.background : scheme.primaryContainer,
    border: Border.all(
      width: 1,
      color: cartoon ? tokens!.badge.ink : scheme.onPrimaryContainer,
    ),
  );

  TextStyle _badgeStyle() => TextStyle(
    fontSize: cartoon ? 11 : 10,
    fontWeight: FontWeight.bold,
    color: cartoon ? tokens!.badge.ink : scheme.onPrimaryContainer,
  );
}

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

  /// The room-tint tiles (issue 83, layer 2): the union of per-cell shapes,
  /// each side inset by the wall band, drawn as one path per room. Abutting
  /// zero-inset same-room edges are the same coordinate, so they cancel
  /// inside the union fill: same-color rects meet exactly, with no
  /// fractional AA fringe across a room in the live app, and the band edges
  /// sit exactly on their insets. A tile corner at a wrapper junction rounds
  /// with the stroke's K-rounding (issue 90) so the wall silhouette reads as
  /// one continuous rounded corner instead of a stepped notch.
  void _paintTiles(Canvas canvas, Paint tiles) {
    final k = math.min(radius, cellSize / 2);
    for (final (index, room) in rooms.indexed) {
      final path = Path();
      for (final cell in room.cells) {
        final insets = _tileInsets(cell.row, cell.col);
        path.addPath(_tilePath(cell.row, cell.col, insets, k), Offset.zero);
      }
      tiles.color = tints[index % tints.length];
      canvas.drawPath(path, tiles);
    }
  }

  /// The tile's outline at (row, col) with per-side [insets]: a plain rect,
  /// plus a quadratic K-round at every corner that rounds per the issue 90
  /// predicate (see [roomTileCornerRounds]). The rounding uses the same form
  /// and clamp as [_roomOutlinePath] so the tile's convex corners align with
  /// the wall stroke's K-rounding.
  Path _tilePath(
    int row,
    int col,
    (double, double, double, double) insets,
    double k,
  ) {
    final (l, t, r, b) = insets;
    final left = col * cellSize + l;
    final top = row * cellSize + t;
    final right = (col + 1) * cellSize - r;
    final bottom = (row + 1) * cellSize - b;
    final (nw, ne, se, sw) = _tileCornerRounding(row, col, insets);
    final path = Path();
    path.moveTo(left + _cornerOffset(nw, k), top);
    _emitTileCorner(
      path,
      rounds: ne,
      approaching: Offset(right - _cornerOffset(ne, k), top),
      corner: Offset(right, top),
      arcTo: Offset(right, top + k),
    );
    _emitTileCorner(
      path,
      rounds: se,
      approaching: Offset(right, bottom - _cornerOffset(se, k)),
      corner: Offset(right, bottom),
      arcTo: Offset(right - k, bottom),
    );
    _emitTileCorner(
      path,
      rounds: sw,
      approaching: Offset(left + _cornerOffset(sw, k), bottom),
      corner: Offset(left, bottom),
      arcTo: Offset(left, bottom - k),
    );
    _emitTileCorner(
      path,
      rounds: nw,
      approaching: Offset(left, top + _cornerOffset(nw, k)),
      corner: Offset(left, top),
      arcTo: Offset(left + k, top),
    );
    path.close();
    return path;
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

  /// The K-offset along an edge when a corner rounds, zero otherwise.
  double _cornerOffset(bool rounds, double k) => rounds ? k : 0.0;

  /// Emits one clockwise tile corner: `lineTo` the k-shortened approach
  /// point, then the corner itself — a quadratic K-round to [arcTo] when
  /// [rounds], a plain point in the exact corner otherwise.
  void _emitTileCorner(
    Path path, {
    required bool rounds,
    required Offset approaching,
    required Offset corner,
    required Offset arcTo,
  }) {
    path.lineTo(approaching.dx, approaching.dy);
    if (rounds) {
      path.quadraticBezierTo(corner.dx, corner.dy, arcTo.dx, arcTo.dy);
    } else {
      path.lineTo(corner.dx, corner.dy);
    }
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
