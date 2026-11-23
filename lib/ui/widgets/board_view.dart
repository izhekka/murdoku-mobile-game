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
    final cartoon = tokens != null && tokens.solidRooms;
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
                  if (cartoon)
                    Positioned(
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
                    ),
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
                          pos: (row: row, col: col),
                          roomNumber: _roomBadgeNumber(
                            anchors,
                            widget.caseData,
                            (row: row, col: col),
                          ),
                          placed: widget.placed,
                          xMarks: widget.xMarks,
                          selectedSuspectId: widget.selectedSuspectId,
                          onCellTap: widget.onCellTap,
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
    required this.pos,
    required this.placed,
    required this.xMarks,
    required this.selectedSuspectId,
    required this.onCellTap,
    this.roomNumber,
  });

  final CaseData caseData;
  final Pos pos;
  final Map<String, Pos> placed;
  final Set<Pos> xMarks;
  final String? selectedSuspectId;
  final void Function(Pos) onCellTap;
  final int? roomNumber;

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

    final content = isVictim
        ? _victimContent(l10n, label, scheme, tokens, cartoon)
        : _guestContent(
            c,
            suspectIdHere: suspectIdHere,
            hasX: hasX,
            objectHere: objectHere,
            selectedSuspectId: selectedSuspectId,
            roomNumber: roomNumber,
            scheme: scheme,
            tokens: tokens,
            cartoon: cartoon,
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

  /// Solid-room overlay fill: victim tint or the row/column occupancy
  /// overlay; null keeps the cell undecorated (the painter carries the tint).
  Color? _cartoonFill(
    SkinTokens tokens,
    bool isVictim,
    bool rowBlocked,
    bool colBlocked,
  ) {
    if (isVictim) return tokens.victimFill;
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

  /// The victim cell: striped cartoon backdrop under the chalk-outline image.
  Widget _victimContent(
    AppLocalizations l10n,
    String label,
    ColorScheme scheme,
    SkinTokens? tokens,
    bool cartoon,
  ) {
    return Semantics(
      label: '${l10n.victimLabel}: $label',
      child: Stack(
        children: [
          if (cartoon)
            // Striped victim cell per the cartoon mockups (issue 23).
            Positioned.fill(
              child: ClipRect(
                child: CustomPaint(
                  painter: SkinVictimStripePainter(
                    color: tokens!.victimStripeColor,
                  ),
                ),
              ),
            ),
          Center(
            child: Image.asset(
              'assets/items/victim.png',
              width: 40,
              height: 40,
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
        ],
      ),
    );
  }

  /// A non-victim cell: room badge, furniture underlay and the occupant.
  Widget _guestContent(
    CaseData c, {
    required String? suspectIdHere,
    required bool hasX,
    required List<ObjectDef> objectHere,
    required String? selectedSuspectId,
    required int? roomNumber,
    required ColorScheme scheme,
    required SkinTokens? tokens,
    required bool cartoon,
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
        _RoomBadge(
          roomNumber: roomNumber,
          tokens: tokens,
          scheme: scheme,
          cartoon: cartoon,
        ),
        // Furniture renders under everything in the cell.
        ?underlay,
        _occupant(
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
    bool cartoon,
  ) {
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
        child: _furnitureSprite(objectHere.first.kind, 28, dimmed: dimmed),
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

/// Paints the cartoon board's rooms as solid blocks (issue 23): a union of
/// per-cell fills rounded only at outer room corners, with boundary-only
/// mortar lines (north/west rules plus the outer south/east edges keep one
/// stroke per internal boundary) wrapping rounded corners in arcs. Classic
/// boards never use this painter.
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
    final fill = Paint();
    final mortar = Paint()
      ..color = mortarColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = lineWidth;

    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        final roomIndex = _roomIndexAt((row, col));
        if (roomIndex < 0) continue;
        final rect = Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          cellSize,
          cellSize,
        );
        _paintCell(canvas, fill, mortar, w, rect, roomIndex, row, col);
      }
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
