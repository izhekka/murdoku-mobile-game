import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/skins.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';

/// Mid-game pause menu (issue #11): a bottom sheet with Resume, How to play,
/// Settings and Abandon case. Follows home's difficulty-sheet pattern
/// (`showModalBottomSheet` + `ListTile`s). How to play and Settings push
/// above the game, so Back returns to the running case with state intact.
///
/// Cartoon skins (issue 23 owner refinement) render a clean icon-free list
/// card instead: no per-item icons or button backgrounds, hairline
/// separators only, and «Покинуть дело» keeps an orange danger accent. The
/// classic skin keeps the icon ListTile list.
class PauseMenuSheet extends StatelessWidget {
  const PauseMenuSheet({super.key, required this.onAbandon});

  /// Runs after the sheet is closed when Abandon case is tapped; the game
  /// screen wires it to its existing quit-confirmation dialog flow.
  final VoidCallback onAbandon;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAbandon,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => PauseMenuSheet(onAbandon: onAbandon),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tokens = SkinScope.maybeOf(context);
    final cartoon = tokens != null && tokens.isCartoon;
    // Resolve the router while the sheet is still mounted: after the pop the
    // sheet context is defunct and can no longer look up ancestors.
    void popThenPush(String location) {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push(location);
    }

    Widget title = Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        l10n.pauseMenuTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );

    Widget body;
    if (cartoon) {
      Widget row(String label, VoidCallback onTap, {Color? color}) => InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            label,
            style: TextStyle(
              color: color ?? tokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      final hairline = tokens.ink.withValues(alpha: 0.12);
      Widget separator() => Divider(height: 1, thickness: 1, color: hairline);
      body = Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.card.background,
          borderRadius: BorderRadius.circular(tokens.card.radius),
          border: Border.all(
            color: tokens.card.borderColor,
            width: tokens.card.borderWidth,
          ),
          boxShadow: [tokens.card.shadow],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            separator(),
            row(l10n.resume, () => Navigator.of(context).pop()),
            separator(),
            row(l10n.howToPlayTitle, () => popThenPush('/how-to-play')),
            separator(),
            row(l10n.settingsTitle, () => popThenPush('/settings')),
            separator(),
            row(l10n.abandonCase, () {
              Navigator.of(context).pop();
              onAbandon();
            }, color: tokens.dangerColor),
          ],
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(l10n.resume),
            onTap: () => Navigator.of(context).pop(),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: Text(l10n.howToPlayTitle),
            onTap: () => popThenPush('/how-to-play'),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(l10n.settingsTitle),
            onTap: () => popThenPush('/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.abandonCase),
            onTap: () {
              Navigator.of(context).pop();
              onAbandon();
            },
          ),
        ],
      );
    }

    return SafeArea(child: body);
  }
}
