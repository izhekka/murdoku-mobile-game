import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murdoku/domain/models.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';

/// Owns the persisted [Stats] and the daily-streak bookkeeping.
class StatsController extends Notifier<Stats> {
  @override
  Stats build() => ref.watch(prefsRepositoryProvider).loadStats();

  /// Records one solved case and updates stats (and, for dailies, the
  /// streak). Same-day daily re-wins keep the streak unchanged.
  Future<void> recordWin({
    required Difficulty difficulty,
    required Duration time,
    required int mistakes,
    required bool isDaily,
    required String dailyDate,
  }) async {
    final repo = ref.read(prefsRepositoryProvider);
    final stats = repo.loadStats();
    stats.solved[difficulty] = (stats.solved[difficulty] ?? 0) + 1;
    final best = stats.bestTime[difficulty];
    if (best == null || time < best) stats.bestTime[difficulty] = time;
    stats.totalTime[difficulty] =
        (stats.totalTime[difficulty] ?? Duration.zero) + time;
    stats.totalCases += 1;
    await repo.saveStats(stats);
    state = stats;

    await _maybeBumpStreak(repo, isDaily, dailyDate);
  }

  /// Daily-streak bookkeeping; no-op off the daily path.
  Future<void> _maybeBumpStreak(
    PrefsRepository repo,
    bool isDaily,
    String dailyDate,
  ) async {
    if (isDaily && dailyDate.isNotEmpty) {
      final daily = repo.loadDailyState();
      await repo.saveDailyState(
        DailyState(
          lastCompletedDate: dailyDate,
          streak: _newStreak(daily, dailyDate),
        ),
      );
    }
  }

  /// Same-day re-win: idempotent; yesterday: extend the streak; otherwise
  /// start a new one.
  int _newStreak(DailyState daily, String dailyDate) =>
      daily.lastCompletedDate == dailyDate
      ? daily
            .streak // same-day re-win: idempotent
      : daily.lastCompletedDate == utcYesterday(dailyDate)
      ? daily.streak + 1
      : 1;
}

final statsControllerProvider = NotifierProvider<StatsController, Stats>(
  StatsController.new,
);
