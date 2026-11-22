import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/skins.dart';
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
/// their full clue text instead of clipping it. Guest names never
/// ellipsize: they render at full size where they fit and scale down to
/// their row where they don't (issue 15).
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
    // Border width of one card per side: the cartoon skins' token border
    // (issue 23), 2 for classic. The row-height math needs it to measure
    // the clue text at the card's real text width.
    final skin = SkinScope.maybeOf(context);
    final cardBorderWidth =
        skin != null && skin.isCartoon ? skin.card.borderWidth : 2.0;
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
        _contentRowHeight(context, cardWidth, clueTextsBySuspect, names.nom,
            cardBorderWidth, skin?.chip),
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
  /// height loose: cards grow instead of clipping text (UX-9). [chip] is the
  /// skin's clue-chip token (issue 26); when non-null each clue measures at
  /// the chip's inner width plus the chip's vertical padding and gaps, so
  /// the grown rows fit the rendered chips exactly.
  double _contentRowHeight(
    BuildContext context,
    double cardWidth,
    Map<String, List<String>> clueTextsBySuspect,
    String Function(String) nameOf,
    double borderWidth,
    SkinChip? chip,
  ) {
    final base = DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Card insets: 4 outer padding + 8 container padding + border per side.
    final textWidth = math.max(cardWidth - 2 * (4 + 8 + borderWidth), 1.0);
    // Chip inner width (issue 26): each clue sentence wraps inside the
    // chip's horizontal padding.
    final chipInnerWidth =
        chip == null ? textWidth : math.max(textWidth - chip.padding.horizontal, 1.0);
    // The name row's text width: avatar (24) plus its 6px gap. The placed
    // check icon is a badge on the avatar's corner (issue 18), so placed and
    // unplaced rows share this width; scale-down names grow *smaller* in a
    // narrower row, so this bound yields the taller name row and the avatar
    // floors the height in the common case.
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

    // Scale-down-to-fit name row (issue 15): the name lays out at its
    // natural width on one line, then shrinks to the row width — the row
    // height is the scaled one-line height, floored by the 24dp avatar.
    double fittedNameHeight(String text, TextStyle? style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: double.infinity);
      final naturalWidth = painter.width;
      final naturalHeight = painter.height;
      painter.dispose();
      final scale = math.min(1.0, width / math.max(naturalWidth, 1.0));
      return naturalHeight * scale;
    }

    var maxHeight = 0.0;
    for (final suspect in caseData.suspects) {
      final nameHeight = fittedNameHeight(
          nameOf(suspect.id), theme.textTheme.titleSmall, nameWidth);
      final texts =
          clueTextsBySuspect[suspect.id] ?? const <String>[];
      double clueHeight;
      if (texts.isEmpty) {
        clueHeight = 0.0;
      } else if (chip == null) {
        // Classic: the card renders the clues joined into one paragraph at
        // the card's text width.
        clueHeight =
            measure(texts.join('\n'), theme.textTheme.bodySmall, textWidth);
      } else {
        // Chip mode (issue 26): every clue is its own chip — the text wraps
        // at the chip's inner width, each chip adds its vertical padding,
        // and consecutive chips are separated by the token gap. Exactly the
        // structure the card's chip column renders.
        clueHeight = 0.0;
        for (var i = 0; i < texts.length; i++) {
          if (i > 0) clueHeight += chip.gap;
          clueHeight += measure(
                  texts[i], theme.textTheme.bodySmall, chipInnerWidth) +
              chip.padding.vertical;
        }
      }
      // 2 * (4 outer padding + 8 container padding + border) + name row
      // (the 24dp avatar floors its height) + 4 gap + clue text block.
      final cardHeight =
          2 * (12 + borderWidth) + math.max(24.0, nameHeight) + 4 + clueHeight;
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
    // Cartoon skins use the token card (issue 23): white card, skin border,
    // offset shadow; selection is a thicker ink outline. Classic keeps the
    // scheme styling.
    final tokens = SkinScope.maybeOf(context);
    final cartoon = tokens != null && tokens.isCartoon;
    // Clue chip (issue 26): a non-null chip token renders every clue
    // sentence in its own rounded chip (mockups); null — classic and bare
    // harnesses — keeps the pre-existing plain clue rendering below.
    final chip = cartoon ? tokens.chip : null;
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
            decoration: cartoon
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(tokens.card.radius),
                    color: tokens.card.background,
                    border: Border.all(
                      // Selection rides the suspect's own color: comic's
                      // card border is already the ink color, so an ink
                      // outline could not show selection.
                      color: selected ? color : tokens.card.borderColor,
                      width:
                          selected ? math.max(tokens.card.borderWidth, 3) : tokens.card.borderWidth,
                    ),
                    boxShadow: [tokens.card.shadow],
                  )
                : BoxDecoration(
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
                    // Placed marker (issue 18): the check icon rides the
                    // avatar's corner as a badge instead of taking an inline
                    // row slot — an inline 18px icon squeezed the placed name
                    // to ~18.7px at the 300px side panel, scaling the widest
                    // pool names ('Морган'/'Харпер') to ~0.37. Badged, the
                    // layout width stays exactly the avatar's 24dp (the badge
                    // paints past the stack bounds via Clip.none), so placed
                    // and unplaced rows share the same ~36.7px name slot in
                    // every layout; unplaced cards are untouched.
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Avatar(color: color, selected: selected, size: 24),
                          if (isPlaced)
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Icon(Icons.check_circle,
                                  size: 12, color: scheme.primary),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Name renders in full on the wide side panel (issue
                    // 15): no ellipsis cap — the name lays out at its
                    // natural width and scales down to fit the row, so
                    // single-word names (which cannot wrap) are never
                    // truncated. Where the name already fits (narrow
                    // phones), scaleDown renders it at 1.0. With the placed
                    // check badged onto the avatar (issue 18) this row keeps
                    // the same slot whether the card is placed or not.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (chip != null)
                  // Each clue sentence in its own rounded token chip (issue
                  // 26), selected and unselected alike. The scroll view is
                  // the same escape hatch the selected card already had:
                  // when the host pins a slot shorter than the content
                  // (narrow layout), the chips scroll instead of throwing a
                  // RenderFlex overflow; the row-height math below grows the
                  // rows wherever the host leaves the height loose, so this
                  // scrolls only when there is genuinely no room (UX-9).
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, text) in clueTexts.indexed)
                            Container(
                              margin: EdgeInsets.only(top: i == 0 ? 0 : chip.gap),
                              padding: chip.padding,
                              decoration: BoxDecoration(
                                color: chip.background,
                                borderRadius:
                                    BorderRadius.circular(chip.radius),
                              ),
                              child: Text(
                                text,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                else if (selected)
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
