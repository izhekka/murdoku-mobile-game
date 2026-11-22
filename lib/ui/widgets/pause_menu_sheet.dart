import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Mid-game pause menu (issue #11): a bottom sheet with Resume, How to play,
/// Settings and Abandon case. Follows home's difficulty-sheet pattern
/// (`showModalBottomSheet` + `ListTile`s). How to play and Settings push
/// above the game, so Back returns to the running case with state intact.
class PauseMenuSheet extends StatelessWidget {
  const PauseMenuSheet({super.key, required this.onAbandon});

  /// Runs after the sheet is closed when Abandon case is tapped; the game
  /// screen wires it to its existing quit-confirmation dialog flow.
  final VoidCallback onAbandon;

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onAbandon,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => PauseMenuSheet(onAbandon: onAbandon),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Resolve the router while the sheet is still mounted: after the pop the
    // sheet context is defunct and can no longer look up ancestors.
    void popThenPush(String location) {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push(location);
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.pauseMenuTitle,
                style: Theme.of(context).textTheme.titleMedium),
          ),
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
      ),
    );
  }
}
