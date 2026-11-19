import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../state/stats_controller.dart';
import '../../state/providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final stats = ref.watch(statsControllerProvider);
    final repo = ref.watch(prefsRepositoryProvider);
    final daily = repo.loadDailyState();

    String difficultyLabel(Difficulty d) => switch (d) {
          Difficulty.easy => l10n.difficultyEasy,
          Difficulty.standard => l10n.difficultyStandard,
          Difficulty.hard => l10n.difficultyHard,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (stats.totalCases == 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.statsEmpty, textAlign: TextAlign.center),
              ),
            ),
          for (final difficulty in Difficulty.values)
            Card(
              child: ListTile(
                title: Text(difficultyLabel(difficulty)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.statsSolved(stats.solved[difficulty] ?? 0)),
                    if (stats.bestTime[difficulty] != null)
                      Text(l10n.statsBest(
                          formatDuration(stats.bestTime[difficulty]!))),
                    if ((stats.solved[difficulty] ?? 0) > 0)
                      Text(l10n.statsAverage(formatDuration(
                          (stats.totalTime[difficulty] ?? Duration.zero) ~/
                              (stats.solved[difficulty] ?? 1)))),
                  ],
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_fire_department),
              title: Text(l10n.currentStreak(daily.streak)),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory),
              title: Text(l10n.totalCasesLabel(stats.totalCases)),
            ),
          ),
        ],
      ),
    );
  }
}
