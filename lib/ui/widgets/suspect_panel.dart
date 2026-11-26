import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/avatar.dart';

/// Test handle for the panel's header row (issue 27).
const Key suspectsPanelHeaderKey = Key('suspects_panel_header');

/// The narrow grid's geometry shared by the row-height math and the
/// layout-time pinned split (issue 39): 3 columns, 4px padding on the grid
/// edges, 4px gutters between tiles.
const int _gridColumns = 3;
const double _gridHPad = 4.0;
const double _gridSpacing = 4.0;

/// The positive sentence when [negated] is false, the negated one otherwise.
/// Both strings are built eagerly; the l10n templates are pure.
String _either(bool negated, String positive, String negatedForm) =>
    negated ? negatedForm : positive;

/// The nominative form of a suspect or the victim.
String _nameOf(String id, NameForms names) =>
    id == victimId ? names.victimNom() : names.nom(id);

/// The genitive form of a suspect or the victim (direction/beside targets).
String _targetOf(String id, NameForms names) =>
    id == victimId ? names.victimGen() : names.gen(id);

/// The localized compass name for a direction clue.
String _dirName(Direction d, AppLocalizations l10n) => switch (d) {
  Direction.north => l10n.dirNorth,
  Direction.south => l10n.dirSouth,
  Direction.east => l10n.dirEast,
  Direction.west => l10n.dirWest,
};

/// Pure clue -> sentence rendering per the spec's wording table (positive and
/// negated forms). [names] resolves locale- and grammar-appropriate forms:
/// genitive for direction/beside targets, nominative for same-row/col
/// targets, full prepositional room phrases in ru. The card owner's name is
/// never in the sentence (issue 89) — the card header and the Semantics
/// label carry it.
String describeClue(
  Clue clue,
  CaseData c,
  AppLocalizations l10n,
  NameForms names,
) {
  if (clue is InRoom) {
    final room = names.roomPrep(clue.roomId);
    return _either(
      clue.negated,
      l10n.clueInRoom(room),
      l10n.clueInRoomNot(room),
    );
  }
  if (clue is BesideObject) {
    final objectName = names.objectPrep(
      c.objects.firstWhere((o) => o.id == clue.objectId).kind,
    );
    return _either(
      clue.negated,
      l10n.clueBesideObject(objectName),
      l10n.clueBesideObjectNot(objectName),
    );
  }
  return _targetClueSentence(clue, l10n, names);
}

/// Sentences for the four target-bearing clue kinds; same-row/col targets
/// take the nominative form, direction/beside targets the genitive.
String _targetClueSentence(Clue clue, AppLocalizations l10n, NameForms names) {
  if (clue is Beside) {
    final target = _targetOf(clue.targetId, names);
    return _either(
      clue.negated,
      l10n.clueBeside(target),
      l10n.clueBesideNot(target),
    );
  }
  if (clue is DirectionClue) {
    return _directionSentence(clue, l10n, names);
  }
  return _sameRowColSentence(clue, l10n, names);
}

/// Direction sentences; targets take the genitive form.
String _directionSentence(
  DirectionClue clue,
  AppLocalizations l10n,
  NameForms names,
) {
  final dir = _dirName(clue.direction, l10n);
  final target = _targetOf(clue.targetId, names);
  return _either(
    clue.negated,
    l10n.clueDirection(dir, target),
    l10n.clueDirectionNot(dir, target),
  );
}

/// Same-row and same-col sentences; targets take the nominative form.
String _sameRowColSentence(Clue clue, AppLocalizations l10n, NameForms names) =>
    switch (clue) {
      SameRow(:final targetId) => _either(
        clue.negated,
        l10n.clueSameRow(_nameOf(targetId, names)),
        l10n.clueSameRowNot(_nameOf(targetId, names)),
      ),
      SameCol(:final targetId) => _either(
        clue.negated,
        l10n.clueSameCol(_nameOf(targetId, names)),
        l10n.clueSameColNot(_nameOf(targetId, names)),
      ),
      _ => throw ArgumentError('no sentence template for: $clue'),
    };

/// Debug-mode guard (issue 59): the panel derives every card size from the
/// incoming width, so an unbounded-width host has no defined layout. Reject
/// it with one documented assertion instead of a NaN aspect ratio or a
/// generic flex/viewport error. Like Flutter's own unbounded-extent guards,
/// the check is a debug-mode assertion (compiled out in profile/release).
void _assertHostWidthIsFinite(BoxConstraints constraints) {
  assert(() {
    if (!constraints.maxWidth.isFinite) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'SuspectPanel was given an unbounded width constraint '
          '(maxWidth = ${constraints.maxWidth}).',
        ),
        ErrorDescription(
          'SuspectPanel sizes every card from the host width: the '
          'narrow layout divides the width into its grid columns and '
          'measures the clue text at the resulting card width. '
          'Without a finite width the tiles have an undefined size '
          '(an infinite card width would make the grid '
          'childAspectRatio NaN), so SuspectPanel requires a finite '
          'width constraint.',
        ),
        ErrorHint(
          'Wrap the panel in a width-bounding widget (e.g. SizedBox, '
          'ConstrainedBox, or Expanded inside a flex), or give the '
          'host a finite cross-axis extent.',
        ),
      ]);
    }
    return true;
  }());
}

/// The suspects panel: a 3x2 grid of compact cards on phones (tall enough to
/// show each card's full clue text, uncapped), a vertical column on wide
/// layouts. Wherever the host leaves the height loose, cards grow to fit
/// their full clue text instead of clipping it. In a pinned slot the rows
/// split the space under the header exactly, and the grid scrolls whenever
/// the grown rows cannot all fit (issue 39). Guest names never
/// ellipsize: they render at full size where they fit and scale down to
/// their row where they don't (issue 15).
///
/// The host must supply a finite width constraint — see
/// [_assertHostWidthIsFinite] (issue 59).
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
    final cardBorderWidth = skin != null && skin.isCartoon
        ? skin.card.borderWidth
        : 2.0;
    final clueTexts = _clueTextsBySuspect(l10n, names);
    final cards = _cards(names, clueTexts);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Issue 59: reject unbounded-width hosts before any width branch
        // below (see _assertHostWidthIsFinite).
        _assertHostWidthIsFinite(constraints);
        if (constraints.maxWidth >= 600) {
          // Wide column of cards: each card sizes itself to its content
          // instead of a pinned 150px height, so longer clue text (or large
          // text scale) never clips (UX-9). The header (issue 27) rides the
          // top of the list.
          return ListView(
            children: [
              const _SuspectsHeader(),
              for (final card in cards) IntrinsicHeight(child: card),
            ],
          );
        }
        return _narrowColumn(
          context,
          constraints,
          cards,
          clueTexts,
          names,
          cardBorderWidth,
          skin,
        );
      },
    );
  }

  /// Clue sentences grouped per suspect, in clue order.
  Map<String, List<String>> _clueTextsBySuspect(
    AppLocalizations l10n,
    NameForms names,
  ) {
    final cluesBySuspect = <String, List<Clue>>{};
    for (final clue in caseData.clues) {
      cluesBySuspect.putIfAbsent(clue.suspectId, () => []).add(clue);
    }
    return {
      for (final entry in cluesBySuspect.entries)
        entry.key: [
          for (final clue in entry.value)
            describeClue(clue, caseData, l10n, names),
        ],
    };
  }

  /// One card per suspect, in board order.
  List<_SuspectCard> _cards(
    NameForms names,
    Map<String, List<String>> clueTexts,
  ) => [
    for (var i = 0; i < caseData.suspects.length; i++)
      _SuspectCard(
        suspect: caseData.suspects[i],
        displayName: names.nom(caseData.suspects[i].id),
        color: suspectColor(i),
        clueTexts: clueTexts[caseData.suspects[i].id] ?? const <String>[],
        selected: caseData.suspects[i].id == selectedSuspectId,
        isPlaced: placed.containsKey(caseData.suspects[i].id),
        onTap: () => onSuspectTap(caseData.suspects[i].id),
      ),
  ];

  /// The narrow (below 600px) layout: header above the 3-column grid; the
  /// grid fills the pinned slot below the header, clamps to the space under
  /// the header when the host bounds the height, or shrink-wraps its grown
  /// rows otherwise (issue 39).
  Widget _narrowColumn(
    BuildContext context,
    BoxConstraints constraints,
    List<_SuspectCard> cards,
    Map<String, List<String>> clueTexts,
    NameForms names,
    double cardBorderWidth,
    SkinTokens? skin,
  ) {
    final cardWidth =
        (constraints.maxWidth -
            2 * _gridHPad -
            (_gridColumns - 1) * _gridSpacing) /
        _gridColumns;
    final grownRowHeight = _narrowRowHeight(
      context,
      constraints,
      cardWidth,
      clueTexts,
      names,
      cardBorderWidth,
      skin?.chip,
    );
    // Grid children, their real row count, and their ideal shrink-wrapped
    // height at the grown row height above: padding on both edges, every
    // grown row, and the gutters between them (issue 30's overflow
    // detection, now shared by the pinned branch's overflow check via the
    // layout-time slot compare — issue 39). The row count is the real grid
    // children's (issue 39). The decorative empty slot joins only when the
    // last row has a spare cell to fill: 5 suspects lay out 2 rows with the
    // slot in the sixth cell, 6 suspects lay out 2 full rows — appending the
    // slot to a full last row would open a lone decorative row that owns the
    // scroll end and clip the last suspect row at max scroll (issue 58).
    final children = caseData.suspects.length % _gridColumns != 0
        ? [...cards, const _EmptySlot()]
        : cards;
    final rows = (children.length / _gridColumns).ceil();
    final gridContentHeight =
        2 * _gridHPad + rows * grownRowHeight + (rows - 1) * _gridSpacing;
    GridView buildGrid({required bool scrollable, required double rowHeight}) =>
        GridView.count(
          crossAxisCount: _gridColumns,
          shrinkWrap: true,
          physics: _gridPhysics(scrollable: scrollable),
          childAspectRatio: cardWidth / rowHeight,
          padding: const EdgeInsets.all(_gridHPad),
          mainAxisSpacing: _gridSpacing,
          crossAxisSpacing: _gridSpacing,
          children: children,
        );
    final bounded = constraints.maxHeight.isFinite;
    final pinned = bounded && constraints.maxHeight == constraints.minHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: pinned ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const _SuspectsHeader(),
        _gridChild(
          pinned: pinned,
          bounded: bounded,
          rows: rows,
          gridContentHeight: gridContentHeight,
          grownRowHeight: grownRowHeight,
          buildGrid: buildGrid,
        ),
      ],
    );
  }

  /// The narrow branch's grown row height: default card proportions grown to
  /// the tallest card's full content instead of pinning tiles that clip long
  /// clue text (UX-9). The pinned host resolves the final tile height
  /// against the post-header slot at layout time (issue 39): this grown
  /// height is what the pinned grid scrolls to when the slot cannot show
  /// every row.
  double _narrowRowHeight(
    BuildContext context,
    BoxConstraints constraints,
    double cardWidth,
    Map<String, List<String>> clueTexts,
    NameForms names,
    double cardBorderWidth,
    SkinChip? chip,
  ) {
    final rowHeight = cardWidth / 1.05;
    if (constraints.maxWidth.isFinite) {
      return math.max(
        rowHeight,
        _contentRowHeight(
          context,
          cardWidth,
          clueTexts,
          names,
          cardBorderWidth,
          chip,
        ),
      );
    }
    return rowHeight;
  }

  /// Scroll physics for the suspect grid (issues 30/39): when the grown row
  /// heights exceed the grid's slot, the shrink-wrap viewport clamps and
  /// NeverScrollableScrollPhysics would leave the bottom-row cards unbuilt
  /// and unreachable — the callers detect that overflow (bounded-loose host:
  /// the Flexible's slot compare; pinned host: the post-header slot compare,
  /// issue 39) and switch to scrolling physics exactly on overflow. When
  /// the content fits, small cases keep the no-scroll grid; more suspects
  /// than the 3x2 grid shows keep the pre-existing scrollable physics.
  ScrollPhysics _gridPhysics({required bool scrollable}) =>
      scrollable || caseData.suspects.length > 6
      ? const ClampingScrollPhysics()
      : const NeverScrollableScrollPhysics();

  /// The grid's placement under the header (issue 27/30/39): filling the
  /// rest of a pinned slot exactly, clamped-and-scrolling on overflow inside
  /// a bounded slot, or shrink-wrapped when the height is unbounded. The
  /// pinned branch (issue 39) splits the post-header slot into the real
  /// [rows] when the grown rows fit it and switches to scrolling physics
  /// exactly like the bounded branch when they don't.
  Widget _gridChild({
    required bool pinned,
    required bool bounded,
    required int rows,
    required double gridContentHeight,
    required double grownRowHeight,
    required GridView Function({
      required bool scrollable,
      required double rowHeight,
    })
    buildGrid,
  }) {
    if (pinned) {
      return Expanded(
        child: LayoutBuilder(
          builder: (context, slot) {
            // Issue 39: the rows split the slot below the header — the real
            // children count, not a hard-coded 2 — and on overflow the grid
            // keeps the grown rows and scrolls, the loose branch's behavior.
            final fillRowHeight =
                (slot.maxHeight - 2 * _gridHPad - (rows - 1) * _gridSpacing) /
                rows;
            final fits = gridContentHeight <= slot.maxHeight + 0.5;
            return buildGrid(
              scrollable: !fits,
              rowHeight: fits ? fillRowHeight : grownRowHeight,
            );
          },
        ),
      );
    }
    if (bounded) {
      return Flexible(
        child: LayoutBuilder(
          builder: (context, slot) => buildGrid(
            scrollable: gridContentHeight > slot.maxHeight + 0.5,
            rowHeight: grownRowHeight,
          ),
        ),
      );
    }
    return buildGrid(scrollable: false, rowHeight: grownRowHeight);
  }

  /// Minimum row height that fits every card's full content (name row plus
  /// all clue lines at the card's text width), measured with the same style
  /// and text scale the cards render with. Used when the host leaves the
  /// height loose: cards grow instead of clipping text (UX-9). [chip] is the
  /// skin's clue-sentence gap token (issue 26; the pill is gone since issue
  /// 89), so each sentence measures at the card's full text width and only
  /// the token's gap joins them — exactly the structure the card renders.
  double _contentRowHeight(
    BuildContext context,
    double cardWidth,
    Map<String, List<String>> clueTextsBySuspect,
    NameForms names,
    double borderWidth,
    SkinChip? chip,
  ) {
    final base = DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Card insets: 4 outer padding + 8 container padding + border per side.
    final textWidth = math.max(cardWidth - 2 * (4 + 8 + borderWidth), 1.0);
    // The name row's text width: avatar (24) plus its 6px gap. The placed
    // check icon is a badge on the avatar's corner (issue 18), so placed and
    // unplaced rows share this width; scale-down names grow *smaller* in a
    // narrower row, so this bound yields the taller name row and the avatar
    // floors the height in the common case.
    final nameWidth = math.max(textWidth - 24 - 6, 1.0);

    var maxHeight = 0.0;
    for (final suspect in caseData.suspects) {
      final nameHeight = _fittedNameHeight(
        names.nom(suspect.id),
        theme.textTheme.titleSmall,
        base,
        scaler,
        direction,
        nameWidth,
      );
      final clueHeight = _clueBlockHeight(
        clueTextsBySuspect[suspect.id] ?? const <String>[],
        chip,
        theme,
        base,
        scaler,
        direction,
        textWidth,
      );
      // 2 * (4 outer padding + 8 container padding + border) + name row
      // (the 24dp avatar floors its height) + 4 gap + clue text block.
      final cardHeight =
          2 * (12 + borderWidth) + math.max(24.0, nameHeight) + 4 + clueHeight;
      maxHeight = math.max(maxHeight, cardHeight);
    }
    return maxHeight;
  }

  /// The clue text block's height at the card's text width: joined
  /// paragraph for classic, per-sentence gap arithmetic in chip mode
  /// (issue 26; sentences are bare Texts since issue 89) — exactly the
  /// structure the card renders.
  double _clueBlockHeight(
    List<String> texts,
    SkinChip? chip,
    ThemeData theme,
    TextStyle base,
    TextScaler scaler,
    TextDirection direction,
    double textWidth,
  ) {
    if (texts.isEmpty) return 0.0;
    if (chip == null) {
      return _measureText(
        texts.join('\n'),
        theme.textTheme.bodySmall,
        base,
        scaler,
        direction,
        textWidth,
      );
    }
    var clueHeight = 0.0;
    for (var i = 0; i < texts.length; i++) {
      if (i > 0) clueHeight += chip.gap;
      clueHeight += _measureText(
        texts[i],
        theme.textTheme.bodySmall,
        base,
        scaler,
        direction,
        textWidth,
      );
    }
    return clueHeight;
  }
}

/// The panel's title header (issue 27): the localized «Подозреваемые» /
/// "Suspects" row above the suspect grid, present in every skin per the
/// approved mockups. The comic skin renders it uppercase through its
/// [SkinTokens.panelHeaderUppercase] token; classic and the other cartoon
/// skins keep title case. ScaleDown keeps the row on one line inside the
/// 320px viewport at textScale 2.0 — uppercase Cyrillic is the widest case.
class _SuspectsHeader extends StatelessWidget {
  const _SuspectsHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = SkinScope.maybeOf(context);
    return Semantics(
      header: true,
      key: suspectsPanelHeaderKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _headerText(l10n, tokens),
            style: _headerStyle(Theme.of(context), tokens),
          ),
        ),
      ),
    );
  }

  /// The localized «Подозреваемые» / "Suspects" row text, uppercased in the
  /// skins whose [SkinTokens.panelHeaderUppercase] token says so (issue 27).
  String _headerText(AppLocalizations l10n, SkinTokens? tokens) {
    return tokens?.panelHeaderUppercase ?? false
        ? l10n.suspectsHeader.toUpperCase()
        : l10n.suspectsHeader;
  }

  /// Comic skins render the header in their [SkinTokens.ink]; classic and the
  /// other cartoon skins keep the color scheme's on-surface tone.
  TextStyle? _headerStyle(ThemeData theme, SkinTokens? tokens) {
    final cartoon = tokens != null && tokens.isCartoon;
    return theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: cartoon ? tokens.ink : theme.colorScheme.onSurface,
    );
  }
}

/// Decorates the spare cell of the narrow grid's last row (the sixth slot
/// of a 5-suspect case, the cell after a seventh guest). Appended only when
/// the last row has an empty cell — never as a lone trailing row (issue 58).
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
    // Clue sentences (issues 26/89): a non-null chip token renders every
    // clue sentence as a bare gap-separated Text; null — classic and bare
    // harnesses — keeps the pre-existing joined paragraph rendering below.
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
            decoration: _cardDecoration(scheme, tokens, cartoon),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _nameRow(context, scheme),
                const SizedBox(height: 4),
                _clueArea(context, chip),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The card surface: cartoon token card or the classic scheme container.
  BoxDecoration _cardDecoration(
    ColorScheme scheme,
    SkinTokens? tokens,
    bool cartoon,
  ) => cartoon ? _cartoonDecoration(tokens!) : _classicDecoration(scheme);

  /// The cartoon token card; selection rides the suspect's own color:
  /// comic's card border is already the ink color, so an ink outline could
  /// not show selection.
  BoxDecoration _cartoonDecoration(SkinTokens tokens) => BoxDecoration(
    borderRadius: BorderRadius.circular(tokens.card.radius),
    color: tokens.card.background,
    border: Border.all(
      color: selected ? color : tokens.card.borderColor,
      width: selected
          ? math.max(tokens.card.borderWidth, 3)
          : tokens.card.borderWidth,
    ),
    boxShadow: [tokens.card.shadow],
  );

  /// The classic scheme container with the selection outline.
  BoxDecoration _classicDecoration(ColorScheme scheme) => BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    color: selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest,
    border: Border.all(
      color: selected ? scheme.primary : Colors.transparent,
      width: 2,
    ),
  );

  /// The avatar + name row (issues 15/18): the placed check icon is a badge
  /// on the avatar's corner so placed and unplaced rows share the same
  /// ~36.7px name slot; the name scales down instead of truncating.
  Widget _nameRow(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
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
                  child: Icon(
                    Icons.check_circle,
                    size: 12,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Name renders in full on the wide side panel (issue 15): no
        // ellipsis cap — the name lays out at its natural width and scales
        // down to fit the row, so single-word names (which cannot wrap) are
        // never truncated. Where the name already fits (narrow phones),
        // scaleDown renders it at 1.0. With the placed check badged onto
        // the avatar (issue 18) this row keeps the same slot whether the
        // card is placed or not.
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
    );
  }

  /// The clue area: bare gap-separated sentence column in chip mode
  /// (issues 26/89), scrollable plain column on the expanded (selected)
  /// card, joined paragraph otherwise.
  Widget _clueArea(BuildContext context, SkinChip? chip) {
    if (chip != null) {
      // Each clue sentence as a bare gap-separated Text (issue 89), selected
      // and unselected alike. The scroll view is the same escape hatch the
      // selected card already had: when the host pins a slot shorter than
      // the content (narrow layout), the sentences scroll instead of
      // throwing a RenderFlex overflow; the row-height math grows the rows
      // wherever the host leaves the height loose, so this scrolls only
      // when there is genuinely no room (UX-9).
      return Expanded(
        child: SingleChildScrollView(child: _chipColumn(context, chip)),
      );
    }
    if (selected) {
      return Expanded(
        child: SingleChildScrollView(child: _plainColumn(context)),
      );
    }
    return Expanded(
      child: Text(
        clueTexts.join('\n'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// One bare clue sentence per line (issue 89): the rounded pill is gone,
  /// the token's gap separates the sentences, and the texts left-align with
  /// the name row.
  Widget _chipColumn(BuildContext context, SkinChip chip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, text) in clueTexts.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : chip.gap),
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );

  /// The selected card's clue column (issue 26's escape hatch).
  Widget _plainColumn(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final text in clueTexts)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
}

/// Measures [text]'s wrapped height at [width] with the card's merged style.
double _measureText(
  String text,
  TextStyle? style,
  TextStyle base,
  TextScaler scaler,
  TextDirection direction,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: base.merge(style)),
    textDirection: direction,
    textScaler: scaler,
  )..layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Scale-down-to-fit name row height (issue 15): the name lays out at its
/// natural width on one line, then shrinks to the row width — the row
/// height is the scaled one-line height, floored by the 24dp avatar.
double _fittedNameHeight(
  String text,
  TextStyle? style,
  TextStyle base,
  TextScaler scaler,
  TextDirection direction,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: base.merge(style)),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  final naturalWidth = painter.width;
  final naturalHeight = painter.height;
  painter.dispose();
  final scale = math.min(1.0, width / math.max(naturalWidth, 1.0));
  return naturalHeight * scale;
}
