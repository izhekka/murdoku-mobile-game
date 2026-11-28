import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';

/// Opens the per-case legend: room color swatches with names, and every item
/// kind appearing in the case with its name and occupiability hint.
Future<void> showLegendSheet(BuildContext context, CaseData caseData) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => LegendSheet(caseData: caseData),
  );
}

class LegendSheet extends StatelessWidget {
  const LegendSheet({super.key, required this.caseData});

  final CaseData caseData;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, caseData);
    final g = caseData.gridSize;
    final tokens = SkinScope.maybeOf(context);
    final cartoon = tokens != null && tokens.isCartoon;
    final roomColors = _roomColors(cartoon, tokens, g);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.legendTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Issue 109: same wide breakpoint as the game screen —
                    // landscape shows the rooms column left of the items
                    // column; portrait keeps today's stacked order.
                    final roomsColumn = Column(
                      key: const Key('legend_rooms'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l10n.legendRooms,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        ..._roomTiles(
                          l10n,
                          names,
                          cartoon,
                          tokens,
                          scheme,
                          roomColors,
                        ),
                      ],
                    );
                    final itemsColumn = Column(
                      key: const Key('legend_items'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l10n.legendItems,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        ..._itemTiles(context, l10n, names),
                      ],
                    );
                    if (constraints.maxWidth >= 600) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: roomsColumn),
                          const SizedBox(width: 16),
                          Expanded(child: itemsColumn),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        roomsColumn,
                        const SizedBox(height: 8),
                        itemsColumn,
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The room swatch colors: skin tints on cartoon skins, the scheme
  /// palette for classic.
  List<Color> _roomColors(bool cartoon, SkinTokens? tokens, int g) => cartoon
      ? List.generate(g, (i) => tokens!.roomTints[i % tokens.roomTints.length])
      : AppTheme.roomColors(g);

  /// One compact numbered-swatch row per room, in board order (issue 109:
  /// ~28px rows instead of ~56px ListTiles, same content).
  List<Widget> _roomTiles(
    AppLocalizations l10n,
    NameForms names,
    bool cartoon,
    SkinTokens? tokens,
    ColorScheme scheme,
    List<Color> roomColors,
  ) => [
    for (var i = 0; i < caseData.rooms.length; i++)
      Padding(
        key: ValueKey('legend_room_$i'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            _roomSwatch(i, cartoon, tokens, scheme, roomColors),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${i + 1} — ${names.roomNom(caseData.rooms[i].id)}'),
            ),
          ],
        ),
      ),
  ];

  /// The colored square with the room number: solid tint + mortar border on
  /// cartoon skins (the board's room blocks, issue 23); the alpha-0.55
  /// scheme swatch on classic.
  Container _roomSwatch(
    int i,
    bool cartoon,
    SkinTokens? tokens,
    ColorScheme scheme,
    List<Color> roomColors,
  ) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: cartoon ? roomColors[i] : roomColors[i].withValues(alpha: 0.55),
        border: Border.all(
          width: 2,
          color: cartoon ? tokens!.mortarColor : scheme.outline,
        ),
        borderRadius: BorderRadius.circular(cartoon ? 6 : 4),
      ),
      child: Center(
        child: Text(
          '${i + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: cartoon ? tokens!.ink : scheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// One compact row per distinct item kind in the case, in first-appearance
  /// order, with its name and occupiability hint (issue 109).
  List<Widget> _itemTiles(
    BuildContext context,
    AppLocalizations l10n,
    NameForms names,
  ) => [
    for (final kind in _seenKinds())
      Padding(
        key: ValueKey('legend_item_${kind.name}'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            // 28 keeps the sprite's 1.35 paint box at ~38px so the two-line
            // row stays <= 44px (issue 109 compaction).
            ItemSprite(kind: kind, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(names.objectNom(kind)),
                  Text(
                    kindOccupiable(kind)
                        ? l10n.legendOccupiable
                        : l10n.stateBlocked,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
  ];

  /// The distinct item kinds appearing in the case, in first-appearance
  /// order.
  List<ObjectKind> _seenKinds() {
    final seenKinds = <ObjectKind>[];
    for (final item in caseData.objects) {
      if (!seenKinds.contains(item.kind)) seenKinds.add(item.kind);
    }
    return seenKinds;
  }
}
