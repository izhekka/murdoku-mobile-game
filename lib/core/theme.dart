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

  /// Muted, distinct room tints usable on both light and dark surfaces.
  static const List<Color> _roomPalette = [
    Color(0xFF7D9D9C), // sage teal
    Color(0xFFB0885B), // ochre clay
    Color(0xFF9A8FBF), // dusty indigo
    Color(0xFFB77B7B), // muted rose
    Color(0xFF8FAF6E), // olive
    Color(0xFF6E9EC1), // slate blue
    Color(0xFFA98BC4), // plum
    Color(0xFFC4A16E), // sand
  ];

  static List<Color> roomColors(int count) => List.generate(
      count, (i) => _roomPalette[i % _roomPalette.length]);
}
