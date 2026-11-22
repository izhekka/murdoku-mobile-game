import 'package:material_ui/material_ui.dart';

import 'package:murdoku/storage/prefs_repository.dart' show SkinSetting;

/// Immutable visual configuration of one skin (issue 23). Everything a
/// widget needs to restyle itself comes from here — no hardcoded skin
/// colors in widgets. Classic tokens are derived from the live
/// [ColorScheme] (see [skinTokensFor]) so the classic look can never drift
/// from the seed output; the cartoon skins are compile-time constants from
/// the owner-approved mockups
/// (docs/superpowers/plans/style-mockups-2026-11-22/).
class SkinTokens {
  const SkinTokens({
    required this.skin,
    required this.isCartoon,
    required this.pageColor,
    this.pageGradient = const [],
    this.pageDotColor,
    this.pageBlobColor,
    required this.appBackground,
    required this.ink,
    required this.inkSoft,
    required this.card,
    required this.roomTints,
    required this.badge,
    required this.mortarColor,
    required this.solidRooms,
    required this.roomRadius,
    required this.roomLineWidth,
    required this.victimFill,
    required this.victimStripeColor,
    required this.actions,
    required this.dangerColor,
    required this.buttonRadius,
    required this.buttonShadow,
    required this.sheetBackground,
    required this.sheetRadius,
    required this.menuIcons,
    this.panelHeaderUppercase = false,
    this.chip,
    this.frame,
    this.frameMargin = 0,
    this.frameRingWidth = 0,
    this.frameRingColor = const Color(0x00000000),
  });

  final SkinSetting skin;

  /// False only for the classic noir skin: widgets keep today's exact
  /// rendering wherever the skins differ.
  final bool isCartoon;

  /// The page behind the app frame (sky gradient for candy, mint with white
  /// polka dots for sticker, yellow halftone for comic). [pageGradient]
  /// empty = flat [pageColor]; [pageDotColor] paints a polka-dot grid;
  /// [pageBlobColor] paints soft cloud blobs (candy).
  final Color pageColor;
  final List<Color> pageGradient;
  final Color? pageDotColor;
  final Color? pageBlobColor;

  /// The app frame's inner background (Scaffold color inside the frame).
  final Color appBackground;

  /// Primary text/icon ink and its softened variant.
  final Color ink;
  final Color inkSoft;

  /// Content cards: suspect cards, home cards, sheets, dialogs.
  final SkinCard card;

  /// Room block tints, indexed by room position; must cover 8 rooms (hard
  /// difficulty) with pairwise distinct colors.
  final List<Color> roomTints;

  /// Room number badge on the board.
  final SkinBadge badge;

  /// Room-boundary line color on the board ("mortar" between room blocks).
  final Color mortarColor;

  /// Rooms render as solid blocks with boundary-only lines; false keeps the
  /// classic per-cell thin/thick borders.
  final bool solidRooms;
  final double roomRadius;
  final double roomLineWidth;

  /// The victim cell: flat [victimFill], or diagonal stripes of
  /// [victimStripeColor] when the two differ (cartoon mockups).
  final Color victimFill;
  final Color victimStripeColor;

  /// Per-action toolbar colors (shared by all cartoon skins, from the
  /// mockups); unused by classic, which keeps its scheme-colored buttons.
  final SkinActions actions;
  final Color dangerColor;

  final double buttonRadius;
  final BoxShadow buttonShadow;

  /// Bottom sheets (pause menu, legend, hints, accuse, difficulty).
  final Color sheetBackground;
  final double sheetRadius;

  /// The classic pause menu shows leading icons; the cartoon mockups use a
  /// clean icon-free list card.
  final bool menuIcons;

  /// Panel headers («Подозреваемые», issue 27) render uppercase — true for
  /// comic only; the other mockups show the title-case header.
  final bool panelHeaderUppercase;

  /// The rounded chip behind each clue sentence on the suspect cards
  /// (issue 26); null for classic, which keeps the pre-existing plain clue
  /// rendering.
  final SkinChip? chip;

  /// The rounded app card sitting on the page background; null for classic,
  /// which has no frame.
  final SkinCard? frame;
  final double frameMargin;
  final double frameRingWidth;
  final Color frameRingColor;

  @override
  bool operator ==(Object other) =>
      other is SkinTokens &&
      other.skin == skin &&
      other.isCartoon == isCartoon &&
      other.pageColor == pageColor &&
      other.pageGradient == pageGradient &&
      other.pageDotColor == pageDotColor &&
      other.pageBlobColor == pageBlobColor &&
      other.appBackground == appBackground &&
      other.ink == ink &&
      other.inkSoft == inkSoft &&
      other.card == card &&
      other.roomTints == roomTints &&
      other.badge == badge &&
      other.mortarColor == mortarColor &&
      other.solidRooms == solidRooms &&
      other.roomRadius == roomRadius &&
      other.roomLineWidth == roomLineWidth &&
      other.victimFill == victimFill &&
      other.victimStripeColor == victimStripeColor &&
      other.actions == actions &&
      other.dangerColor == dangerColor &&
      other.buttonRadius == buttonRadius &&
      other.buttonShadow == buttonShadow &&
      other.sheetBackground == sheetBackground &&
      other.sheetRadius == sheetRadius &&
      other.menuIcons == menuIcons &&
      other.panelHeaderUppercase == panelHeaderUppercase &&
      other.chip == chip &&
      other.frame == frame &&
      other.frameMargin == frameMargin &&
      other.frameRingWidth == frameRingWidth &&
      other.frameRingColor == frameRingColor;

  @override
  int get hashCode => Object.hashAll([
    skin,
    isCartoon,
    pageColor,
    pageGradient,
    pageDotColor,
    pageBlobColor,
    appBackground,
    ink,
    inkSoft,
    card,
    roomTints,
    badge,
    mortarColor,
    solidRooms,
    roomRadius,
    roomLineWidth,
    victimFill,
    victimStripeColor,
    actions,
    dangerColor,
    buttonRadius,
    buttonShadow,
    sheetBackground,
    sheetRadius,
    menuIcons,
    panelHeaderUppercase,
    chip,
    frame,
    frameMargin,
    frameRingWidth,
    frameRingColor,
  ]);
}

/// A card surface: background fill, border, corner radius and one shadow.
class SkinCard {
  const SkinCard({
    required this.background,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.shadow,
  });

  final Color background;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final BoxShadow shadow;

  @override
  bool operator ==(Object other) =>
      other is SkinCard &&
      other.background == background &&
      other.borderColor == borderColor &&
      other.borderWidth == borderWidth &&
      other.radius == radius &&
      other.shadow == shadow;

  @override
  int get hashCode =>
      Object.hash(background, borderColor, borderWidth, radius, shadow);
}

/// A clue chip on the suspect cards (issue 26): each clue sentence sits in
/// its own rounded pill per the approved mockups. Null on classic tokens —
/// widgets keep the pre-existing plain clue rendering there.
class SkinChip {
  const SkinChip({
    required this.background,
    required this.radius,
    required this.padding,
    required this.gap,
  });

  final Color background;
  final double radius;
  final EdgeInsets padding;

  /// Vertical spacing between consecutive chips.
  final double gap;

  @override
  bool operator ==(Object other) =>
      other is SkinChip &&
      other.background == background &&
      other.radius == radius &&
      other.padding == padding &&
      other.gap == gap;

  @override
  int get hashCode => Object.hash(background, radius, padding, gap);
}

/// Room number badge: circle fill with the room number in [ink].
class SkinBadge {
  const SkinBadge({required this.background, required this.ink});

  final Color background;
  final Color ink;

  @override
  bool operator ==(Object other) =>
      other is SkinBadge && other.background == background && other.ink == ink;

  @override
  int get hashCode => Object.hash(background, ink);
}

/// Toolbar colors per action; shared across the cartoon skins (issue 23).
class SkinActions {
  const SkinActions({
    required this.place,
    required this.mark,
    required this.erase,
    required this.undo,
    required this.hint,
    required this.check,
    required this.accuse,
    required this.menu,
  });

  final Color place;
  final Color mark;
  final Color erase;
  final Color undo;
  final Color hint;
  final Color check;
  final Color accuse;
  final Color menu;

  @override
  bool operator ==(Object other) =>
      other is SkinActions &&
      other.place == place &&
      other.mark == mark &&
      other.erase == erase &&
      other.undo == undo &&
      other.hint == hint &&
      other.check == check &&
      other.accuse == accuse &&
      other.menu == menu;

  @override
  int get hashCode =>
      Object.hash(place, mark, erase, undo, hint, check, accuse, menu);
}

/// Shared cartoon toolbar palette (issue 23). The mockups show no Accuse
/// button (the app has one), so accuse takes the danger accent.
const SkinActions _cartoonActions = SkinActions(
  place: Color(0xFFFF6B9D),
  mark: Color(0xFFFFA94D),
  erase: Color(0xFF38D9A9),
  undo: Color(0xFF74C0FC),
  hint: Color(0xFFFFC078),
  check: Color(0xFF51CF66),
  accuse: Color(0xFFE8590C),
  menu: Color(0xFFB197FC),
);

/// Clue-chip look shared by the three cartoon mockups (issue 26): a rounded
/// light-gray pill behind each clue sentence. Token-driven so a skin can
/// diverge later; classic keeps null (plain clue text).
const SkinChip _cartoonChip = SkinChip(
  background: Color(0xFFF1F3F5),
  radius: 12,
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  gap: 6,
);

const Color _cartoonDanger = Color(0xFFE8590C);

/// Victim cell stripe pair shared by the three cartoon mockups.
const Color _victimFill = Color(0xFFFFC9C9);
const Color _victimStripe = Color(0xFFF47C7C);

/// Soft candy shadow tone: rgba(31,108,158,.14) per the issue.
const Color _candyShadow = Color(0x241F6C9E);

/// Карамель (style-a-candy.png): sky-gradient page with soft cloud blobs,
/// white fluffy cards with soft shadows.
const candyTokens = SkinTokens(
  skin: SkinSetting.candy,
  isCartoon: true,
  pageColor: Color(0xFF6FCBFF),
  pageGradient: [Color(0xFF6FCBFF), Color(0xFFA9EBFF), Color(0xFFC6F6FF)],
  pageBlobColor: Color(0x8CFFFFFF),
  appBackground: Color(0xFFFFFFFF),
  ink: Color(0xFF35406E),
  inkSoft: Color(0xFF6B76A8),
  card: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFFFFFFFF),
    borderWidth: 4,
    radius: 20,
    shadow: BoxShadow(color: _candyShadow, offset: Offset(0, 6)),
  ),
  roomTints: [
    Color(0xFFFF9EB5),
    Color(0xFFFFC078),
    Color(0xFFFFE999),
    Color(0xFFD0BFFF),
    Color(0xFF8FF2C8),
    Color(0xFF9FD5FF),
    Color(0xFFC7F284),
    Color(0xFFFF9E80),
  ],
  badge: SkinBadge(background: Color(0xFFFFFFFF), ink: Color(0xFF35406E)),
  mortarColor: Color(0xFFFFFFFF),
  solidRooms: true,
  roomRadius: 14,
  roomLineWidth: 4,
  victimFill: _victimFill,
  victimStripeColor: _victimStripe,
  actions: _cartoonActions,
  dangerColor: _cartoonDanger,
  buttonRadius: 14,
  buttonShadow: BoxShadow(color: _candyShadow, offset: Offset(0, 4)),
  sheetBackground: Color(0xFFFFFFFF),
  sheetRadius: 24,
  menuIcons: false,
  chip: _cartoonChip,
  frame: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFFFFFFFF),
    borderWidth: 4,
    radius: 28,
    shadow: BoxShadow(color: _candyShadow, offset: Offset(0, 12)),
  ),
  frameMargin: 12,
);

/// Стикеры (style-b-sticker.png): flat mint polka-dot page, cream app
/// background, white cards with navy outlines and hard offset shadows.
const stickerTokens = SkinTokens(
  skin: SkinSetting.sticker,
  isCartoon: true,
  pageColor: Color(0xFF45C4B0),
  pageDotColor: Color(0x73FFFFFF),
  appBackground: Color(0xFFFFF8EF),
  ink: Color(0xFF1D3557),
  inkSoft: Color(0xFF457B9D),
  card: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFF1D3557),
    borderWidth: 3,
    radius: 16,
    shadow: BoxShadow(color: Color(0xFF1D3557), offset: Offset(6, 6)),
  ),
  roomTints: [
    Color(0xFFFF6B6B),
    Color(0xFFFFA94D),
    Color(0xFFFFD43B),
    Color(0xFFB197FC),
    Color(0xFF63E6BE),
    Color(0xFF74C0FC),
    Color(0xFFA9E34B),
    Color(0xFFF783AC),
  ],
  badge: SkinBadge(background: Color(0xFFFFFFFF), ink: Color(0xFF1D3557)),
  mortarColor: Color(0xFF1D3557),
  solidRooms: true,
  roomRadius: 10,
  roomLineWidth: 3.5,
  victimFill: _victimFill,
  victimStripeColor: _victimStripe,
  actions: _cartoonActions,
  dangerColor: _cartoonDanger,
  buttonRadius: 14,
  buttonShadow: BoxShadow(color: Color(0xFF1D3557), offset: Offset(3, 3)),
  sheetBackground: Color(0xFFFFFFFF),
  sheetRadius: 20,
  menuIcons: false,
  chip: _cartoonChip,
  frame: SkinCard(
    background: Color(0xFFFFF8EF),
    borderColor: Color(0xFF1D3557),
    borderWidth: 3,
    radius: 28,
    shadow: BoxShadow(color: Color(0xFF1D3557), offset: Offset(6, 6)),
  ),
  frameMargin: 12,
);

/// Комикс (style-d-comic.png): yellow halftone page, white app card with a
/// black outline and a white ring, hard black offset shadows, uppercase
/// chrome ink.
const comicTokens = SkinTokens(
  skin: SkinSetting.comic,
  isCartoon: true,
  pageColor: Color(0xFFFFD43B),
  pageDotColor: Color(0x8CFFFFFF),
  appBackground: Color(0xFFFFFFFF),
  ink: Color(0xFF111111),
  inkSoft: Color(0xFF444444),
  card: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFF111111),
    borderWidth: 3.5,
    radius: 16,
    shadow: BoxShadow(color: Color(0xFF111111), offset: Offset(7, 7)),
  ),
  roomTints: [
    Color(0xFFFF595E),
    Color(0xFFFFCA3A),
    Color(0xFFFFE24A),
    Color(0xFF9B5DE5),
    Color(0xFF70E000),
    Color(0xFF00B4D8),
    Color(0xFFFF924C),
    Color(0xFFFF80BF),
  ],
  badge: SkinBadge(background: Color(0xFFFFFFFF), ink: Color(0xFF111111)),
  mortarColor: Color(0xFF111111),
  solidRooms: true,
  roomRadius: 10,
  roomLineWidth: 4,
  victimFill: _victimFill,
  victimStripeColor: _victimStripe,
  actions: _cartoonActions,
  dangerColor: _cartoonDanger,
  buttonRadius: 14,
  buttonShadow: BoxShadow(color: Color(0xFF111111), offset: Offset(3, 3)),
  sheetBackground: Color(0xFFFFFFFF),
  sheetRadius: 20,
  menuIcons: false,
  panelHeaderUppercase: true,
  chip: _cartoonChip,
  frame: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFF111111),
    borderWidth: 4,
    radius: 24,
    shadow: BoxShadow(color: Color(0xFF111111), offset: Offset(8, 8)),
  ),
  frameMargin: 12,
  frameRingWidth: 8,
  frameRingColor: Color(0xFFFFFFFF),
);

/// Classic noir tokens, derived from the resolved [ColorScheme] so the
/// classic rendering stays byte-identical to the current main (both light
/// and dark). Cartoon skins ignore the scheme and return their constants.
SkinTokens skinTokensFor(SkinSetting skin, ColorScheme scheme) =>
    switch (skin) {
      SkinSetting.candy => candyTokens,
      SkinSetting.sticker => stickerTokens,
      SkinSetting.comic => comicTokens,
      SkinSetting.classic => SkinTokens(
        skin: SkinSetting.classic,
        isCartoon: false,
        pageColor: scheme.surface,
        appBackground: scheme.surface,
        ink: scheme.onSurface,
        inkSoft: scheme.onSurfaceVariant,
        card: SkinCard(
          background: scheme.surface,
          borderColor: scheme.outlineVariant,
          borderWidth: 1,
          radius: 12,
          shadow: const BoxShadow(
            color: Color(0x1F000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ),
        roomTints: classicRoomTints,
        badge: SkinBadge(
          background: scheme.primaryContainer,
          ink: scheme.onPrimaryContainer,
        ),
        mortarColor: scheme.outline,
        solidRooms: false,
        roomRadius: 0,
        roomLineWidth: 0,
        victimFill: scheme.errorContainer,
        victimStripeColor: scheme.errorContainer,
        actions: SkinActions(
          place: scheme.primary,
          mark: scheme.primary,
          erase: scheme.primary,
          undo: scheme.primary,
          hint: scheme.primary,
          check: scheme.primary,
          accuse: scheme.primary,
          menu: scheme.primary,
        ),
        dangerColor: scheme.error,
        buttonRadius: 12,
        buttonShadow: const BoxShadow(color: Color(0x00000000)),
        sheetBackground: scheme.surface,
        sheetRadius: 28,
        menuIcons: true,
      ),
    };

/// The classic vivid room palette (moved verbatim from AppTheme so both
/// files can share it without an import cycle).
const classicRoomTints = [
  Color(0xFFE89E3C), // amber
  Color(0xFF35C290), // teal green
  Color(0xFF9A4FD0), // violet
  Color(0xFFD63E2E), // coral red
  Color(0xFF8FCB3A), // lime
  Color(0xFF3E86E0), // sky blue
  Color(0xFFE85890), // pink
  Color(0xFFD8B26E), // sand
];

/// Exposes the active skin's tokens to every widget below the app shell.
class SkinScope extends InheritedWidget {
  const SkinScope({super.key, required this.tokens, required super.child});

  final SkinTokens tokens;

  static SkinTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkinScope>()!.tokens;

  /// Null when no scope is above (bare widget-test harnesses); callers then
  /// keep the classic rendering.
  static SkinTokens? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkinScope>()?.tokens;

  @override
  bool updateShouldNotify(SkinScope oldWidget) => tokens != oldWidget.tokens;
}
