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
          // Anchor cell of each room (top-left-most, victim cell excluded):
          // carries the number badge shown in the legend.
          final anchors = <Pos>{
            for (final room in widget.caseData.rooms)
              ([...room.cells]..sort(
                    (a, b) => a.row != b.row ? a.row - b.row : a.col - b.col,
                  ))
                  .firstWhere((cell) => cell != widget.caseData.victimPos),
          };

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
                          roomNumber: anchors.contains((row: row, col: col))
                              ? widget.caseData.rooms.indexWhere(
                                      (r) => r.contains((row: row, col: col)),
                                    ) +
                                    1
                              : null,
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
    String? suspectIdHere;
    for (final entry in placed.entries) {
      if (entry.value == pos) {
        suspectIdHere = entry.key;
        break;
      }
    }
    final suspectIndexHere = suspectIdHere == null
        ? null
        : c.suspects.indexWhere((s) => s.id == suspectIdHere);
    final hasX = xMarks.contains(pos);
    final objectHere = c.objects.where((o) => o.pos == pos).toList();
    final selectedHere =
        suspectIdHere != null && suspectIdHere == selectedSuspectId;

    final rowBlocked = placed.values.any((p) => p.row == pos.row);
    final colBlocked = placed.values.any((p) => p.col == pos.col);

    final tokens = SkinScope.maybeOf(context);
    final cartoon = tokens != null && tokens.solidRooms;

    final scheme = Theme.of(context).colorScheme;
    Color? cellFill;
    Border? cellBorder;
    if (cartoon) {
      // Solid rooms: SkinRoomPainter paints the tints and boundary-only
      // mortar beneath the cells; cells keep only state overlays (issue 23).
      if (isVictim) {
        cellFill = tokens.victimFill;
      } else if (rowBlocked || colBlocked) {
        cellFill = tokens.ink.withValues(alpha: 0.10);
      }
    } else {
      var fill = AppTheme.roomColors(g)[roomIndex].withValues(alpha: 0.55);
      if (isVictim) fill = scheme.errorContainer;
      if (rowBlocked || colBlocked) {
        fill = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.10), fill);
      }
      cellFill = fill;

      // Room boundary: thicker edge where the neighbor belongs to another
      // room.
      const thin = 0.5;
      const thick = 2.5;
      final northRoom = pos.row > 0
          ? roomOf(c.rooms, (row: pos.row - 1, col: pos.col))
          : null;
      final westRoom = pos.col > 0
          ? roomOf(c.rooms, (row: pos.row, col: pos.col - 1))
          : null;
      final southRoom = pos.row < g - 1
          ? roomOf(c.rooms, (row: pos.row + 1, col: pos.col))
          : null;
      final eastRoom = pos.col < g - 1
          ? roomOf(c.rooms, (row: pos.row, col: pos.col + 1))
          : null;
      cellBorder = Border(
        top: BorderSide(
          width: northRoom != room.id ? thick : thin,
          color: scheme.outline,
        ),
        left: BorderSide(
          width: westRoom != room.id ? thick : thin,
          color: scheme.outline,
        ),
        right: BorderSide(
          width: eastRoom != room.id ? thick : thin,
          color: scheme.outline,
        ),
        bottom: BorderSide(
          width: southRoom != room.id ? thick : thin,
          color: scheme.outline,
        ),
      );
    }

    final furnitureName = objectHere.isNotEmpty
        ? NameForms.forLocale(
            l10n.localeName,
            c,
          ).objectNom(objectHere.first.kind)
        : null;
    final blocking = objectHere.isNotEmpty && !objectHere.first.occupiable;
    var state = isVictim
        ? l10n.stateVictim
        : suspectIdHere != null
        ? c.suspects.firstWhere((s) => s.id == suspectIdHere).name
        : [
            if (hasX) l10n.stateExcluded,
            ?furnitureName,
            if (blocking) l10n.stateBlocked,
          ].join(' · ');
    if (state.isEmpty) state = l10n.stateEmpty;
    final label = l10n.cellSemantics(pos.row, pos.col, room.name, state);

    Widget roomBadge() => roomNumber == null
        ? const SizedBox.shrink()
        : Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                width: cartoon ? 20 : 16,
                height: cartoon ? 20 : 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cartoon
                      ? tokens.badge.background
                      : scheme.primaryContainer,
                  border: Border.all(
                    width: 1,
                    color: cartoon
                        ? tokens.badge.ink
                        : scheme.onPrimaryContainer,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$roomNumber',
                    style: TextStyle(
                      fontSize: cartoon ? 11 : 10,
                      fontWeight: FontWeight.bold,
                      color: cartoon
                          ? tokens.badge.ink
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          );

    Widget furniture(
      IconData icon, {
      double size = 28,
      Alignment alignment = Alignment.center,
    }) => ItemSprite(
      kind: objectHere.first.kind,
      size: size,
      opacity: blocking && !hasX ? 0.85 : 1.0,
    );

    Widget content;
    if (isVictim) {
      content = Semantics(
        label: '${l10n.victimLabel}: $label',
        child: Stack(
          children: [
            if (cartoon)
              // Striped victim cell per the cartoon mockups (issue 23).
              Positioned.fill(
                child: ClipRect(
                  child: CustomPaint(
                    painter: SkinVictimStripePainter(
                      color: tokens.victimStripeColor,
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
    } else {
      final itemIcon = objectHere.isNotEmpty
          ? objectIcon(objectHere.first.kind)
          : null;
      content = Stack(
        children: [
          roomBadge(),
          // Furniture renders under everything in the cell.
          if (itemIcon != null && (suspectIndexHere != null || hasX))
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: furniture(itemIcon, size: 12),
              ),
            ),
          if (suspectIndexHere != null)
            Center(
              child: Avatar(
                color: suspectColor(suspectIndexHere),
                selected: selectedHere,
                size: 30,
              ),
            )
          else if (hasX)
            Center(
              child: Icon(
                Icons.close,
                color: cartoon ? tokens.ink : scheme.error,
                size: 22,
              ),
            )
          else if (itemIcon != null)
            Center(child: furniture(itemIcon))
          else
            const SizedBox.shrink(),
        ],
      );
    }

    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCellTap(pos),
        child: Container(
          key: isVictim ? const Key('victim_cell') : null,
          decoration: cellFill == null && cellBorder == null
              ? null
              : BoxDecoration(color: cellFill, border: cellBorder),
          child: content,
        ),
      ),
    );
  }
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
        final north = _boundary(row, col, -1, 0);
        final south = _boundary(row, col, 1, 0);
        final west = _boundary(row, col, 0, -1);
        final east = _boundary(row, col, 0, 1);
        // Rounded only at outer room corners: both adjacent sides are
        // boundaries. Same-room neighbors keep square corners so their
        // fills meet seamlessly.
        final tl = north && west ? radius : 0.0;
        final tr = north && east ? radius : 0.0;
        final br = south && east ? radius : 0.0;
        final bl = south && west ? radius : 0.0;

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

        // Boundary lines hug the fill edge (inset half a line width) and
        // stop short of rounded corners where an arc takes over.
        if (north) {
          canvas.drawLine(
            Offset(rect.left + (tl > 0 ? radius : w / 2), rect.top + w / 2),
            Offset(rect.right - (tr > 0 ? radius : w / 2), rect.top + w / 2),
            mortar,
          );
        }
        if (west) {
          canvas.drawLine(
            Offset(rect.left + w / 2, rect.top + (tl > 0 ? radius : w / 2)),
            Offset(rect.left + w / 2, rect.bottom - (bl > 0 ? radius : w / 2)),
            mortar,
          );
        }
        if (south && row == gridSize - 1) {
          canvas.drawLine(
            Offset(rect.left + (bl > 0 ? radius : w / 2), rect.bottom - w / 2),
            Offset(rect.right - (br > 0 ? radius : w / 2), rect.bottom - w / 2),
            mortar,
          );
        }
        if (east && col == gridSize - 1) {
          canvas.drawLine(
            Offset(rect.right - w / 2, rect.top + (tr > 0 ? radius : w / 2)),
            Offset(rect.right - w / 2, rect.bottom - (br > 0 ? radius : w / 2)),
            mortar,
          );
        }

        // Corner arcs: the stroke follows the rounded fill corner.
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
    }
  }

  @override
  bool shouldRepaint(SkinRoomPainter oldDelegate) =>
      rooms != oldDelegate.rooms ||
      gridSize != oldDelegate.gridSize ||
      cellSize != oldDelegate.cellSize ||
      tints != oldDelegate.tints ||
      mortarColor != oldDelegate.mortarColor ||
      lineWidth != oldDelegate.lineWidth ||
      radius != oldDelegate.radius;
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
