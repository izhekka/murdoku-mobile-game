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
    required this.appBackground,
    required this.ink,
    required this.inkSoft,
    required this.spriteInk,
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
  });

  final SkinSetting skin;

  /// False only for the classic noir skin: widgets keep today's exact
  /// rendering wherever the skins differ.
  final bool isCartoon;

  /// The app's paper background: the Scaffold canvas color that reaches
  /// every screen edge (`theme.dart` seeds it as scaffoldBackgroundColor).
  final Color appBackground;

  /// Primary text/icon ink and its softened variant.
  final Color ink;
  final Color inkSoft;

  /// The ink item sprites (ItemSprite, issue 100) recolor the game-icons
  /// art to at render: an opaque skin-ink silhouette over whatever tint the
  /// sprite lands on, at the WCAG 3:1 non-text bar. Candy needs a deeper
  /// shade than [ink] here — ink #35406E vs the red room tint #D45D48
  /// measures 2.59:1; the deepened navy clears it (see pinned bars in
  /// test/core/skins_contrast_test.dart). Assets are untouched at render.
  final Color spriteInk;

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

  /// The clue-sentence gap on the suspect cards (issue 26, shrunk by issue
  /// 89): the per-sentence pill is gone, so the token keeps only the
  /// vertical gap between consecutive sentences. Null for classic, which
  /// keeps the pre-existing joined paragraph rendering.
  final SkinChip? chip;

  @override
  bool operator ==(Object other) {
    if (other is! SkinTokens) return false;
    return _allEqual([
      other.skin == skin,
      other.isCartoon == isCartoon,
      other.appBackground == appBackground,
      other.ink == ink,
      other.inkSoft == inkSoft,
      other.spriteInk == spriteInk,
      other.card == card,
      other.roomTints == roomTints,
      other.badge == badge,
      other.mortarColor == mortarColor,
      other.solidRooms == solidRooms,
      other.roomRadius == roomRadius,
      other.roomLineWidth == roomLineWidth,
      other.victimFill == victimFill,
      other.victimStripeColor == victimStripeColor,
      other.actions == actions,
      other.dangerColor == dangerColor,
      other.buttonRadius == buttonRadius,
      other.buttonShadow == buttonShadow,
      other.sheetBackground == sheetBackground,
      other.sheetRadius == sheetRadius,
      other.menuIcons == menuIcons,
      other.panelHeaderUppercase == panelHeaderUppercase,
      other.chip == chip,
    ]);
  }

  @override
  int get hashCode => Object.hashAll([
    skin,
    isCartoon,
    appBackground,
    ink,
    inkSoft,
    spriteInk,
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
  bool operator ==(Object other) {
    if (other is! SkinCard) return false;
    return _allEqual([
      other.background == background,
      other.borderColor == borderColor,
      other.borderWidth == borderWidth,
      other.radius == radius,
      other.shadow == shadow,
    ]);
  }

  @override
  int get hashCode =>
      Object.hash(background, borderColor, borderWidth, radius, shadow);
}

/// A clue-sentence gap on the suspect cards (issue 26, shrunk by issue 89):
/// each clue sentence is a bare Text and the token carries only the vertical
/// gap between consecutive sentences. Kept per-skin for future divergence,
/// matching how the padding diverged in issue 76. Null on classic tokens —
/// widgets keep the pre-existing joined paragraph rendering there.
class SkinChip {
  const SkinChip({required this.gap});

  /// Vertical spacing between consecutive sentences.
  final double gap;

  @override
  bool operator ==(Object other) => other is SkinChip && other.gap == gap;

  @override
  int get hashCode => gap.hashCode;
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
  bool operator ==(Object other) {
    if (other is! SkinActions) return false;
    return _allEqual([
      other.place == place,
      other.mark == mark,
      other.erase == erase,
      other.undo == undo,
      other.hint == hint,
      other.check == check,
      other.accuse == accuse,
      other.menu == menu,
    ]);
  }

  @override
  int get hashCode =>
      Object.hash(place, mark, erase, undo, hint, check, accuse, menu);
}

/// Cartoon danger accent (issue 87): deep burnt orange so the white glyphs
/// on the accuse pill clear WCAG AA 4.5:1 (white on it measures 5.18:1;
/// the old #E8590C gave 3.58:1). Shared by candy, sticker and comic — the
/// owner approved deepening all three error/danger highlights along with
/// the toolbar.
const Color _cartoonDanger = Color(0xFFC2410C);

/// Shared cartoon toolbar palette (issue 23). The mockups show no Accuse
/// button (the app has one), so accuse takes the danger accent. Issue 87
/// retunes the palette for ink glyphs: place/menu lighten one step so the
/// skin ink on them reaches AA 4.5:1 (the other pills already do; place is
/// the thinnest pair at 4.66:1 with the weakest skin ink), and the danger
/// pill alone renders white glyphs.
const SkinActions _cartoonActions = SkinActions(
  place: Color(0xFFFF8FB3),
  mark: Color(0xFFFFA94D),
  erase: Color(0xFF38D9A9),
  undo: Color(0xFF74C0FC),
  hint: Color(0xFFFFC078),
  check: Color(0xFF51CF66),
  accuse: _cartoonDanger,
  menu: Color(0xFFC3A9FD),
);

/// Clue-sentence gap shared by the cartoon mockups (issue 26, shrunk by
/// issue 89): sentences render bare, separated by this vertical gap. Kept
/// per-skin so a skin can diverge later; classic keeps null (joined plain
/// clue paragraph).
const SkinChip _cartoonChip = SkinChip(gap: 6);

/// The default skin's clue-sentence gap (issue 76/89): issue 76 diverged the
/// token's padding to fit the phone text box; issue 89 removed the pill, so
/// sticker keeps its own token carrying the shared gap.
const SkinChip _stickerChip = SkinChip(gap: 6);

/// Victim-cell stripe pair; sticker and comic keep the mockup values, while
/// candy diverges below (issue 87).
const Color _victimFill = Color(0xFFFFC9C9);
const Color _victimStripe = Color(0xFFF47C7C);

/// The candy victim pair diverges from the shared mockup pair (issue 87):
/// #FFC9C9/#F47C7C sat within ~1.3:1 of the page and the warm room tints.
/// This pair keeps the same striped render and clears the issue's bars —
/// fill 1.64:1 vs the page and stripe 3.0:1 vs its own fill.
const Color _candyVictimFill = Color(0xFFFFB8B8);
const Color _candyVictimStripe = Color(0xFFC2435A);

/// Soft candy shadow tone: rgba(31,108,158,.14) per the issue.
const Color _candyShadow = Color(0x241F6C9E);

/// Candy's own clue-sentence gap (issue 87/89): issue 87 diverged the chip
/// background to clear 1.3:1 on the white cards; issue 89 removed the pill
/// surface, so candy keeps its own token carrying the shared gap.
const SkinChip _candyChip = SkinChip(gap: 6);

/// True when every field-equality check in [checks] holds. The skin `==`
/// helpers build their per-field comparisons eagerly: each check is a pure
/// predicate, so evaluating all of them is observably identical to the old
/// short-circuit `&&` chain (issue 35). List fields keep the identity
/// comparison they always had (`roomTints`).
bool _allEqual(List<bool> checks) {
  for (final check in checks) {
    if (!check) return false;
  }
  return true;
}

/// Карамель (style-a-candy.png): white fluffy cards on a fresh sky paper
/// with soft shadows.
///
/// Issue 87 diverges the board tokens: `roomTints` are one shade deeper
/// than the issue 23 mockup palette (every tint ≥ 1.5:1 vs the white
/// mortar plate they paint on — issue 97 split the sky page from that
/// plate; all
/// 28 pairs CIE76 ΔE ≥ 15, ≥ 12 under both Machado-0.6 deuteranopia and
/// protanopia simulation — lavender/sky pulled further apart than the
/// issue's starting pair, which collapsed to ΔE ~8 under both
/// simulations), the victim pair separates from the plate and cards, and
/// `inkSoft` reaches AA — on white it must measure ≥ 4.5:1, and it is also
/// the clue text color (onSurfaceVariant), so it is darkened past the
/// issue's starting #5A66A0 until it clears AA on white (#505D9A: 6.23:1;
/// the issue-87 chip it used to paint on was removed in issue 89). The
/// white mortar, badge, card and sheet stay untouched — the deeper tints
/// carry the board's visibility. Issue 97 returns the app page to the flat
/// mockup sky `0xFF6FCBFF` (the owner-picked white-cloud schema, restoring
/// the pre-#86 pageColor) so the white cloud-controls separate from the
/// page without borders; every control surface keeps its landed colors.
/// Pinned by test/core/skins_contrast_test.dart.
const candyTokens = SkinTokens(
  skin: SkinSetting.candy,
  isCartoon: true,
  appBackground: Color(0xFF6FCBFF),
  ink: Color(0xFF35406E),
  inkSoft: Color(0xFF505D9A),
  spriteInk: Color(0xFF1F2440), // Deepened ink: dimmed-vs-lavender 2.63:1 and core-vs-red 2.59:1 with plain ink both miss the 3:1 bar (issue 100).
  card: SkinCard(
    background: Color(0xFFFFFFFF),
    borderColor: Color(0xFFFFFFFF),
    borderWidth: 4,
    radius: 20,
    shadow: BoxShadow(color: _candyShadow, offset: Offset(0, 6)),
  ),
  roomTints: [
    Color(0xFFFF8FA6),
    Color(0xFFFFA94D),
    Color(0xFFC99145),
    Color(0xFF9C7FE8),
    Color(0xFF3BB08C),
    Color(0xFF74B6F2),
    Color(0xFF9CCB62),
    Color(0xFFD45D48),
  ],
  badge: SkinBadge(background: Color(0xFFFFFFFF), ink: Color(0xFF35406E)),
  mortarColor: Color(0xFFFFFFFF),
  solidRooms: true,
  roomRadius: 14,
  roomLineWidth: 4,
  victimFill: _candyVictimFill,
  victimStripeColor: _candyVictimStripe,
  actions: _cartoonActions,
  dangerColor: _cartoonDanger,
  buttonRadius: 14,
  buttonShadow: BoxShadow(color: _candyShadow, offset: Offset(0, 4)),
  sheetBackground: Color(0xFFFFFFFF),
  sheetRadius: 24,
  menuIcons: false,
  chip: _candyChip,
);

/// Стикеры (style-b-sticker.png): cream app background, white cards with
/// navy outlines and hard offset shadows.
const stickerTokens = SkinTokens(
  skin: SkinSetting.sticker,
  isCartoon: true,
  appBackground: Color(0xFFFFF8EF),
  ink: Color(0xFF1D3557),
  inkSoft: Color(0xFF457B9D),
  spriteInk: Color(0xFF1D3557),
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
  chip: _stickerChip,
);

/// Комикс (style-d-comic.png): white app with a black outline, hard black
/// offset shadows, uppercase chrome ink.
///
/// Radius/lineWidth pairing (issue 82): comic's 14/4 puts the wall corner
/// rounding K ≈ 3.5× the stroke half-width — right at the ~3.4 threshold
/// where a four-way junction can leave a ≤ 0.1px sub-pixel pocket at its
/// center (sticker's 10/3.5 sits safely at ≈ 2.9). If the radius grows,
/// raise the line width along with it.
const comicTokens = SkinTokens(
  skin: SkinSetting.comic,
  isCartoon: true,
  appBackground: Color(0xFFFFFFFF),
  ink: Color(0xFF111111),
  inkSoft: Color(0xFF444444),
  spriteInk: Color(0xFF111111),
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
        appBackground: scheme.surface,
        ink: scheme.onSurface,
        inkSoft: scheme.onSurfaceVariant,
        spriteInk: scheme.onSurface,
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
