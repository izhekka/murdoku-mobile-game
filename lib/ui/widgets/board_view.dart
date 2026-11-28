import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/avatar.dart';
import 'package:murdoku/ui/widgets/board_geometry.dart';
import 'package:murdoku/ui/widgets/board_painters.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';

// Pure-move split (issue 105): board_geometry.dart (grid-space outline
// tracing and tile insets) and board_painters.dart (skin painters) keep the
// public API on this library unchanged for callers that import board_view.
export 'board_geometry.dart';
export 'board_painters.dart';

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

  /// Classic per-cell fill: room tint, victim fill, occupancy blend. The
  /// victim fill is the issue-102 pair (light: the scheme error — the
  /// chalk sprite reads 5.5:1 vs it vs 1.11:1 against the old container;
  /// dark: the container, unchanged at 8.0:1) — the same mapping
  /// skinTokensFor(classic) carries in [SkinTokens.victimFill].
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
    if (isVictim) {
      fill = scheme.brightness == Brightness.dark
          ? scheme.errorContainer
          : scheme.error;
    }
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
    final underlay = _furnitureUnderlay(objectHere, itemIcon, suspectIndexHere);
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
  ) {
    if (itemIcon == null) return null;
    if (suspectIndexHere == null) return null;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _furnitureSprite(objectHere.first.kind, 12),
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
        child: _furnitureSprite(objectHere.first.kind, furnitureSize),
      );
    }
    return const SizedBox.shrink();
  }

  /// The furniture sprite at full opacity: the ink recolor (issue 100)
  /// gives it its designed contrast, and the blocked row/col overlay
  /// (issue 82/83 fill) carries the blocked-cell signal — the old 0.85
  /// dimming broke the 3:1 bar for the light ink on classic dark
  /// (combined overlay×dimmed pair measured 2.85:1, review round #100).
  Widget _furnitureSprite(ObjectKind kind, double size) =>
      ItemSprite(kind: kind, size: size);
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
