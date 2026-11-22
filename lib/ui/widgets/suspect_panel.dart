import 'dart:math' as math;

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
      names.objectPrep(c.objects.firstWhere((o) => o.id == objectId).kind);

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

/// The suspects panel: a 3x2 grid of compact cards on phones (tall enough to
/// show each card's full clue text, uncapped), a vertical column on wide
/// layouts. Wherever the host leaves the height loose, cards grow to fit
/// their full clue text instead of clipping it.
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
    final clueTextsBySuspect = <String, List<String>>{
      for (final entry in cluesBySuspect.entries)
        entry.key: [
          for (final clue in entry.value)
            describeClue(clue, caseData, l10n, names),
        ],
    };

    final cards = [
      for (var i = 0; i < caseData.suspects.length; i++)
        _SuspectCard(
          suspect: caseData.suspects[i],
          displayName: names.nom(caseData.suspects[i].id),
          color: suspectColor(i),
          clueTexts:
              clueTextsBySuspect[caseData.suspects[i].id] ?? const <String>[],
          selected: caseData.suspects[i].id == selectedSuspectId,
          isPlaced: placed.containsKey(caseData.suspects[i].id),
          onTap: () => onSuspectTap(caseData.suspects[i].id),
        ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 600) {
        // Wide column of cards: each card sizes itself to its content
        // instead of a pinned 150px height, so longer clue text (or large
        // text scale) never clips (UX-9).
        return ListView(
          children: [
            for (final card in cards) IntrinsicHeight(child: card),
          ],
        );
      }
      const columns = 3;
      const hPad = 4.0;
      const spacing = 4.0;
      const rows = 2;
      final cardWidth =
          (constraints.maxWidth - 2 * hPad - (columns - 1) * spacing) / columns;
      // Default card proportions ~1.05; when the host pins a tight height
      // (the game screen's fixed panel slot), size the two rows to fill the
      // slot exactly so nothing clips and no dead space is left.
      var rowHeight = cardWidth / 1.05;
      if (constraints.maxHeight.isFinite &&
          constraints.maxHeight == constraints.minHeight) {
        rowHeight = (constraints.maxHeight - 2 * hPad - (rows - 1) * spacing) /
            rows;
      } else if (constraints.maxWidth.isFinite) {
        // Loose height (the wide layout's 300px side slot): grow the rows to
        // the tallest card's full content instead of pinning ~1.05-proportion
        // tiles that clip long clue text (UX-9).
        rowHeight = math.max(
          rowHeight,
          _contentRowHeight(
              context, cardWidth, clueTextsBySuspect, names.nom),
        );
      }
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: caseData.suspects.length <= 6
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        childAspectRatio: cardWidth / rowHeight,
        padding: const EdgeInsets.all(hPad),
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        children: [
          ...cards,
          const _EmptySlot(),
        ],
      );
    });
  }

  /// Minimum row height that fits every card's full content (name row plus
  /// all clue lines at the card's text width), measured with the same style
  /// and text scale the cards render with. Used when the host leaves the
  /// height loose: cards grow instead of clipping text (UX-9).
  double _contentRowHeight(
    BuildContext context,
    double cardWidth,
    Map<String, List<String>> clueTextsBySuspect,
    String Function(String) nameOf,
  ) {
    final base = DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Card insets: 4 outer padding + 8 container padding + 2 border per side.
    final textWidth = math.max(cardWidth - 2 * (4 + 8 + 2), 1.0);
    // The name row's text width: avatar (24) plus its 6px gap; placed cards
    // narrow it further with the 18px check icon, but names are short and
    // the avatar floors the row height in the common case.
    final nameWidth = math.max(textWidth - 24 - 6, 1.0);

    double measure(String text, TextStyle? style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: width);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var maxHeight = 0.0;
    for (final suspect in caseData.suspects) {
      final nameHeight =
          measure(nameOf(suspect.id), theme.textTheme.titleSmall, nameWidth);
      final joined =
          (clueTextsBySuspect[suspect.id] ?? const <String>[]).join('\n');
      final clueHeight = joined.isEmpty
          ? 0.0
          : measure(joined, theme.textTheme.bodySmall, textWidth);
      // 2 * (4 outer padding + 8 container padding + 2 border) + name row
      // (the 24dp avatar floors its height) + 4 gap + clue text block.
      final cardHeight = 2 * 14 + math.max(24.0, nameHeight) + 4 + clueHeight;
      maxHeight = math.max(maxHeight, cardHeight);
    }
    return maxHeight;
  }
}

/// Fills the sixth grid slot when the case has 5 suspects.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }
}

class _SuspectCard extends StatelessWidget {
  const _SuspectCard({
    required this.suspect,
    required this.displayName,
    required this.color,
    required this.clueTexts,
    required this.selected,
    required this.isPlaced,
    required this.onTap,
  });

  final Suspect suspect;
  final String displayName;
  final Color color;
  final List<String> clueTexts;
  final bool selected;
  final bool isPlaced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a11yLabel = clueTexts.isEmpty
        ? '$displayName.'
        : '$displayName. ${clueTexts.first}';
    return Semantics(
      button: true,
      label: a11yLabel,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
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
                    Avatar(color: color, selected: selected, size: 24),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayName,
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
                if (selected)
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
                  )
                else
                  Expanded(
                    child: Text(
                      clueTexts.join('\n'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
