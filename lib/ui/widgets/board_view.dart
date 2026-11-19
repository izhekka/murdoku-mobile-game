import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../domain/localized_names.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'avatar.dart';
import 'item_sprite.dart';

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
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          final cell = side / g;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _lastDragCell = null;
              _fireDrag(details.localPosition, cell, g);
            },
            onPanUpdate: (details) =>
                _fireDrag(details.localPosition, cell, g),
            child: SizedBox(
              key: const Key('board_view'),
              width: side,
              height: side,
              child: Stack(
                children: [
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
  });

  final CaseData caseData;
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

    final scheme = Theme.of(context).colorScheme;
    var fill = AppTheme.roomColors(g)[roomIndex].withValues(alpha: 0.35);
    if (isVictim) fill = scheme.errorContainer;
    if (rowBlocked || colBlocked) {
      fill = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.10), fill);
    }

    // Room boundary: thicker edge where the neighbor belongs to another room.
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
    final border = Border(
      top: BorderSide(
          width: northRoom != room.id ? thick : thin, color: scheme.outline),
      left: BorderSide(
          width: westRoom != room.id ? thick : thin, color: scheme.outline),
      right: BorderSide(
          width: eastRoom != room.id ? thick : thin, color: scheme.outline),
      bottom: BorderSide(
          width: southRoom != room.id ? thick : thin, color: scheme.outline),
    );

    final furnitureName = objectHere.isNotEmpty
        ? NameForms.forLocale(l10n.localeName, c).objectNom(objectHere.first.kind)
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

    Widget furniture(IconData icon,
            {double size = 20, Alignment alignment = Alignment.center}) =>
        ItemSprite(
          kind: objectHere.first.kind,
          size: size,
          opacity: blocking && !hasX ? 0.85 : 1.0,
        );

    Widget content;
    if (isVictim) {
      content = Semantics(
        label: '${l10n.victimLabel}: $label',
        child: Center(
          child: Text(
            'V',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      );
    } else {
      final itemIcon =
          objectHere.isNotEmpty ? objectIcon(objectHere.first.kind) : null;
      content = Stack(
        children: [
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
              child: Icon(Icons.close, color: scheme.error, size: 22),
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
          decoration: BoxDecoration(color: fill, border: border),
          child: content,
        ),
      ),
    );
  }
}
