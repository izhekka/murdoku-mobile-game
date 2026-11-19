import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

/// Compact 5x5 case fixture with every clue subtype.
CaseData fixtureCase() => CaseData(
      seed: 42,
      difficulty: Difficulty.easy,
      rooms: [
        RoomDef(id: 'r0', name: 'Hall', cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)]),
        RoomDef(id: 'r1', name: 'Library', cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)]),
        RoomDef(id: 'r2', name: 'Kitchen', cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)]),
        RoomDef(id: 'r3', name: 'Cellar', cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)]),
        RoomDef(id: 'r4', name: 'Study', cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)]),
      ],
      objects: [
        ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 1)),
        ObjectDef(id: 'o1', kind: ObjectKind.clock, pos: p(4, 4)),
      ],
      suspects: List.generate(5, (i) => Suspect(id: 's$i', name: 'Guest $i')),
      victimPos: p(2, 2),
      murdererId: 's2',
      clues: [
        InRoom(suspectId: 's0', roomId: 'r0', negated: false),
        InRoom(suspectId: 's1', roomId: 'r1', negated: true),
        SameRow(suspectId: 's2', targetId: 'V', negated: false),
        SameRow(suspectId: 's0', targetId: 's4', negated: true),
        SameCol(suspectId: 's1', targetId: 's3', negated: false),
        SameCol(suspectId: 's2', targetId: 'V', negated: true),
        DirectionClue(
            suspectId: 's3', targetId: 'V', direction: Direction.north, negated: false),
        DirectionClue(
            suspectId: 's4', targetId: 's0', direction: Direction.west, negated: true),
        Beside(suspectId: 's0', targetId: 's1', negated: false),
        Beside(suspectId: 's3', targetId: 's4', negated: true),
        BesideObject(suspectId: 's2', objectId: 'o0', negated: false),
        BesideObject(suspectId: 's4', objectId: 'o1', negated: true),
      ],
      solution: {
        's0': p(0, 0),
        's1': p(1, 4),
        's2': p(2, 1),
        's3': p(3, 3),
        's4': p(4, 2),
      },
    );

SavedGame fixtureGame() => SavedGame(
      caseData: fixtureCase(),
      isDaily: true,
      dailyDate: '2026-11-19',
      board: BoardSnapshot(
        placed: {'s0': p(0, 0), 's2': p(2, 1)},
        xMarks: {p(3, 3), p(4, 4)},
        elapsed: const Duration(seconds: 125),
        hintsUsed: 1,
        wrongAccusations: 2,
        eliminatedSuspects: {'s1'},
      ),
    );

void main() {
  late SharedPreferences prefs;
  late PrefsRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance().then((value) {
      prefs = value;
      repo = PrefsRepository(value);
    });
  });

  test('defaults on empty storage', () async {
    expect(repo.loadSettings().themeMode, ThemeMode.system);
    expect(repo.loadSettings().haptics, isTrue);
    expect(repo.loadActiveGame(), isNull);
    final stats = repo.loadStats();
    expect(stats.totalCases, 0);
    expect(stats.solved[Difficulty.easy] ?? 0, 0);
    expect(stats.bestTime[Difficulty.hard] ?? Duration.zero, Duration.zero);
    expect(repo.loadDailyState().lastCompletedDate, '');
    expect(repo.loadDailyState().streak, 0);
  });

  test('settings round-trip', () async {
    await repo.saveSettings(const Settings(themeMode: ThemeMode.dark, haptics: false));
    expect(repo.loadSettings(), const Settings(themeMode: ThemeMode.dark, haptics: false));
  });

  test('stats round-trip', () async {
    final stats = Stats()
      ..solved[Difficulty.easy] = 3
      ..bestTime[Difficulty.easy] = const Duration(seconds: 95)
      ..totalTime[Difficulty.easy] = const Duration(minutes: 7)
      ..totalCases = 4;
    await repo.saveStats(stats);
    final loaded = repo.loadStats();
    expect(loaded.solved[Difficulty.easy], 3);
    expect(loaded.bestTime[Difficulty.easy], const Duration(seconds: 95));
    expect(loaded.totalTime[Difficulty.easy], const Duration(minutes: 7));
    expect(loaded.totalCases, 4);
  });

  test('daily state round-trip', () async {
    await repo.saveDailyState(const DailyState(lastCompletedDate: '2026-11-18', streak: 7));
    expect(repo.loadDailyState(), const DailyState(lastCompletedDate: '2026-11-18', streak: 7));
  });

  test('saved game round-trip with full case and board snapshot', () async {
    await repo.saveActiveGame(fixtureGame());
    final loaded = repo.loadActiveGame();
    expect(loaded, isNotNull);
    expect(loaded!.caseData, fixtureCase());
    expect(loaded.isDaily, isTrue);
    expect(loaded.dailyDate, '2026-11-19');
    expect(loaded.board.placed, fixtureGame().board.placed);
    expect(loaded.board.xMarks, fixtureGame().board.xMarks);
    expect(loaded.board.elapsed, const Duration(seconds: 125));
    expect(loaded.board.hintsUsed, 1);
    expect(loaded.board.wrongAccusations, 2);
    expect(loaded.board.eliminatedSuspects, {'s1'});
  });

  test('clearActiveGame removes the save', () async {
    await repo.saveActiveGame(fixtureGame());
    await repo.clearActiveGame();
    expect(repo.loadActiveGame(), isNull);
  });

  test('corrupt payloads return null instead of throwing', () async {
    const key = 'murdoku.activeGame';
    await prefs.setString(key, '{not json');
    expect(repo.loadActiveGame(), isNull);
    await prefs.setString(key, '{}');
    expect(repo.loadActiveGame(), isNull);
    await prefs.setString(key, '{"v": 99, "caseData": {}}');
    expect(repo.loadActiveGame(), isNull);
  });

  test('saved payload carries version key v: 1', () async {
    await repo.saveActiveGame(fixtureGame());
    expect(prefs.getString('murdoku.activeGame'), contains('"v":1'));
  });
}
