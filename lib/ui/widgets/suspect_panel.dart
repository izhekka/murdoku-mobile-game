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
/// layout-time pinned split (issue 39): 3 columns on phones (2 in the
/// landscape game screen, issue 103), 4px padding on the grid edges, 4px
/// gutters between tiles.
const int _gridColumns = 3;
const int _landscapeGridColumns = 2;
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

/// The clue dash's font-size scale relative to the sentence style (issue
/// 104): every clue sentence's leading dash renders at ~0.75x the sentence
/// font size, in both locales and all four skins.
const double clueDashFontScale = 0.75;

/// The leading dash every clue-sentence template starts with (em-dash +
/// space, pinned by the arb files).
const String _clueDash = '— ';

/// One inline piece of a rendered clue sentence (issue 104): the leading
/// dash, plain words, or the room phrase that renders as a chip. [text]
/// pieces join back to the plain `describeClue` string losslessly — the
/// plain string stays the Semantics label.
sealed class ClueSegment {
  final String text;

  const ClueSegment(this.text);
}

/// The sentence's leading «— »; renders at [clueDashFontScale].
final class DashClueSegment extends ClueSegment {
  const DashClueSegment(super.text);
}

/// Plain sentence words at the sentence style.
final class PlainClueSegment extends ClueSegment {
  const PlainClueSegment(super.text);
}

/// The room phrase of an InRoom sentence; renders as a rounded chip filled
/// with the room's board tint. [roomIndex] is the room's index in
/// `caseData.rooms` — the same order the legend sheet and the board index
/// their tints by.
final class RoomClueSegment extends ClueSegment {
  final int roomIndex;

  const RoomClueSegment(super.text, this.roomIndex);
}

/// The InRoom sentence split: dash, optional plain prefix, the room segment
/// at [roomIndex], optional trailing plain — or null when [room] does not
/// occur in [plain] (defensive fallback to the plain segments).
List<ClueSegment>? _roomSentenceSegments(
  String plain,
  int dashLen,
  String room,
  int roomIndex,
) {
  final i = plain.indexOf(room, dashLen);
  if (i < 0) return null;
  return [
    if (dashLen > 0) DashClueSegment(_clueDash),
    if (i > dashLen) PlainClueSegment(plain.substring(dashLen, i)),
    RoomClueSegment(room, roomIndex),
    if (i + room.length < plain.length)
      PlainClueSegment(plain.substring(i + room.length)),
  ];
}

/// The clue sentence as inline segments (issue 104): [DashClueSegment] first
/// (every template starts with the dash), then — for InRoom sentences only —
/// the plain prefix (ru '' / en 'in the ' / negated 'не '/'not in the '), the
/// [RoomClueSegment] (full prepositional phrase in ru, bare name in en) and
/// the trailing plain segment; every other clue kind is dash + one plain
/// segment. Derived from the `describeClue` template result by locating the
/// room phrase — no arb wording is duplicated here, so template edits keep
/// the split correct.
List<ClueSegment> describeClueSegments(
  Clue clue,
  CaseData c,
  AppLocalizations l10n,
  NameForms names,
) {
  final plain = describeClue(clue, c, l10n, names);
  final dashLen = plain.startsWith(_clueDash) ? _clueDash.length : 0;
  if (clue is InRoom) {
    final room = names.roomPrep(clue.roomId);
    final segments = _roomSentenceSegments(
      plain,
      dashLen,
      room,
      c.rooms.indexWhere((r) => r.id == clue.roomId),
    );
    if (segments != null) return segments;
  }
  return [
    if (dashLen > 0) DashClueSegment(_clueDash),
    PlainClueSegment(plain.substring(dashLen)),
  ];
}

/// The room chip's painted background (issue 104): cartoon skins fill with
/// the room's board tint (the board's own room color, indexed like the
/// legend sheet and the board); classic composites the legend-swatch alpha
/// 0.55 ([classicRoomTints] at `withValues(alpha: 0.55)`).
Color clueChipBackground(SkinTokens? tokens, int roomIndex) {
  final cartoon = tokens != null && tokens.isCartoon;
  final tints = cartoon ? tokens.roomTints : classicRoomTints;
  final tint = tints[roomIndex % tints.length];
  return cartoon ? tint : tint.withValues(alpha: 0.55);
}

/// The opaque color the chip effectively paints as: cartoon skins paint the
/// tint itself; classic's alpha swatch composites over the [cardSurface]
/// (the classic card decoration color), which is what the chip text must
/// contrast against.
Color clueChipEffectiveBackground(
  SkinTokens? tokens,
  int roomIndex,
  Color cardSurface,
) {
  final bg = clueChipBackground(tokens, roomIndex);
  final cartoon = tokens != null && tokens.isCartoon;
  return cartoon ? bg : Color.alphaBlend(bg, cardSurface);
}

/// WCAG contrast ratio of two colors (relative luminance, +0.05 offsets).
double clueContrastRatio(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return math.max(la, lb) / math.min(la, lb);
}

/// The room chip's label ink (issue 104): a deterministic shade of the chip
/// background's tint reaching AA (>= 4.5:1) against
/// [effectiveBackground]. Steps darken the tint 10% toward black per
/// iteration and prefer the darker shade (the spec's "same tint, darkened");
/// toward-white steps join only as the fallback for backgrounds dark enough
/// that no darker shade can ever reach 4.5:1 (classic dark cards). 96 steps
/// bound the loop (the geometric series converges close enough to the black
/// or white asymptote for every reachable background).
Color clueChipInk(Color effectiveBackground) {
  var dark = effectiveBackground;
  var light = effectiveBackground;
  for (var i = 0; i < 96; i++) {
    if (clueContrastRatio(dark, effectiveBackground) >= 4.5) return dark;
    if (clueContrastRatio(light, effectiveBackground) >= 4.5) return light;
    dark = Color.lerp(dark, Colors.black, 0.1)!;
    light = Color.lerp(light, Colors.white, 0.1)!;
  }
  return dark;
}

/// The clue chip's shape tokens (issue 104): a fixed radius (not the classic
/// room-radius 0) and small padding so a chip line grows ~4 px.
const double clueChipRadius = 9;
const EdgeInsets clueChipPadding = EdgeInsets.symmetric(
  horizontal: 6,
  vertical: 2,
);

/// The inline span tree for one clue sentence (issue 104): the dash span at
/// [dashScale] x the sentence font size, the plain spans at [sentenceStyle],
/// and one rounded room chip WidgetSpan per room segment — filled with the
/// room's board tint ([tokens] null or non-cartoon selects the classic
/// legend-swatch alpha over [cardSurface]) and labeled in the tint-derived
/// AA ink. The row-height math builds this same tree, so measured heights
/// match the rendered heights.
TextSpan clueSentenceSpan(
  List<ClueSegment> segments, {
  required TextStyle sentenceStyle,
  required SkinTokens? tokens,
  required Color cardSurface,
  double dashScale = clueDashFontScale,
}) => TextSpan(
  children: [
    for (final segment in segments)
      switch (segment) {
        DashClueSegment(:final text) => _dashSpan(
          text,
          sentenceStyle,
          dashScale,
        ),
        PlainClueSegment(:final text) => TextSpan(
          text: text,
          style: sentenceStyle,
        ),
        RoomClueSegment(:final text, :final roomIndex) => _roomChipSpan(
          text,
          roomIndex,
          sentenceStyle,
          tokens,
          cardSurface,
        ),
      },
  ],
);

/// The sentence's leading dash at [dashScale] x the sentence font size
/// (issue 104).
TextSpan _dashSpan(String text, TextStyle sentenceStyle, double dashScale) =>
    TextSpan(
      text: text,
      style: sentenceStyle.copyWith(
        fontSize: (sentenceStyle.fontSize ?? 14) * dashScale,
      ),
    );

/// The room chip WidgetSpan (issue 104): the rounded tint-filled box,
/// middle-aligned on the sentence line. The label is a scale-down FittedBox
/// so the chip NEVER re-wraps inside the paragraph's constraints — a phrase
/// wider than the card at extreme text scales shrinks to the card's text
/// width instead (no overflow, no reflow). The row-height math reserves the
/// chip's natural-size box ([_clueChipSize] + [clueChipPadding]), which is
/// therefore an upper bound of the rendered box at every text scale: rows
/// grow at least to the rendered content, never clipping it.
InlineSpan _roomChipSpan(
  String text,
  int roomIndex,
  TextStyle sentenceStyle,
  SkinTokens? tokens,
  Color cardSurface,
) {
  final bg = clueChipBackground(tokens, roomIndex);
  final effective = clueChipEffectiveBackground(tokens, roomIndex, cardSurface);
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      padding: clueChipPadding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(clueChipRadius),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: sentenceStyle.copyWith(color: clueChipInk(effective)),
        ),
      ),
    ),
  );
}

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
    final objectName = names.objectPrep(_objectKind(c, clue.objectId));
    return _either(
      clue.negated,
      l10n.clueBesideObject(objectName),
      l10n.clueBesideObjectNot(objectName),
    );
  }
  return _objectCellOrTargetSentence(clue, c, l10n, names);
}

/// The issue-111 object-cell kinds (positive-only templates) or, for every
/// other kind, the target-bearing sentence.
String _objectCellOrTargetSentence(
  Clue clue,
  CaseData c,
  AppLocalizations l10n,
  NameForms names,
) {
  if (clue is OnObject) return _onObjectSentence(clue, c, names, l10n);
  if (clue is NearObject) return _nearObjectSentence(clue, c, names, l10n);
  if (clue is SoleNearObject) {
    return _soleNearObjectSentence(clue, c, names, l10n);
  }
  return _targetClueSentence(clue, l10n, names);
}

/// The item kind an object-anchored clue points at.
ObjectKind _objectKind(CaseData c, String objectId) =>
    c.objects.firstWhere((o) => o.id == objectId).kind;

/// The three object-cell kinds render positive-only templates keyed by the
/// item kind. Negated forms never ship (the generator cannot emit them), so
/// the renderer rejects them loudly instead of lying with a positive
/// template.
String _onObjectSentence(
  OnObject clue,
  CaseData c,
  NameForms names,
  AppLocalizations l10n,
) {
  if (clue.negated) {
    throw ArgumentError('negated object-cell clues never ship: $clue');
  }
  return l10n.clueOnObject(names.objectOn(_objectKind(c, clue.objectId)));
}

String _nearObjectSentence(
  NearObject clue,
  CaseData c,
  NameForms names,
  AppLocalizations l10n,
) {
  if (clue.negated) {
    throw ArgumentError('negated object-cell clues never ship: $clue');
  }
  return l10n.clueNearObject(names.objectPrep(_objectKind(c, clue.objectId)));
}

String _soleNearObjectSentence(
  SoleNearObject clue,
  CaseData c,
  NameForms names,
  AppLocalizations l10n,
) {
  if (clue.negated) {
    throw ArgumentError('negated object-cell clues never ship: $clue');
  }
  return l10n.clueSoleNearObject(
    names.objectPrep(_objectKind(c, clue.objectId)),
  );
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
    this.showHeader = true,
  });

  final CaseData caseData;
  final Map<String, Pos> placed;
  final String? selectedSuspectId;
  final void Function(String) onSuspectTap;

  /// False only from the landscape game screen's wide branch (issue 103):
  /// the «Подозреваемые»/"Suspects" header row disappears, the grid lays
  /// out 2 columns of content-height cards, and the grid fills the whole
  /// panel. Every other host keeps the default true (header + 3-column
  /// phone grid).
  final bool showHeader;

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
    final clueSegments = _clueSegmentsBySuspect(l10n, names);
    final cards = _cards(names, clueTexts, clueSegments);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Issue 59: reject unbounded-width hosts before any width branch
        // below (see _assertHostWidthIsFinite).
        _assertHostWidthIsFinite(constraints);
        if (constraints.maxWidth >= 600) {
          return _wideColumn(cards);
        }
        return _narrowColumn(
          context,
          constraints,
          cards,
          clueSegments,
          names,
          cardBorderWidth,
          skin,
        );
      },
    );
  }

  /// The panel's wide (≥600px) branch: a vertical list of cards, each sizing
  /// itself to its content instead of a pinned 150px height, so longer clue
  /// text (or large text scale) never clips (UX-9). The header (issue 27)
  /// rides the top of the list — unless the landscape game screen dropped it
  /// (issue 103).
  Widget _wideColumn(List<_SuspectCard> cards) => ListView(
    children: [
      if (showHeader) const _SuspectsHeader(),
      for (final card in cards) IntrinsicHeight(child: card),
    ],
  );

  /// The narrow branch's grid column count: 3 on phones, 2 in the landscape
  /// game screen's header-less host (issue 103).
  int get _narrowColumns => showHeader ? _gridColumns : _landscapeGridColumns;

  /// The header row above the narrow grid — an empty list in the landscape
  /// game screen's header-less host (issue 103).
  List<Widget> get _headerRow =>
      showHeader ? [const _SuspectsHeader()] : const <Widget>[];

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

  /// Clue sentences as inline segments grouped per suspect, in clue order
  /// (issue 104) — the rendered form of [_clueTextsBySuspect]'s strings.
  Map<String, List<List<ClueSegment>>> _clueSegmentsBySuspect(
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
            describeClueSegments(clue, caseData, l10n, names),
        ],
    };
  }

  /// One card per suspect, in board order.
  List<_SuspectCard> _cards(
    NameForms names,
    Map<String, List<String>> clueTexts,
    Map<String, List<List<ClueSegment>>> clueSegments,
  ) => [
    for (var i = 0; i < caseData.suspects.length; i++)
      _SuspectCard(
        suspect: caseData.suspects[i],
        displayName: names.nom(caseData.suspects[i].id),
        color: suspectColor(i),
        clueTexts: clueTexts[caseData.suspects[i].id] ?? const <String>[],
        clueSegments:
            clueSegments[caseData.suspects[i].id] ??
            const <List<ClueSegment>>[],
        selected: caseData.suspects[i].id == selectedSuspectId,
        isPlaced: placed.containsKey(caseData.suspects[i].id),
        onTap: () => onSuspectTap(caseData.suspects[i].id),
      ),
  ];

  /// The narrow (below 600px) layout: header above the 3-column grid; the
  /// grid fills the pinned slot below the header, clamps to the space under
  /// the header when the host bounds the height, or shrink-wraps its grown
  /// rows otherwise (issue 39). The landscape game screen hosts this branch
  /// header-less ([showHeader] false, issue 103): 2 columns of pure
  /// content-height rows, the grid filling the whole panel — the issue-39
  /// pinned split and issue-58 slot rule carry over with the new numbers.
  Widget _narrowColumn(
    BuildContext context,
    BoxConstraints constraints,
    List<_SuspectCard> cards,
    Map<String, List<List<ClueSegment>>> clueSegments,
    NameForms names,
    double cardBorderWidth,
    SkinTokens? skin,
  ) {
    final columns = _narrowColumns;
    final cardWidth =
        (constraints.maxWidth - 2 * _gridHPad - (columns - 1) * _gridSpacing) /
        columns;
    final grownRowHeight = _narrowRowHeight(
      context,
      constraints,
      cardWidth,
      clueSegments,
      names,
      cardBorderWidth,
      skin?.chip,
      showHeader: showHeader,
    );
    // Grid children, their real row count, and their ideal shrink-wrapped
    // height at the grown row height above: padding on both edges, every
    // grown row, and the gutters between them (issue 30's overflow
    // detection, now shared by the pinned branch's overflow check via the
    // layout-time slot compare — issue 39). The row count is the real grid
    // children's (issue 39). The decorative empty slot joins only when the
    // last row has a spare cell: 5 suspects lay out 2 rows with the
    // slot in the sixth cell, 6 suspects lay out 2 full rows — appending the
    // slot to a full last row would open a lone decorative row that owns the
    // scroll end and clip the last suspect row at max scroll (issue 58).
    final children = caseData.suspects.length % columns != 0
        ? [...cards, const _EmptySlot()]
        : cards;
    final rows = (children.length / columns).ceil();
    final gridContentHeight =
        2 * _gridHPad + rows * grownRowHeight + (rows - 1) * _gridSpacing;
    GridView buildGrid({required bool scrollable, required double rowHeight}) =>
        GridView.count(
          crossAxisCount: columns,
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
        ..._headerRow,
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
  /// every row. The landscape grid (issue 103) drops the square-ish
  /// `cardWidth / 1.05` floor — its wide cards would stretch to ~268px tall
  /// — so its rows are pure content height.
  double _narrowRowHeight(
    BuildContext context,
    BoxConstraints constraints,
    double cardWidth,
    Map<String, List<List<ClueSegment>>> clueSegments,
    NameForms names,
    double cardBorderWidth,
    SkinChip? chip, {
    required bool showHeader,
  }) {
    final floorHeight = showHeader ? cardWidth / 1.05 : 0.0;
    if (constraints.maxWidth.isFinite) {
      return math.max(
        floorHeight,
        _contentRowHeight(
          context,
          cardWidth,
          clueSegments,
          names,
          cardBorderWidth,
          chip,
        ),
      );
    }
    return floorHeight;
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
  /// the token's gap joins them — exactly the structure the card renders,
  /// chip WidgetSpans included (issue 104).
  double _contentRowHeight(
    BuildContext context,
    double cardWidth,
    Map<String, List<List<ClueSegment>>> clueSegmentsBySuspect,
    NameForms names,
    double borderWidth,
    SkinChip? chip,
  ) {
    final base = DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // The chip colors the measurement spans carry (metrics ignore colors, so
    // the unselected classic surface is fine here).
    final tokens = SkinScope.maybeOf(context);
    final cardSurface = tokens != null && tokens.isCartoon
        ? tokens.card.background
        : theme.colorScheme.surfaceContainerHighest;
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
        clueSegmentsBySuspect[suspect.id] ?? const <List<ClueSegment>>[],
        chip,
        base.merge(theme.textTheme.bodySmall),
        scaler,
        direction,
        textWidth,
        tokens: tokens,
        cardSurface: cardSurface,
      );
      // 2 * (4 outer padding + 8 container padding + border) + name row
      // (the 24dp avatar floors its height) + 4 gap + clue text block.
      final cardHeight =
          2 * (12 + borderWidth) + math.max(24.0, nameHeight) + 4 + clueHeight;
      maxHeight = math.max(maxHeight, cardHeight);
    }
    return maxHeight;
  }

  /// The clue text block's height at the card's text width: joined rich
  /// paragraph for classic, per-sentence gap arithmetic in chip mode
  /// (issue 26) — the exact span trees the card renders (issue 104), with
  /// the room chips as sized placeholders.
  double _clueBlockHeight(
    List<List<ClueSegment>> sentenceSegments,
    SkinChip? chip,
    TextStyle sentenceStyle,
    TextScaler scaler,
    TextDirection direction,
    double textWidth, {
    required SkinTokens? tokens,
    required Color cardSurface,
  }) {
    if (sentenceSegments.isEmpty) return 0.0;
    if (chip == null) {
      return _measureClassicBlock(
        sentenceSegments,
        sentenceStyle,
        scaler,
        direction,
        textWidth,
        tokens: tokens,
        cardSurface: cardSurface,
      );
    }
    return _measureChipBlock(
      sentenceSegments,
      sentenceStyle,
      chip,
      scaler,
      direction,
      textWidth,
      tokens: tokens,
      cardSurface: cardSurface,
    );
  }

  /// Classic's joined rich paragraph height (issue 104's rich upgrade of
  /// the plain join).
  double _measureClassicBlock(
    List<List<ClueSegment>> sentenceSegments,
    TextStyle sentenceStyle,
    TextScaler scaler,
    TextDirection direction,
    double textWidth, {
    required SkinTokens? tokens,
    required Color cardSurface,
  }) {
    // The root carries the sentence style so the newline separators inherit
    // exactly what the rendered Text.rich's root gives them (issue 104).
    final tree = TextSpan(
      style: sentenceStyle,
      children: [
        for (final (i, segments) in sentenceSegments.indexed) ...[
          if (i > 0) const TextSpan(text: '\n'),
          clueSentenceSpan(
            segments,
            sentenceStyle: sentenceStyle,
            tokens: tokens,
            cardSurface: cardSurface,
          ),
        ],
      ],
    );
    return _measureSpanTree(
      tree,
      [
        for (final segments in sentenceSegments)
          ..._placeholderSizes(segments, sentenceStyle, scaler, direction),
      ],
      scaler,
      direction,
      textWidth,
    );
  }

  /// Chip mode's per-sentence heights plus the skin's gaps (issue 26).
  double _measureChipBlock(
    List<List<ClueSegment>> sentenceSegments,
    TextStyle sentenceStyle,
    SkinChip chip,
    TextScaler scaler,
    TextDirection direction,
    double textWidth, {
    required SkinTokens? tokens,
    required Color cardSurface,
  }) {
    var clueHeight = 0.0;
    for (var i = 0; i < sentenceSegments.length; i++) {
      if (i > 0) clueHeight += chip.gap;
      clueHeight += _measureSpanTree(
        clueSentenceSpan(
          sentenceSegments[i],
          sentenceStyle: sentenceStyle,
          tokens: tokens,
          cardSurface: cardSurface,
        ),
        _placeholderSizes(
          sentenceSegments[i],
          sentenceStyle,
          scaler,
          direction,
        ),
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
    required this.clueSegments,
    required this.selected,
    required this.isPlaced,
    required this.onTap,
  });

  final Suspect suspect;
  final String displayName;
  final Color color;
  final List<String> clueTexts;

  /// The rendered form of [clueTexts] (issue 104): per sentence, the inline
  /// segments with the room phrase to chip.
  final List<List<ClueSegment>> clueSegments;
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

  /// The clue area: bare gap-separated rich sentence column in chip mode
  /// (issues 26/89, rich since issue 104), scrollable rich column on the
  /// expanded (selected) card, joined rich paragraph otherwise.
  Widget _clueArea(BuildContext context, SkinChip? chip) {
    final sentenceStyle = _sentenceStyle(context);
    final cardSurface = _cardSurface(context);
    if (chip != null) {
      // Each clue sentence as a bare gap-separated rich Text (issue 89,
      // issue 104's dash/chip spans), selected and unselected alike. The
      // scroll view is the same escape hatch the selected card already had:
      // when the host pins a slot shorter than the content (narrow layout),
      // the sentences scroll instead of throwing a RenderFlex overflow; the
      // row-height math grows the rows wherever the host leaves the height
      // loose, so this scrolls only when there is genuinely no room (UX-9).
      return Expanded(
        child: SingleChildScrollView(
          child: _chipColumn(context, chip, sentenceStyle, cardSurface),
        ),
      );
    }
    if (selected) {
      return Expanded(
        child: SingleChildScrollView(
          child: _plainColumn(context, sentenceStyle, cardSurface),
        ),
      );
    }
    return Expanded(
      child: Text.rich(
        _joinedParagraph(context, sentenceStyle, cardSurface),
        style: sentenceStyle,
      ),
    );
  }

  /// The sentence style every clue span carries: the card's merged rendering
  /// style — the same merge convention the row-height math measures with.
  TextStyle _sentenceStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style
          .merge(Theme.of(context).textTheme.bodySmall);

  /// The opaque surface the card paints behind its clue text: the cartoon
  /// token card, or the classic scheme container (selected containers swap
  /// the scheme color, which the classic chip's composite accounts for).
  Color _cardSurface(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = SkinScope.maybeOf(context);
    return tokens != null && tokens.isCartoon
        ? tokens.card.background
        : selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;
  }

  /// One bare clue sentence per line (issue 89), rich since issue 104: the
  /// rounded pill is gone, the token's gap separates the sentences, and the
  /// texts left-align with the name row.
  Widget _chipColumn(
    BuildContext context,
    SkinChip chip,
    TextStyle sentenceStyle,
    Color cardSurface,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, segments) in clueSegments.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : chip.gap),
          child: Text.rich(
            clueSentenceSpan(
              segments,
              sentenceStyle: sentenceStyle,
              tokens: SkinScope.maybeOf(context),
              cardSurface: cardSurface,
            ),
            style: sentenceStyle,
          ),
        ),
    ],
  );

  /// The selected card's rich clue column (issue 26's escape hatch).
  Widget _plainColumn(
    BuildContext context,
    TextStyle sentenceStyle,
    Color cardSurface,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final segments in clueSegments)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text.rich(
            clueSentenceSpan(
              segments,
              sentenceStyle: sentenceStyle,
              tokens: SkinScope.maybeOf(context),
              cardSurface: cardSurface,
            ),
            style: sentenceStyle,
          ),
        ),
    ],
  );

  /// The classic unselected rendering: one rich paragraph per card, the
  /// sentences newline-joined (issue 104's rich upgrade of the plain join).
  TextSpan _joinedParagraph(
    BuildContext context,
    TextStyle sentenceStyle,
    Color cardSurface,
  ) => TextSpan(
    children: [
      for (final (i, segments) in clueSegments.indexed) ...[
        if (i > 0) const TextSpan(text: '\n'),
        clueSentenceSpan(
          segments,
          sentenceStyle: sentenceStyle,
          tokens: SkinScope.maybeOf(context),
          cardSurface: cardSurface,
        ),
      ],
    ],
  );
}

/// Measures [tree]'s wrapped height at [width]; the room chips participate
/// through [placeholderSizes] (one box per WidgetSpan in traversal order,
/// issue 104), so the measured height matches the rendered paragraph.
double _measureSpanTree(
  TextSpan tree,
  List<Size> placeholderSizes,
  TextScaler scaler,
  TextDirection direction,
  double width,
) {
  final painter = TextPainter(
    text: tree,
    textDirection: direction,
    textScaler: scaler,
  );
  painter.setPlaceholderDimensions([
    for (final size in placeholderSizes)
      PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.middle),
  ]);
  painter.layout(maxWidth: width);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// The room chips' boxes for [segments], in tree traversal order: each room
/// phrase measured at the sentence style plus the chip padding — exactly
/// what the rendered WidgetSpan lays out.
List<Size> _placeholderSizes(
  List<ClueSegment> segments,
  TextStyle sentenceStyle,
  TextScaler scaler,
  TextDirection direction,
) => [
  for (final segment in segments)
    if (segment is RoomClueSegment)
      _clueChipSize(segment.text, sentenceStyle, scaler, direction),
];

/// The room chip's box (issue 104): the phrase laid out on one line at
/// [sentenceStyle] plus [clueChipPadding].
Size _clueChipSize(
  String roomText,
  TextStyle sentenceStyle,
  TextScaler scaler,
  TextDirection direction,
) {
  final painter = TextPainter(
    text: TextSpan(text: roomText, style: sentenceStyle),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  final size = Size(
    painter.width + clueChipPadding.horizontal,
    painter.height + clueChipPadding.vertical,
  );
  painter.dispose();
  return size;
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
