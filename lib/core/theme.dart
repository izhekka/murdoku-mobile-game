import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/storage/prefs_repository.dart' show SkinSetting;

/// Maps skins to ThemeData (issue 23): the classic noir palette (deep
/// indigo/charcoal surfaces with an amber accent) keeps its light/dark
/// pair; the cartoon skins are light-only designs built from their
/// SkinTokens (dark requests fall back to the skin's light theme).
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFFC89B3C);

  /// Cached singletons: forSkin(classic, …) returns these very instances,
  /// and every access shares one construction.
  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  /// Theme for the given skin: classic returns the existing light/dark
  /// singletons untouched (byte-identical rendering); cartoon skins always
  /// return a light theme seeded from their tokens.
  static ThemeData forSkin(SkinSetting skin, Brightness brightness) {
    if (skin == SkinSetting.classic) {
      return brightness == Brightness.dark ? dark : light;
    }
    return _buildCartoon(skinTokensFor(skin, light.colorScheme));
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
      ),
    );
  }

  /// Light-only ThemeData for a cartoon skin, seeded from its ink and
  /// overridden with the token surfaces so stock Material chrome (scaffold,
  /// app bar, dialogs, sheets, cards) matches the skin.
  static ThemeData _buildCartoon(SkinTokens t) {
    final scheme = ColorScheme.fromSeed(seedColor: t.ink).copyWith(
      surface: t.appBackground,
      onSurface: t.ink,
      onSurfaceVariant: t.inkSoft,
      outline: t.mortarColor,
      outlineVariant: t.card.borderColor,
      error: t.dangerColor,
      primary: t.ink,
      onPrimary: t.appBackground,
      primaryContainer: t.card.background,
      onPrimaryContainer: t.ink,
      secondaryContainer: t.badge.background,
      onSecondaryContainer: t.badge.ink,
      surfaceContainerHighest: t.card.background,
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(t.card.radius),
      side: BorderSide(color: t.card.borderColor, width: t.card.borderWidth),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: t.appBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: t.appBackground,
        foregroundColor: t.ink,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: t.card.background,
        elevation: 0,
        shape: cardShape,
        margin: const EdgeInsets.all(8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.sheetBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.sheetRadius),
          side: BorderSide(
            color: t.card.borderColor,
            width: t.card.borderWidth,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.sheetBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(t.sheetRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.ink,
          foregroundColor: t.appBackground,
        ),
      ),
      dividerTheme: DividerThemeData(color: t.ink.withValues(alpha: 0.12)),
    );
  }

  /// Room tints of the given skin, extended/wrapped to [count]. Classic
  /// keeps the vivid noir palette; cartoon skins use their mockup tints
  /// extended to 8 distinct entries (hard difficulty).
  static List<Color> roomColors(
    int count, [
    SkinSetting skin = SkinSetting.classic,
  ]) {
    final tints = skinTokensFor(skin, light.colorScheme).roomTints;
    return List.generate(count, (i) => tints[i % tints.length]);
  }
}
