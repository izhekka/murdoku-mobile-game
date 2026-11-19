import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'avatar.dart';

/// Modal accuse sheet: every suspect as a card; eliminated suspects are
/// struck through and disabled. Pops with the accused suspect's id.
class AccuseSheet extends StatelessWidget {
  const AccuseSheet({
    super.key,
    required this.caseData,
    required this.eliminatedSuspects,
  });

  final CaseData caseData;
  final Set<String> eliminatedSuspects;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.accuseTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < caseData.suspects.length; i++)
                    _accuseTile(context, i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accuseTile(BuildContext context, int index) {
    final l10n = AppLocalizations.of(context)!;
    final suspect = caseData.suspects[index];
    final eliminated = eliminatedSuspects.contains(suspect.id);
    return ListTile(
      enabled: !eliminated,
      leading: Avatar(color: suspectColor(index), selected: false, size: 32),
      title: Text(
        suspect.name,
        style: eliminated
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Theme.of(context).colorScheme.outline,
              )
            : null,
      ),
      subtitle: eliminated ? Text(l10n.stateExcluded) : null,
      onTap: () => Navigator.of(context).pop(suspect.id),
    );
  }
}
