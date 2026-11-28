import 'package:murdoku/domain/models.dart';

/// Grid-space board geometry shared by the board view and the skin painters:
/// room outline tracing, per-tile wall insets and tile-corner rounding.
/// All of this operates in grid vertices/cells — it renders nothing itself.

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
