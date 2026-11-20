import 'package:material_ui/material_ui.dart';

/// Distinct suspect colors (independent from room tints), bright enough to
/// pop on dark surfaces while keeping ~4:1 contrast under the white glyph.
const List<Color> suspectColors = [
  Color(0xFF4E86B8), // steel blue
  Color(0xFFC05A78), // wine
  Color(0xFF4EA870), // forest
  Color(0xFF8C5AB8), // violet
  Color(0xFFC08848), // bronze
  Color(0xFF48A8A8), // teal
  Color(0xFFC07048), // rust
  Color(0xFF74A84C), // moss
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
