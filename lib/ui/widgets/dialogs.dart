import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../domain/models.dart';

/// Shown after a correct accusation: time, difficulty and mistake count.
class VictoryDialog extends StatelessWidget {
  const VictoryDialog({
    super.key,
    required this.elapsed,
    required this.difficulty,
    required this.wrongAccusations,
  });

  final Duration elapsed;
  final Difficulty difficulty;
  final int wrongAccusations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final difficultyLabel = switch (difficulty) {
      Difficulty.easy => l10n.difficultyEasy,
      Difficulty.standard => l10n.difficultyStandard,
      Difficulty.hard => l10n.difficultyHard,
    };
    return AlertDialog(
      icon: const Icon(Icons.emoji_events),
      title: Text(l10n.victoryTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.victoryTime(formatDuration(elapsed))),
          Text(difficultyLabel),
          Text(l10n.victoryMistakes(wrongAccusations)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.victoryDone),
        ),
      ],
    );
  }
}

/// Two-button confirmation dialog used by quit/reveal flows.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppLocalizations.of(dialogContext)!.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
