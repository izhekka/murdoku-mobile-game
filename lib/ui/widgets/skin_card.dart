import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';

/// Card in the active skin (issue 23): the classic skin keeps the stock
/// Material Card; cartoon skins render the token card (background, border,
/// radius, offset shadow) in a plain container. Same [margin] convention as
/// [Card] so layouts don't shift.
class SkinCard extends StatelessWidget {
  const SkinCard({super.key, this.margin, required this.child});

  final EdgeInsetsGeometry? margin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SkinScope.maybeOf(context);
    if (tokens == null || !tokens.isCartoon) {
      return Card(margin: margin, child: child);
    }
    final card = tokens.card;
    return Padding(
      padding: margin ?? const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: card.background,
          borderRadius: BorderRadius.circular(card.radius),
          border: Border.all(color: card.borderColor, width: card.borderWidth),
          boxShadow: [card.shadow],
        ),
        // ListTiles paint their ink on the nearest Material; a transparent
        // one keeps splashes visible under the token container.
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
