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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        l10n.legendItems,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ..._itemTiles(context, l10n, names),
                  ],
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

  /// One numbered swatch tile per room, in board order.
  List<ListTile> _roomTiles(
    AppLocalizations l10n,
    NameForms names,
    bool cartoon,
    SkinTokens? tokens,
    ColorScheme scheme,
    List<Color> roomColors,
  ) => [
    for (var i = 0; i < caseData.rooms.length; i++)
      ListTile(
        leading: _roomSwatch(i, cartoon, tokens, scheme, roomColors),
        title: Text('${i + 1} — ${names.roomNom(caseData.rooms[i].id)}'),
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

  /// One tile per distinct item kind in the case, in first-appearance
  /// order, with its name and occupiability hint.
  List<ListTile> _itemTiles(
    BuildContext context,
    AppLocalizations l10n,
    NameForms names,
  ) => [
    for (final kind in _seenKinds())
      ListTile(
        leading: ItemSprite(kind: kind, size: 30),
        title: Text(names.objectNom(kind)),
        subtitle: Text(
          kindOccupiable(kind) ? l10n.legendOccupiable : l10n.stateBlocked,
          style: Theme.of(context).textTheme.bodySmall,
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
