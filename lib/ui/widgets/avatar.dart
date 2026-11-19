import 'package:material_ui/material_ui.dart';

/// Distinct suspect colors (independent from room tints).
const List<Color> suspectColors = [
  Color(0xFF3E6B8C), // steel blue
  Color(0xFF8C3E55), // wine
  Color(0xFF3E8C5A), // forest
  Color(0xFF6B3E8C), // violet
  Color(0xFF8C6B3E), // bronze
  Color(0xFF3E8C8C), // teal
  Color(0xFF8C553E), // rust
  Color(0xFF558C3E), // moss
];

Color suspectColor(int index) =>
    suspectColors[index % suspectColors.length];

/// A suspect portrait: colored circle with a person glyph. No image assets.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.color,
    required this.selected,
    this.size = 40,
  });

  final Color color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: Icon(
        Icons.person,
        size: size * 0.7,
        color: Colors.white,
      ),
    );
    if (!selected) return inner;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
      child: inner,
    );
  }
}
