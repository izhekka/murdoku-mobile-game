import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:murdoku/domain/generator/case_factory.dart'
    show casePoolGeneratorTag;
import 'package:murdoku/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language preference. `system` follows the platform locale (clamped to
/// supported locales); the app defaults to [russian].
enum LanguageSetting { system, russian, english }

/// Visual skin of the whole app (issue 23): [classic] is the original noir
/// theme; candy/sticker/comic are the light-only cartoon skins. Fresh
/// installs and legacy stored settings default to [sticker].
enum SkinSetting { classic, candy, sticker, comic }

class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.haptics = true,
    this.language = LanguageSetting.russian,
    this.skin = SkinSetting.sticker,
  });

  final ThemeMode themeMode;
  final bool haptics;
  final LanguageSetting language;
  final SkinSetting skin;

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.themeMode == themeMode &&
      other.haptics == haptics &&
      other.language == language &&
      other.skin == skin;

  @override
  int get hashCode => Object.hash(themeMode, haptics, language, skin);

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'haptics': haptics,
    'language': language.name,
    'skin': skin.name,
  };

  factory Settings.fromJson(Map<String, Object?> json) => Settings(
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == json['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    haptics: json['haptics'] as bool? ?? true,
    language: LanguageSetting.values.firstWhere(
      (l) => l.name == json['language'],
      orElse: () => LanguageSetting.russian,
    ),
    skin: SkinSetting.values.firstWhere(
      (s) => s.name == json['skin'],
      orElse: () => SkinSetting.sticker,
    ),
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

  Map<String, Object?> toJson() => {
    'lastCompletedDate': lastCompletedDate,
    'streak': streak,
  };

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
  bool operator ==(Object other) {
    if (other is! Stats) return false;
    return _allEqual([
      mapEquals(other.solved, solved),
      mapEquals(other.bestTime, bestTime),
      mapEquals(other.totalTime, totalTime),
      other.totalCases == totalCases,
    ]);
  }

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
    final solved = _mapOrEmpty(json, 'solved');
    final best = _mapOrEmpty(json, 'bestTimeSeconds');
    final total = _mapOrEmpty(json, 'totalTimeSeconds');
    _fillDifficultyStats(stats, solved, best, total);
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
  final String
  dailyDate; // yyyy-mm-dd UTC the daily was started, '' if not daily
  final BoardSnapshot board;

  @override
  bool operator ==(Object other) {
    if (other is! SavedGame) return false;
    return _allEqual([
      other.caseData == caseData,
      other.isDaily == isDaily,
      other.dailyDate == dailyDate,
      other.board == board,
    ]);
  }

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
      return _tryParse(json);
    } on Object catch (e) {
      debugPrint('SavedGame parse failed: $e');
      return null;
    }
  }

  /// Payload validation and construction for a known-good envelope; any
  /// throw is caught by [tryFromJson] and degrades to null.
  static SavedGame? _tryParse(Map<String, Object?> json) {
    if (json['v'] != 1) return null;
    final caseJson = json['caseData'];
    final boardJson = json['board'];
    if (caseJson is! Map<String, Object?> ||
        boardJson is! Map<String, Object?>) {
      return null;
    }
    return SavedGame(
      caseData: CaseData.fromJson(caseJson),
      isDaily: _boolOr(json, 'isDaily', false),
      dailyDate: _stringOr(json, 'dailyDate', ''),
      board: BoardSnapshot.fromJson(boardJson),
    );
  }
}

/// Persisted per-difficulty pools of pre-generated unstarted cases
/// (issue 108). The envelope carries `'v': 1` plus the generator-pipeline
/// tag (`'gen'`, [casePoolGeneratorTag]): malformed, unknown-version or
/// foreign-tag payloads degrade to [CasePool.empty] — a changed pipeline
/// (ADR 0007-style gating) discards stored pools instead of serving
/// stale-quality cases. Anonymous content, not progress: `resetProgress`
/// does not clear it.
class CasePool {
  const CasePool({this.byDifficulty = const {}});

  static const CasePool empty = CasePool();

  final Map<Difficulty, List<CaseData>> byDifficulty;

  @override
  bool operator ==(Object other) =>
      other is CasePool && _poolsEqual(other.byDifficulty, byDifficulty);

  /// Deep per-difficulty comparison. mapEquals compares map VALUES by
  /// identity — the values here are lists, so each pool compares deep via
  /// listEquals. A missing key and an explicitly empty list mean the same
  /// (the empty pool for that difficulty).
  static bool _poolsEqual(
    Map<Difficulty, List<CaseData>> a,
    Map<Difficulty, List<CaseData>> b,
  ) {
    for (final d in Difficulty.values) {
      if (!listEquals(a[d] ?? const <CaseData>[], b[d] ?? const <CaseData>[])) {
        return false;
      }
    }
    return true;
  }

  @override
  // Canonical difficulty order (== walks Difficulty.values too), so equal
  // pools hash equal regardless of the map's key insertion order.
  int get hashCode => Object.hashAll([
    for (final d in Difficulty.values)
      Object.hash(d, (byDifficulty[d] ?? const <CaseData>[]).length),
  ]);

  Map<String, Object?> toJson() => {
    'v': 1,
    'gen': casePoolGeneratorTag,
    for (final d in Difficulty.values)
      d.name: (byDifficulty[d] ?? const <CaseData>[])
          .map((c) => c.toJson())
          .toList(),
  };

  /// Returns null for unknown versions, foreign generator tags or malformed
  /// payloads — callers treat that as an empty pool.
  static CasePool? tryFromJson(Map<String, Object?> json) {
    try {
      return _tryParse(json);
    } on Object catch (e) {
      debugPrint('CasePool parse failed: $e');
      return null;
    }
  }

  /// Payload validation and construction for a known-good envelope; any
  /// throw is caught by [tryFromJson] and degrades to null.
  static CasePool? _tryParse(Map<String, Object?> json) {
    if (json['v'] != 1 || json['gen'] != casePoolGeneratorTag) return null;
    return CasePool(byDifficulty: _parsePools(json));
  }

  /// Per-difficulty case lists; a non-list entry throws into the
  /// [tryFromJson] guard (whole payload degrades to empty).
  static Map<Difficulty, List<CaseData>> _parsePools(
    Map<String, Object?> json,
  ) {
    final pools = <Difficulty, List<CaseData>>{};
    for (final d in Difficulty.values) {
      final raw = json[d.name];
      if (raw == null) continue;
      pools[d] = [
        for (final entry in raw as List<Object?>)
          CaseData.fromJson(entry as Map<String, Object?>),
      ];
    }
    return pools;
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
  static const _casePoolKey = 'murdoku.casePool';

  Settings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object catch (e) {
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
    } on Object catch (e) {
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
    } on Object catch (e) {
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
    } on Object catch (e) {
      debugPrint('daily state jsonDecode failed: $e');
      return const DailyState();
    }
  }

  Future<void> saveDailyState(DailyState d) =>
      _prefs.setString(_dailyKey, jsonEncode(d.toJson()));

  bool loadTutorialSeen() => _prefs.getBool(_tutorialKey) ?? false;

  Future<void> saveTutorialSeen(bool seen) =>
      _prefs.setBool(_tutorialKey, seen);

  /// The persisted case pools; absent, corrupt or foreign-tag payloads
  /// degrade to [CasePool.empty] (never crash).
  CasePool loadCasePool() {
    final raw = _prefs.getString(_casePoolKey);
    if (raw == null) return CasePool.empty;
    try {
      return CasePool.tryFromJson(jsonDecode(raw) as Map<String, Object?>) ??
          CasePool.empty;
    } on Object catch (e) {
      debugPrint('case pool jsonDecode failed: $e');
      return CasePool.empty;
    }
  }

  Future<void> saveCasePool(CasePool pool) =>
      _prefs.setString(_casePoolKey, jsonEncode(pool.toJson()));
}

/// True when every field-equality check in [checks] holds. The persisted
/// models' `==` helpers build their per-field comparisons eagerly: each
/// check is a pure predicate, so evaluating all of them is observably
/// identical to the old short-circuit `&&` chain (issue 35).
bool _allEqual(List<bool> checks) {
  for (final check in checks) {
    if (!check) return false;
  }
  return true;
}

/// A stored map field, or the empty map when the key is absent.
Map<String, Object?> _mapOrEmpty(Map<String, Object?> json, String key) =>
    json[key] as Map<String, Object?>? ?? {};

/// Fills the per-difficulty counters and durations from stored maps.
void _fillDifficultyStats(
  Stats stats,
  Map<String, Object?> solved,
  Map<String, Object?> best,
  Map<String, Object?> total,
) {
  for (final d in Difficulty.values) {
    stats.solved[d] = solved[d.name] as int? ?? 0;
    if (best[d.name] != null) {
      stats.bestTime[d] = Duration(seconds: best[d.name] as int);
    }
    if (total[d.name] != null) {
      stats.totalTime[d] = Duration(seconds: total[d.name] as int);
    }
  }
}

/// A stored bool field, or [fallback] when the key is absent or not a bool.
bool _boolOr(Map<String, Object?> json, String key, bool fallback) =>
    (json[key] as bool?) ?? fallback;

/// A stored string field, or [fallback] when the key is absent or not a
/// string.
String _stringOr(Map<String, Object?> json, String key, String fallback) =>
    (json[key] as String?) ?? fallback;
