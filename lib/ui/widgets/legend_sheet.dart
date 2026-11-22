import 'package:material_ui/material_ui.dart';

import '../../core/skins.dart';
import '../../core/theme.dart';
import '../../domain/localized_names.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'item_sprite.dart';

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
    final roomColors = cartoon
        ? List.generate(g, (i) => tokens.roomTints[i % tokens.roomTints.length])
        : AppTheme.roomColors(g);
    final scheme = Theme.of(context).colorScheme;
    // One entry per distinct item kind, in first-appearance order.
    final seenKinds = <ObjectKind>[];
    for (final item in caseData.objects) {
      if (!seenKinds.contains(item.kind)) seenKinds.add(item.kind);
    }

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
                    child: Text(l10n.legendRooms,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (var i = 0; i < caseData.rooms.length; i++)
                    ListTile(
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          // Cartoon skins: solid tint + mortar border, the
                          // board's room blocks (issue 23). Classic: the
                          // alpha-0.55 scheme swatch.
                          color: cartoon
                              ? roomColors[i]
                              : roomColors[i].withValues(alpha: 0.55),
                          border: Border.all(
                              width: 2,
                              color: cartoon
                                  ? tokens.mortarColor
                                  : scheme.outline),
                          borderRadius:
                              BorderRadius.circular(cartoon ? 6 : 4),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cartoon ? tokens.ink : scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                          '${i + 1} — ${names.roomNom(caseData.rooms[i].id)}'),
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l10n.legendItems,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final kind in seenKinds)
                    ListTile(
                      leading: ItemSprite(kind: kind, size: 30),
                      title: Text(names.objectNom(kind)),
                      subtitle: Text(
                        kindOccupiable(kind)
                            ? l10n.legendOccupiable
                            : l10n.stateBlocked,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
