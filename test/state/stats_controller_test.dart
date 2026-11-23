import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/stats_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/widgets/accuse_sheet.dart';
import 'package:murdoku/ui/widgets/dialogs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/seeded_overrides.dart';

Pos p(int row, int col) => (row: row, col: col);

final CaseData accuseFixture = CaseData(
  seed: 1,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(
      id: 'r0',
      name: 'Hall',
      cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)],
    ),
    RoomDef(
      id: 'r1',
      name: 'Library',
      cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)],
    ),
    RoomDef(
      id: 'r2',
      name: 'Kitchen',
      cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)],
    ),
    RoomDef(
      id: 'r3',
      name: 'Cellar',
      cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)],
    ),
    RoomDef(
      id: 'r4',
      name: 'Study',
      cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)],
    ),
  ],
  objects: const [],
  suspects: [
    const Suspect(id: 's0', name: 'Ash'),
    const Suspect(id: 's1', name: 'Blair'),
    const Suspect(id: 's2', name: 'Casey'),
  ],
  victimPos: p(2, 2),
  murdererId: 's2',
  clues: const [],
  solution: {'s0': p(0, 0), 's1': p(1, 4), 's2': p(2, 1)},
);

Future<ProviderContainer> makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: seededOverrides(prefs));
}

void main() {
  test('first win initializes all stats', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(statsControllerProvider.notifier);

    await notifier.recordWin(
      difficulty: Difficulty.easy,
      time: const Duration(seconds: 95),
      mistakes: 1,
      isDaily: false,
      dailyDate: '',
    );

    final stats = container.read(statsControllerProvider);
    expect(stats.solved[Difficulty.easy], 1);
    expect(stats.bestTime[Difficulty.easy], const Duration(seconds: 95));
    expect(stats.totalTime[Difficulty.easy], const Duration(seconds: 95));
    expect(stats.totalCases, 1);
  });

  test('second faster win updates best and accumulates total', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(statsControllerProvider.notifier);

    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 4),
      mistakes: 0,
      isDaily: false,
      dailyDate: '',
    );
    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 2, seconds: 30),
      mistakes: 0,
      isDaily: false,
      dailyDate: '',
    );

    final stats = container.read(statsControllerProvider);
    expect(stats.solved[Difficulty.standard], 2);
    expect(
      stats.bestTime[Difficulty.standard],
      const Duration(minutes: 2, seconds: 30),
    );
    expect(
      stats.totalTime[Difficulty.standard],
      const Duration(minutes: 6, seconds: 30),
    );
    expect(stats.totalCases, 2);
  });

  test('daily streak continues, breaks, and is same-day idempotent', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    final repo = container.read(prefsRepositoryProvider);
    final notifier = container.read(statsControllerProvider.notifier);

    // Day 1: streak 1.
    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 3),
      mistakes: 0,
      isDaily: true,
      dailyDate: '2026-11-19',
    );
    expect(repo.loadDailyState().streak, 1);
    expect(repo.loadDailyState().lastCompletedDate, '2026-11-19');

    // Simulate having played the previous day: continue the streak.
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-18', streak: 1),
    );
    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 3),
      mistakes: 0,
      isDaily: true,
      dailyDate: '2026-11-19',
    );
    expect(repo.loadDailyState().streak, 2);

    // Broken streak: gap day.
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-15', streak: 4),
    );
    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 3),
      mistakes: 0,
      isDaily: true,
      dailyDate: '2026-11-19',
    );
    expect(repo.loadDailyState().streak, 1);

    // Same-day re-win: streak unchanged, solved count still grows.
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-19', streak: 3),
    );
    final solvedBefore = container
        .read(statsControllerProvider)
        .solved[Difficulty.standard];
    await notifier.recordWin(
      difficulty: Difficulty.standard,
      time: const Duration(minutes: 3),
      mistakes: 0,
      isDaily: true,
      dailyDate: '2026-11-19',
    );
    expect(repo.loadDailyState().streak, 3);
    expect(
      container.read(statsControllerProvider).solved[Difficulty.standard],
      solvedBefore! + 1,
    );
  });

  testWidgets('accuse sheet disables eliminated suspects', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AccuseSheet(
            caseData: accuseFixture,
            eliminatedSuspects: {'s0'},
          ),
        ),
      ),
    );
    await tester.pump();

    final ashTile = find.ancestor(
      of: find.text('Ash'),
      matching: find.byType(ListTile),
    );
    final ash = tester.widget<ListTile>(ashTile.first);
    expect(ash.enabled, isFalse);
    final caseyTile = find.ancestor(
      of: find.text('Casey'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(caseyTile.first).enabled, isTrue);
  });

  testWidgets('victory dialog shows the formatted time and mistakes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VictoryDialog(
            elapsed: const Duration(seconds: 95),
            difficulty: Difficulty.easy,
            wrongAccusations: 2,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Time: 01:35'), findsOneWidget);
    expect(find.text('Mistakes: 2'), findsOneWidget);
  });
}
