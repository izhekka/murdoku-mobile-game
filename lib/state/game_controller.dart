import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/generator/case_factory.dart';
import '../domain/game_logic.dart' show Tool, canPlace, correctCount;
import '../domain/models.dart';
import '../storage/prefs_repository.dart';
import 'providers.dart';

enum GamePhase { playing, won, revealed }

/// A reversible player action, for undo.
sealed class _Move {
  void undo(GameNotifier notifier);
}

class _PlaceMove implements _Move {
  _PlaceMove(this.suspectId, this.pos, this.clearedMark);

  final String suspectId;
  final Pos pos;
  final bool clearedMark; // an X mark was consumed by this placement

  @override
  void undo(GameNotifier notifier) {
    notifier._placed.remove(suspectId);
    if (clearedMark) notifier._xMarks.add(pos);
  }
}

class _RemoveMove implements _Move {
  _RemoveMove(this.suspectId, this.pos);

  final String suspectId;
  final Pos pos;

  @override
  void undo(GameNotifier notifier) {
    notifier._placed[suspectId] = pos;
  }
}

class _ToggleXMove implements _Move {
  _ToggleXMove(this.pos);

  final Pos pos;

  @override
  void undo(GameNotifier notifier) {
    if (!notifier._xMarks.remove(pos)) notifier._xMarks.add(pos);
  }
}

class GameState {
  const GameState({
    required this.caseData,
    required this.phase,
    required this.placed,
    required this.xMarks,
    required this.lockedSuspects,
    required this.selectedSuspectId,
    required this.tool,
    required this.elapsed,
    required this.hintsUsed,
    required this.wrongAccusations,
    required this.isDaily,
    required this.dailyDate,
    required this.eliminatedSuspects,
  });

  final CaseData caseData;
  final GamePhase phase;
  final Map<String, Pos> placed;
  final Set<Pos> xMarks;
  final Set<String> lockedSuspects; // Hint A placements cannot be moved
  final String? selectedSuspectId;
  final Tool tool;
  final Duration elapsed;
  final int hintsUsed;
  final int wrongAccusations;
  final bool isDaily;
  final String? dailyDate; // the UTC date the daily was STARTED
  final Set<String> eliminatedSuspects;

  GameState copyWith({
    GamePhase? phase,
    String? selectedSuspectId,
    Tool? tool,
    Duration? elapsed,
  }) =>
      GameState(
        caseData: caseData,
        phase: phase ?? this.phase,
        placed: placed,
        xMarks: xMarks,
        lockedSuspects: lockedSuspects,
        selectedSuspectId: selectedSuspectId ?? this.selectedSuspectId,
        tool: tool ?? this.tool,
        elapsed: elapsed ?? this.elapsed,
        hintsUsed: hintsUsed,
        wrongAccusations: wrongAccusations,
        isDaily: isDaily,
        dailyDate: dailyDate,
        eliminatedSuspects: eliminatedSuspects,
      );
}

/// Drives one active case. Null state means no active game (home screen).
class GameNotifier extends Notifier<GameState?> {
  final _history = <_Move>[];
  late CaseData _case;
  Map<String, Pos> _placed = {};
  Set<Pos> _xMarks = {};
  Set<String> _locked = {};
  Set<String> _eliminated = {};
  Duration _elapsed = Duration.zero;
  Tool _tool = Tool.place;
  int _hintsUsed = 0;
  int _wrongAccusations = 0;
  bool _isDaily = false;
  String _dailyDate = '';

  @override
  GameState? build() => null;

  GameState? get _state => state;

  void startNewCase(Difficulty difficulty, {int? seed}) {
    _start(generateCase(
        difficulty: difficulty,
        seed: seed ??
            ref.read(forcedSeedProvider) ??
            Random().nextInt(1 << 30)),
        isDaily: false,
        dailyDate: '');
  }

  void startDaily(String utcDate, {Difficulty difficulty = Difficulty.standard}) {
    _start(
      generateCase(difficulty: difficulty, seed: dailySeedFor(_utcDate(utcDate))),
      isDaily: true,
      dailyDate: utcDate,
    );
  }

  DateTime _utcDate(String yyyyMmDd) {
    final parts = yyyyMmDd.split('-').map(int.parse).toList();
    return DateTime.utc(parts[0], parts[1], parts[2]);
  }

  void _start(CaseData c, {required bool isDaily, required String dailyDate}) {
    _case = c;
    _placed = {};
    _xMarks = {};
    _locked = {};
    _eliminated = {};
    _elapsed = Duration.zero;
    _tool = Tool.place;
    _hintsUsed = 0;
    _wrongAccusations = 0;
    _isDaily = isDaily;
    _dailyDate = dailyDate;
    _history.clear();
    state = _compose(phase: GamePhase.playing, selectedSuspectId: null);
    _persist();
  }

  GameState _compose({
    required GamePhase phase,
    String? selectedSuspectId,
  }) =>
      GameState(
        caseData: _case,
        phase: phase,
        placed: Map.of(_placed),
        xMarks: Set.of(_xMarks),
        lockedSuspects: Set.of(_locked),
        selectedSuspectId: selectedSuspectId,
        tool: _tool,
        elapsed: _elapsed,
        hintsUsed: _hintsUsed,
        wrongAccusations: _wrongAccusations,
        isDaily: _isDaily,
        dailyDate: _isDaily ? _dailyDate : null,
        eliminatedSuspects: Set.of(_eliminated),
      );

  void resume(SavedGame g) {
    _case = g.caseData;
    _placed = Map.of(g.board.placed);
    _xMarks = Set.of(g.board.xMarks);
    _locked = {}; // hints are not persisted as locked; board positions are
    _eliminated = Set.of(g.board.eliminatedSuspects);
    _elapsed = g.board.elapsed;
    _hintsUsed = g.board.hintsUsed;
    _wrongAccusations = g.board.wrongAccusations;
    _isDaily = g.isDaily;
    _dailyDate = g.dailyDate;
    _history.clear();
    state = _compose(phase: GamePhase.playing);
  }

  void selectSuspect(String? id) {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    state = s.copyWith(selectedSuspectId: id);
  }

  void setTool(Tool tool) {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    _tool = tool;
    state = s.copyWith(tool: tool);
  }

  void tapCell(Pos p) {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    switch (s.tool) {
      case Tool.place:
        _tapPlace(s, p);
      case Tool.markX:
        _toggleX(s, p);
      case Tool.erase:
        if (_xMarks.remove(p)) {
          _history.add(_ToggleXMove(p));
          _afterMove(s);
        }
    }
  }

  void _tapPlace(GameState s, Pos p) {
    final selected = s.selectedSuspectId;
    if (selected == null) return;
    if (_locked.contains(selected)) return;

    String? suspectAt;
    for (final entry in _placed.entries) {
      if (entry.value == p) {
        suspectAt = entry.key;
        break;
      }
    }
    if (suspectAt != null) {
      if (suspectAt == selected) {
        // Toggle: remove the selected suspect from its own cell.
        _placed.remove(selected);
        _history.add(_RemoveMove(selected, p));
        _afterMove(s);
      }
      // Tapping a cell occupied by ANOTHER suspect is a no-op.
      return;
    }
    if (_placed.containsKey(selected)) return; // remove before re-placing
    if (!canPlace(_case, _placed, selected, p)) return;
    final clearedMark = _xMarks.remove(p);
    _placed[selected] = p;
    _history.add(_PlaceMove(selected, p, clearedMark));
    _afterMove(s);
  }

  void _toggleX(GameState s, Pos p) {
    if (_placed.values.contains(p)) return; // never mark a suspect cell
    if (!_xMarks.remove(p)) _xMarks.add(p);
    _history.add(_ToggleXMove(p));
    _afterMove(s);
  }

  void undo() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    if (_history.isEmpty) return;
    _history.removeLast().undo(this);
    _afterMove(s);
  }

  ({int correct, int total}) runCheck() {
    final s = _state;
    if (s == null) return (correct: 0, total: 0);
    return (correct: correctCount(_case, _placed), total: _case.suspects.length);
  }

  void hintPlacement() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    if (_hintsUsed >= 2) return;
    // Only guests whose solution cell is free (never evict a wrongly placed
    // guest — that would double-occupy a cell and corrupt the board).
    String? unplaced;
    for (final id in _case.suspects.map((x) => x.id)) {
      final pos = _case.solution[id]!;
      if (!_placed.containsKey(id) && !_placed.values.contains(pos)) {
        unplaced = id;
        break;
      }
    }
    if (unplaced == null) return; // board full or every target cell blocked
    final pos = _case.solution[unplaced]!;
    _xMarks.remove(pos);
    _placed[unplaced] = pos;
    _locked.add(unplaced);
    _hintsUsed++;
    _afterMove(s);
  }

  void hintEliminate() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    if (_hintsUsed >= 2) return; // shared budget with Hint A
    final innocents = _case.suspects
        .map((x) => x.id)
        .where((id) => id != _case.murdererId && !_eliminated.contains(id))
        .toList();
    if (innocents.isEmpty) return;
    innocents.shuffle();
    _eliminated.add(innocents.first);
    _hintsUsed++;
    _afterMove(s);
  }

  /// Returns true when [suspectId] is the murderer (game won).
  bool accuse(String suspectId) {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return false;
    if (suspectId == _case.murdererId) {
      _wrongAccusations = _wrongAccusations; // unchanged on a correct accusation
      state = _compose(phase: GamePhase.won);
      unawaited(ref.read(prefsRepositoryProvider).clearActiveGame());
      return true;
    }
    _wrongAccusations++;
    _afterMove(s);
    return false;
  }

  void revealSolution() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    _placed = Map.of(_case.solution);
    _xMarks = {};
    state = _compose(phase: GamePhase.revealed);
    unawaited(ref.read(prefsRepositoryProvider).clearActiveGame());
  }

  void quit() {
    unawaited(ref.read(prefsRepositoryProvider).clearActiveGame());
    state = null;
  }

  void tick() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return;
    _elapsed += const Duration(seconds: 1);
    state = s.copyWith(elapsed: _elapsed);
    _persist();
  }

  void _afterMove(GameState s) {
    state = _compose(phase: s.phase, selectedSuspectId: s.selectedSuspectId);
    _persist();
  }

  /// Synchronous snapshot of the active game for persistence and UI reads.
  /// Null when no game is running or it is no longer playable.
  SavedGame? currentSave() {
    final s = _state;
    if (s == null || s.phase != GamePhase.playing) return null;
    return SavedGame(
      caseData: _case,
      isDaily: _isDaily,
      dailyDate: _dailyDate,
      board: BoardSnapshot(
        placed: Map.of(_placed),
        xMarks: Set.of(_xMarks),
        elapsed: _elapsed,
        hintsUsed: _hintsUsed,
        wrongAccusations: _wrongAccusations,
        eliminatedSuspects: Set.of(_eliminated),
      ),
    );
  }

  void _persist() {
    final save = currentSave();
    if (save == null) return;
    unawaited(ref.read(prefsRepositoryProvider).saveActiveGame(save));
  }
}

final gameControllerProvider =
    NotifierProvider<GameNotifier, GameState?>(GameNotifier.new);
