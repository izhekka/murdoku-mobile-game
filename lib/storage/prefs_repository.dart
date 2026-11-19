import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

class Settings {
  const Settings({this.themeMode = ThemeMode.system, this.haptics = true});

  final ThemeMode themeMode;
  final bool haptics;

  @override
  bool operator ==(Object other) =>
      other is Settings && other.themeMode == themeMode && other.haptics == haptics;

  @override
  int get hashCode => Object.hash(themeMode, haptics);

  Map<String, Object?> toJson() => {'themeMode': themeMode.name, 'haptics': haptics};

  factory Settings.fromJson(Map<String, Object?> json) => Settings(
        themeMode: ThemeMode.values
            .firstWhere((m) => m.name == json['themeMode'], orElse: () => ThemeMode.system),
        haptics: json['haptics'] as bool? ?? true,
      );
}

class DailyState {
  const DailyState({this.lastCompletedDate = '', this.streak = 0});

  final String lastCompletedDate; // yyyy-mm-dd UTC, '' when never completed
  final int streak;

  @override
  bool operator ==(Object other) =>
      other is DailyState &&
      other.lastCompletedDate == lastCompletedDate &&
      other.streak == streak;

  @override
  int get hashCode => Object.hash(lastCompletedDate, streak);

  Map<String, Object?> toJson() =>
      {'lastCompletedDate': lastCompletedDate, 'streak': streak};

  factory DailyState.fromJson(Map<String, Object?> json) => DailyState(
        lastCompletedDate: json['lastCompletedDate'] as String? ?? '',
        streak: json['streak'] as int? ?? 0,
      );
}

class Stats {
  Stats()
      : solved = {for (final d in Difficulty.values) d: 0},
        bestTime = {},
        totalTime = {},
        totalCases = 0;

  final Map<Difficulty, int> solved;
  final Map<Difficulty, Duration> bestTime;
  final Map<Difficulty, Duration> totalTime;
  int totalCases;

  @override
  bool operator ==(Object other) =>
      other is Stats &&
      _statsMapEqual(other.solved, solved) &&
      _durationMapEqual(other.bestTime, bestTime) &&
      _durationMapEqual(other.totalTime, totalTime) &&
      other.totalCases == totalCases;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(solved.values),
        Object.hashAll(bestTime.values),
        Object.hashAll(totalTime.values),
        totalCases,
      );

  Map<String, Object?> toJson() => {
        'solved': solved.map((k, v) => MapEntry(k.name, v)),
        'bestTimeSeconds': bestTime.map((k, v) => MapEntry(k.name, v.inSeconds)),
        'totalTimeSeconds': totalTime.map((k, v) => MapEntry(k.name, v.inSeconds)),
        'totalCases': totalCases,
      };

  factory Stats.fromJson(Map<String, Object?> json) {
    final stats = Stats();
    final solved = json['solved'] as Map<String, Object?>? ?? {};
    final best = json['bestTimeSeconds'] as Map<String, Object?>? ?? {};
    final total = json['totalTimeSeconds'] as Map<String, Object?>? ?? {};
    for (final d in Difficulty.values) {
      stats.solved[d] = solved[d.name] as int? ?? 0;
      if (best[d.name] != null) {
        stats.bestTime[d] = Duration(seconds: best[d.name] as int);
      }
      if (total[d.name] != null) {
        stats.totalTime[d] = Duration(seconds: total[d.name] as int);
      }
    }
    stats.totalCases = json['totalCases'] as int? ?? 0;
    return stats;
  }
}

class SavedGame {
  const SavedGame({
    required this.caseData,
    required this.isDaily,
    required this.dailyDate,
    required this.board,
  });

  final CaseData caseData;
  final bool isDaily;
  final String dailyDate; // yyyy-mm-dd UTC the daily was started, '' if not daily
  final BoardSnapshot board;

  @override
  bool operator ==(Object other) =>
      other is SavedGame &&
      other.caseData == caseData &&
      other.isDaily == isDaily &&
      other.dailyDate == dailyDate &&
      other.board == board;

  @override
  int get hashCode => Object.hash(caseData, isDaily, dailyDate, board);

  Map<String, Object?> toJson() => {
        'v': 1,
        'caseData': caseData.toJson(),
        'isDaily': isDaily,
        'dailyDate': dailyDate,
        'board': board.toJson(),
      };

  /// Returns null for unknown versions or malformed payloads — callers must
  /// treat that as "no save".
  static SavedGame? tryFromJson(Map<String, Object?> json) {
    try {
      if (json['v'] != 1) return null;
      final caseJson = json['caseData'];
      final boardJson = json['board'];
      if (caseJson is! Map<String, Object?> || boardJson is! Map<String, Object?>) {
        return null;
      }
      return SavedGame(
        caseData: CaseData.fromJson(caseJson),
        isDaily: json['isDaily'] as bool? ?? false,
        dailyDate: json['dailyDate'] as String? ?? '',
        board: BoardSnapshot.fromJson(boardJson),
      );
    } catch (e) {
      debugPrint('SavedGame parse failed: $e');
      return null;
    }
  }
}

class PrefsRepository {
  PrefsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _settingsKey = 'murdoku.settings';
  static const _activeGameKey = 'murdoku.activeGame';
  static const _statsKey = 'murdoku.stats';
  static const _dailyKey = 'murdoku.daily';
  static const _tutorialKey = 'murdoku.tutorialSeen';

  Settings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      debugPrint('settings jsonDecode failed: $e');
      return const Settings();
    }
  }

  Future<void> saveSettings(Settings s) =>
      _prefs.setString(_settingsKey, jsonEncode(s.toJson()));

  SavedGame? loadActiveGame() {
    final raw = _prefs.getString(_activeGameKey);
    if (raw == null) return null;
    try {
      return SavedGame.tryFromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      debugPrint('active game jsonDecode failed: $e');
      return null;
    }
  }

  Future<void> saveActiveGame(SavedGame g) =>
      _prefs.setString(_activeGameKey, jsonEncode(g.toJson()));

  Future<void> clearActiveGame() => _prefs.remove(_activeGameKey);

  /// Clears saves, statistics and the daily streak; settings are kept.
  Future<void> resetProgress() async {
    await _prefs.remove(_activeGameKey);
    await _prefs.remove(_statsKey);
    await _prefs.remove(_dailyKey);
  }

  Stats loadStats() {
    final raw = _prefs.getString(_statsKey);
    if (raw == null) return Stats();
    try {
      return Stats.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      debugPrint('stats jsonDecode failed: $e');
      return Stats();
    }
  }

  Future<void> saveStats(Stats s) =>
      _prefs.setString(_statsKey, jsonEncode(s.toJson()));

  DailyState loadDailyState() {
    final raw = _prefs.getString(_dailyKey);
    if (raw == null) return const DailyState();
    try {
      return DailyState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      debugPrint('daily state jsonDecode failed: $e');
      return const DailyState();
    }
  }

  Future<void> saveDailyState(DailyState d) =>
      _prefs.setString(_dailyKey, jsonEncode(d.toJson()));

  bool loadTutorialSeen() => _prefs.getBool(_tutorialKey) ?? false;

  Future<void> saveTutorialSeen(bool seen) =>
      _prefs.setBool(_tutorialKey, seen);
}

bool _statsMapEqual<M extends Enum, V>(Map<M, V> a, Map<M, V> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (b[key] != a[key]) return false;
  }
  return true;
}

bool _durationMapEqual(Map<Difficulty, Duration> a, Map<Difficulty, Duration> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (b[key] != a[key]) return false;
  }
  return true;
}
