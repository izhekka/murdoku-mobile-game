import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/format.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart' show Stats;

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final stats = ref.watch(statsControllerProvider);
    final repo = ref.watch(prefsRepositoryProvider);
    final daily = repo.loadDailyState();

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
                title: Text(_difficultyLabel(l10n, difficulty)),
                subtitle: _statSubtitle(l10n, stats, difficulty),
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

  /// The localized difficulty label.
  String _difficultyLabel(AppLocalizations l10n, Difficulty d) => switch (d) {
    Difficulty.easy => l10n.difficultyEasy,
    Difficulty.standard => l10n.difficultyStandard,
    Difficulty.hard => l10n.difficultyHard,
  };

  /// Solved count, best time and (when solved) average time per difficulty.
  Widget _statSubtitle(AppLocalizations l10n, Stats stats, Difficulty d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.statsSolved(stats.solved[d] ?? 0)),
        if (stats.bestTime[d] != null)
          Text(l10n.statsBest(formatDuration(stats.bestTime[d]!))),
        if ((stats.solved[d] ?? 0) > 0)
          Text(l10n.statsAverage(formatDuration(_averageDuration(stats, d)))),
      ],
    );
  }

  /// Total play time over solved cases; guarded by the solved-count check
  /// above, so the divisor is never 0 in practice.
  Duration _averageDuration(Stats stats, Difficulty d) =>
      (stats.totalTime[d] ?? Duration.zero) ~/ (stats.solved[d] ?? 1);
}
