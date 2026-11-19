import 'package:material_ui/material_ui.dart';

import '../../domain/localized_names.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'avatar.dart';

/// Pure clue -> sentence rendering per the spec's wording table (positive and
/// negated forms). [names] resolves locale- and grammar-appropriate forms:
/// nominative for subjects, genitive for direction/beside targets, full
/// prepositional room phrases in ru.
String describeClue(
  Clue clue,
  CaseData c,
  AppLocalizations l10n,
  NameForms names,
) {
  String nameOf(String id) =>
      id == victimId ? names.victimNom() : names.nom(id);

  String targetOf(String id) =>
      id == victimId ? names.victimGen() : names.gen(id);

  String objectNameOf(String objectId) =>
      names.objectGen(c.objects.firstWhere((o) => o.id == objectId).kind);

  String dirName(Direction d) => switch (d) {
        Direction.north => l10n.dirNorth,
        Direction.south => l10n.dirSouth,
        Direction.east => l10n.dirEast,
        Direction.west => l10n.dirWest,
      };

  final name = nameOf(clue.suspectId);
  switch (clue) {
    case InRoom(:final roomId):
      final room = names.roomPrep(roomId);
      return clue.negated
          ? l10n.clueInRoomNot(name, room)
          : l10n.clueInRoom(name, room);
    case SameRow(:final targetId):
      final target = nameOf(targetId);
      return clue.negated
          ? l10n.clueSameRowNot(name, target)
          : l10n.clueSameRow(name, target);
    case SameCol(:final targetId):
      final target = nameOf(targetId);
      return clue.negated
          ? l10n.clueSameColNot(name, target)
          : l10n.clueSameCol(name, target);
    case DirectionClue(:final targetId, :final direction):
      final target = targetOf(targetId);
      final dir = dirName(direction);
      return clue.negated
          ? l10n.clueDirectionNot(name, dir, target)
          : l10n.clueDirection(name, dir, target);
    case Beside(:final targetId):
      final target = targetOf(targetId);
      return clue.negated
          ? l10n.clueBesideNot(name, target)
          : l10n.clueBeside(name, target);
    case BesideObject(:final objectId):
      final objectName = objectNameOf(objectId);
      return clue.negated
          ? l10n.clueBesideObjectNot(name, objectName)
          : l10n.clueBesideObject(name, objectName);
  }
}

/// The suspects bar: portrait, name and clue cards per suspect. A horizontal
/// scroll strip on phones, a vertical column on wide layouts.
class SuspectPanel extends StatelessWidget {
  const SuspectPanel({
    super.key,
    required this.caseData,
    required this.placed,
    required this.selectedSuspectId,
    required this.onSuspectTap,
  });

  final CaseData caseData;
  final Map<String, Pos> placed;
  final String? selectedSuspectId;
  final void Function(String) onSuspectTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, caseData);
    final cluesBySuspect = <String, List<Clue>>{};
    for (final clue in caseData.clues) {
      cluesBySuspect.putIfAbsent(clue.suspectId, () => []).add(clue);
    }

    final cards = [
      for (var i = 0; i < caseData.suspects.length; i++)
        _SuspectCard(
          suspect: caseData.suspects[i],
          color: suspectColor(i),
          clues: cluesBySuspect[caseData.suspects[i].id] ?? const [],
          clueTexts: [
            for (final clue in cluesBySuspect[caseData.suspects[i].id] ?? const <Clue>[])
              describeClue(clue, caseData, l10n, names),
          ],
          selected: caseData.suspects[i].id == selectedSuspectId,
          isPlaced: placed.containsKey(caseData.suspects[i].id),
          onTap: () => onSuspectTap(caseData.suspects[i].id),
        ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 600) {
        return ListView(
          children: [
            for (final card in cards)
              SizedBox(height: 150, width: double.infinity, child: card),
          ],
        );
      }
      return SizedBox(
        height: 150,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: cards,
        ),
      );
    });
  }
}

class _SuspectCard extends StatelessWidget {
  const _SuspectCard({
    required this.suspect,
    required this.color,
    required this.clues,
    required this.clueTexts,
    required this.selected,
    required this.isPlaced,
    required this.onTap,
  });

  final Suspect suspect;
  final Color color;
  final List<Clue> clues;
  final List<String> clueTexts;
  final bool selected;
  final bool isPlaced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(color: color, selected: selected, size: 32),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      suspect.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (isPlaced)
                    Icon(Icons.check_circle,
                        size: 18, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final text in clueTexts)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            text,
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
      ),
    );
  }
}
