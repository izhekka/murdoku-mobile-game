import 'package:material_ui/material_ui.dart';

import 'package:murdoku/domain/models.dart';

IconData objectIcon(ObjectKind kind) => switch (kind) {
  ObjectKind.piano => Icons.piano,
  ObjectKind.plant => Icons.local_florist,
  ObjectKind.armor => Icons.shield,
  ObjectKind.chest => Icons.inventory_2,
  ObjectKind.clock => Icons.schedule,
  ObjectKind.globe => Icons.public,
  ObjectKind.portrait => Icons.portrait,
  ObjectKind.fireplace => Icons.local_fire_department,
  ObjectKind.table => Icons.table_restaurant,
  ObjectKind.chair => Icons.chair,
  ObjectKind.flowers => Icons.local_florist,
  ObjectKind.sofa => Icons.weekend,
  ObjectKind.bookshelf => Icons.shelves,
  ObjectKind.lamp => Icons.light,
};

/// Asset path for an item kind's generated sprite (tool/gen_items.dart).
String itemAssetPath(ObjectKind kind) => 'assets/items/${kind.name}.png';

/// Renders an item's generated sprite; falls back to a styled Material icon
/// when the asset is missing (e.g. assets stripped from a test context).
class ItemSprite extends StatelessWidget {
  const ItemSprite({
    super.key,
    required this.kind,
    this.size = 20,
    this.opacity = 1.0,
  });

  final ObjectKind kind;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      objectIcon(kind),
      size: size,
      color: scheme.onSurface.withValues(alpha: 0.7 * opacity),
    );
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        itemAssetPath(kind),
        width: size * 1.35,
        height: size * 1.35,
        errorBuilder: (_, _, _) => icon,
      ),
    );
  }
}
