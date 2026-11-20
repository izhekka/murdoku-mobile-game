import 'package:material_ui/material_ui.dart';

/// Noir-mystery palette: deep indigo/charcoal surfaces with an amber accent.
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFFC89B3C);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

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

  /// Vivid, distinct room tints usable on both light and dark surfaces
  /// (pairwise RGB distance > 9000 for the first 7; HSL lightness 0.45–0.75).
  static const List<Color> _roomPalette = [
    Color(0xFFE89E3C), // amber
    Color(0xFF35C290), // teal green
    Color(0xFF9A4FD0), // violet
    Color(0xFFD63E2E), // coral red
    Color(0xFF8FCB3A), // lime
    Color(0xFF3E86E0), // sky blue
    Color(0xFFE85890), // pink
    Color(0xFFD8B26E), // sand
  ];

  static List<Color> roomColors(int count) => List.generate(
      count, (i) => _roomPalette[i % _roomPalette.length]);
}
