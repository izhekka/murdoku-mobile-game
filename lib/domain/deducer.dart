/// Pure-Dart deduction engine for Murdoku cases (issue #106).
///
/// Verifies — and lets the generator require — that the shipped clue cards,
/// applied step by step, force every guest's exact cell: a chain of
/// deductions from the visible cards alone, never trial-and-error search.
/// The engine keeps a candidate cell set per suspect (a two-word bitmask
/// over g² ≤ 81 cells) and drives it to a fixpoint with:
///
/// 1. clue filters for all nine kinds — the room-, item-room- and target-
///    bearing kinds in both polarities (arc-consistent on the relation: a
///    binary clue filters BOTH involved guests, including while both are
///    unplaced), the object-cell kinds positive-only (negated
///    SoleNearObject is rejected);
/// 2. structural propagation — a placed guest's cell, row, column and room
///    leave every other unplaced guest's candidates;
/// 3. tiered placement rules ([DeduceTier]): easy = naked + hidden singles;
///    standard/hard add uniqueness probes (a hypothesized placement that
///    leads to a contradiction eliminates that cell).
///
/// Every step is a sound elimination (only entailed conclusions), so a full
/// trace implies a unique solution (`countSolutions == 1`). The engine is
/// deterministic: same input → same trace (fixed iteration order, no rng).
/// The trace is the written solution-hint algorithm; it is a
/// test/measurement artifact and is NOT stored in `CaseData`. Imports only
/// `models.dart`, so it stays testable in isolation and issue #98 can build
/// on it.
library;

import 'package:murdoku/domain/models.dart';

/// Which placement rules the engine may use (owner-picked tiers, issue #106).
enum DeduceTier {
  /// Tier 1 — naked and hidden singles only (easy). A stall means the case
  /// is not chain-solvable under this tier.
  singles,

  /// Tier 3 — tier 1 plus uniqueness probes when propagation stalls
  /// (standard and hard).
  probes,
}

/// The tier a difficulty generates under: easy stays on the strict tier 1,
/// standard and hard may use uniqueness probes.
DeduceTier deduceTierFor(Difficulty difficulty) =>
    difficulty == Difficulty.easy ? DeduceTier.singles : DeduceTier.probes;

/// Which rule placed a guest — the trace step's "because".
enum DeduceRule {
  /// The guest's candidate set had shrunk to exactly one cell.
  nakedSingle,

  /// A row/column/room only this unplaced guest could still take.
  hiddenSingle,
}

/// One placed guest in the ordered placement trace.
class DeduceStep {
  const DeduceStep({
    required this.guestId,
    required this.cell,
    required this.rule,
  });

  final String guestId;
  final Pos cell;
  final DeduceRule rule;

  @override
  bool operator ==(Object other) =>
      other is DeduceStep &&
      other.guestId == guestId &&
      other.cell == cell &&
      other.rule == rule;

  @override
  int get hashCode => Object.hash(DeduceStep, guestId, cell, rule);

  @override
  String toString() => '$guestId→(${cell.row},${cell.col}) ${rule.name}';
}

/// Two-word bitmask over g² ≤ 81 candidate cells: bits 0..62 live in [lo],
/// bits 63..80 in [hi] as bit i−63. Cell index = row·g + col. Mutating value
/// ops (intersect/subtract return whether anything changed) so the fixpoint
/// loop can stop exactly when propagation is done.
class _Mask {
  _Mask();

  _Mask._(this.lo, this.hi);

  int lo = 0;
  int hi = 0;

  _Mask copy() => _Mask._(lo, hi);

  bool contains(int i) =>
      i < 63 ? (lo >> i) & 1 == 1 : (hi >> (i - 63)) & 1 == 1;

  void set(int i) {
    if (i < 63) {
      lo |= 1 << i;
    } else {
      hi |= 1 << (i - 63);
    }
  }

  void clear(int i) {
    if (i < 63) {
      lo &= ~(1 << i);
    } else {
      hi &= ~(1 << (i - 63));
    }
  }

  bool get isEmpty => lo == 0 && hi == 0;

  int get length => _popcount(lo) + _popcount(hi);

  /// Intersects in place with [other]; true when anything changed.
  bool intersect(_Mask other) {
    final nLo = lo & other.lo;
    final nHi = hi & other.hi;
    final changed = nLo != lo || nHi != hi;
    lo = nLo;
    hi = nHi;
    return changed;
  }

  /// Removes [other]'s bits in place; true when anything changed.
  bool subtract(_Mask other) {
    final nLo = lo & ~other.lo;
    final nHi = hi & ~other.hi;
    final changed = nLo != lo || nHi != hi;
    lo = nLo;
    hi = nHi;
    return changed;
  }

  /// Set cell indices, ascending.
  List<int> cells(int total) => [
    for (var i = 0; i < total; i++)
      if (contains(i)) i,
  ];
}

/// True when [m] and [cands] share at least one cell.
bool _hits(_Mask cands, _Mask m) =>
    (cands.lo & m.lo) != 0 || (cands.hi & m.hi) != 0;

/// Parallel bit count over a non-negative 64-bit word.
int _popcount(int x) {
  x = x - ((x >> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f;
  return (x * 0x0101010101010101) >>> 56;
}

/// Immutable per-case precomputation: house masks, row/column strip masks,
/// neighbor masks and the init candidate mask. Built once per [Deducer];
/// states are cheap masks over it.
class _Env {
  _Env({
    required int gridSize,
    required List<RoomDef> rooms,
    required this.clues,
    required this.suspectIds,
    required Pos victimPos,
    required List<ObjectDef> objects,
  }) : g = gridSize,
       n = gridSize * gridSize,
       suspectCount = suspectIds.length {
    _buildLookups(suspectIds, rooms, objects);
    _buildHouseMasks(rooms);
    _buildRowStrips();
    _buildColStrips();
    _buildNeighborMasks();
    _buildInitMask(objects, victimPos);
    victimRow = victimPos.row;
    victimCol = victimPos.col;
    victimBesideMask = neighborMask[victimPos.row * g + victimPos.col];
  }

  final int g;
  final int n;
  final int suspectCount;
  final List<Clue> clues;
  final List<String> suspectIds;

  late final Map<String, int> indexOf;
  late final Map<String, int> roomIndexOf;
  late final Map<String, ObjectDef> objectById;
  late final List<_Mask> rowMask;
  late final List<_Mask> colMask;
  late final List<_Mask> roomMask;
  late final List<_Mask> cellRowMask;
  late final List<_Mask> cellColMask;
  late final List<_Mask> cellRoomMask;
  late final List<_Mask> rowsBelow;
  late final List<_Mask> rowsAbove;
  late final List<_Mask> rowsFrom;
  late final List<_Mask> rowsTo;
  late final List<_Mask> colsBelow;
  late final List<_Mask> colsAbove;
  late final List<_Mask> colsFrom;
  late final List<_Mask> colsTo;
  late final List<_Mask> neighborMask;
  late final _Mask initMask;
  late final int victimRow;
  late final int victimCol;
  late final _Mask victimBesideMask;

  Pos posOf(int cell) => (row: cell ~/ g, col: cell % g);

  int cellOf(Pos p) => p.row * g + p.col;

  void _buildLookups(
    List<String> suspectIds,
    List<RoomDef> rooms,
    List<ObjectDef> objects,
  ) {
    indexOf = {for (var i = 0; i < suspectIds.length; i++) suspectIds[i]: i};
    roomIndexOf = {for (var i = 0; i < rooms.length; i++) rooms[i].id: i};
    objectById = {for (final o in objects) o.id: o};
  }

  /// Full row/column/room masks plus the per-cell house masks the clue
  /// filters and the structural pass use.
  void _buildHouseMasks(List<RoomDef> rooms) {
    rowMask = List.generate(g, (_) => _Mask());
    colMask = List.generate(g, (_) => _Mask());
    roomMask = List.generate(rooms.length, (_) => _Mask());
    cellRowMask = List.generate(n, (_) => _Mask());
    cellColMask = List.generate(n, (_) => _Mask());
    cellRoomMask = List.generate(n, (_) => _Mask());
    for (var cell = 0; cell < n; cell++) {
      final p = posOf(cell);
      rowMask[p.row].set(cell);
      colMask[p.col].set(cell);
      cellRowMask[cell] = rowMask[p.row];
      cellColMask[cell] = colMask[p.col];
      final room = roomIndexOf[rooms.firstWhere((r) => r.contains(p)).id]!;
      roomMask[room].set(cell);
      cellRoomMask[cell] = roomMask[room];
    }
  }

  /// The union of the [take]-selected row masks — a strip along the rows.
  static _Mask _unionOf(List<_Mask> houses, bool Function(int i) take) {
    final m = _Mask();
    for (var i = 0; i < houses.length; i++) {
      if (take(i)) {
        m.lo |= houses[i].lo;
        m.hi |= houses[i].hi;
      }
    }
    return m;
  }

  void _buildRowStrips() {
    rowsBelow = [for (var r = 0; r < g; r++) _unionOf(rowMask, (i) => i < r)];
    rowsAbove = [for (var r = 0; r < g; r++) _unionOf(rowMask, (i) => i > r)];
    rowsFrom = [for (var r = 0; r < g; r++) _unionOf(rowMask, (i) => i >= r)];
    rowsTo = [for (var r = 0; r < g; r++) _unionOf(rowMask, (i) => i <= r)];
  }

  void _buildColStrips() {
    colsBelow = [for (var c = 0; c < g; c++) _unionOf(colMask, (i) => i < c)];
    colsAbove = [for (var c = 0; c < g; c++) _unionOf(colMask, (i) => i > c)];
    colsFrom = [for (var c = 0; c < g; c++) _unionOf(colMask, (i) => i >= c)];
    colsTo = [for (var c = 0; c < g; c++) _unionOf(colMask, (i) => i <= c)];
  }

  /// Orthogonal in-grid neighbors per cell (the Manhattan-1 relation).
  void _buildNeighborMasks() {
    neighborMask = List.generate(n, (_) => _Mask());
    for (var row = 0; row < g; row++) {
      for (var col = 0; col < g; col++) {
        final m = neighborMask[row * g + col];
        _link(m, row - 1, col);
        _link(m, row + 1, col);
        _link(m, row, col - 1);
        _link(m, row, col + 1);
      }
    }
  }

  void _link(_Mask m, int r, int c) {
    if (r >= 0 && r < g && c >= 0 && c < g) m.set(r * g + c);
  }

  /// Init candidates: every cell except the victim's and blocking cells
  /// (occupiable furniture keeps its cell — a guest may sit there).
  void _buildInitMask(List<ObjectDef> objects, Pos victimPos) {
    initMask = _Mask();
    for (var i = 0; i < n; i++) {
      initMask.set(i);
    }
    initMask.clear(victimPos.row * g + victimPos.col);
    for (final o in objects) {
      if (!o.occupiable) initMask.clear(o.pos.row * g + o.pos.col);
    }
  }
}

/// Mutable deduction state: candidate masks per suspect, placed flags and
/// the ordered trace. Placed guests keep their single-cell mask, so later
/// clue-filter passes can still test a placement against relational clues
/// (a conflict surfaces as an empty mask — a contradiction).
class _State {
  _State(this.env)
    : cands = [for (var i = 0; i < env.suspectCount; i++) env.initMask.copy()],
      placed = List<bool>.filled(env.suspectCount, false),
      placedCell = List<int>.filled(env.suspectCount, -1),
      trace = [];

  final _Env env;
  final List<_Mask> cands;
  final List<bool> placed;
  final List<int> placedCell;
  final List<DeduceStep> trace;
  int placedCount = 0;

  _State copy() {
    final s = _State(env);
    for (var i = 0; i < env.suspectCount; i++) {
      s.cands[i] = cands[i].copy();
      s.placed[i] = placed[i];
      s.placedCell[i] = placedCell[i];
    }
    s.placedCount = placedCount;
    return s;
  }
}

/// The row/column strip masks along one axis, bundled for the direction
/// filters.
typedef _Strips = ({
  List<_Mask> below,
  List<_Mask> above,
  List<_Mask> from,
  List<_Mask> to,
});

/// The deduction engine: pure input → trace | null (issue #106). One
/// instance precomputes its environment once; [filter] and [solve] start
/// from fresh state each call and never share mutable data.
class Deducer {
  Deducer({
    required int gridSize,
    required List<RoomDef> rooms,
    required List<Clue> clues,
    required List<String> suspectIds,
    required Pos victimPos,
    required List<ObjectDef> objects,
    required this.tier,
  }) : _env = _Env(
         gridSize: gridSize,
         rooms: rooms,
         clues: clues,
         suspectIds: suspectIds,
         victimPos: victimPos,
         objects: objects,
       );

  final DeduceTier tier;
  final _Env _env;

  /// The init + clue-filter fixpoint without any placement rule — the
  /// observability seam the filter unit tests assert against (plainly
  /// public, like `ensureCoverage` in case_factory.dart).
  Map<String, Set<Pos>> filter() {
    final s = _State(_env);
    var changed = true;
    while (changed) {
      changed = _applyClues(s);
    }
    return {
      for (var i = 0; i < _env.suspectCount; i++)
        _env.suspectIds[i]: {
          for (final cell in s.cands[i].cells(_env.n)) _env.posOf(cell),
        },
    };
  }

  /// Solves the case by a chain of deductions under [tier]. Returns the
  /// ordered placement trace — one [DeduceStep] per guest, in placement
  /// order — or null when propagation stalls (or contradicts) before every
  /// guest is placed. Under [DeduceTier.probes] a stall runs uniqueness
  /// probes ([_probeRound]) and the loop repeats while they eliminate
  /// anything. Deterministic.
  List<DeduceStep>? solve() {
    final s = _State(_env);
    while (s.placedCount < _env.suspectCount) {
      if (!_propagate(s) || _stalled(s)) return null;
    }
    return s.trace;
  }

  /// Stalled: guests remain and propagation cannot go on — tier 1 has no
  /// further rule, tier 3 ran one probe round without an elimination
  /// ([_probeRound] is skipped on a just-solved state).
  bool _stalled(_State s) =>
      s.placedCount < _env.suspectCount &&
      (tier == DeduceTier.singles || !_probeRound(s));

  // -- propagation ----------------------------------------------------

  /// Drives clue filters, structural propagation and the tier-1 placement
  /// rules to a fixpoint. False = contradiction (an empty candidate mask or
  /// an unfilled house no unplaced guest can cover).
  bool _propagate(_State s) {
    var changed = true;
    while (changed) {
      changed = _applyClues(s);
      changed = _applyStructural(s) || changed;
      changed = _applySingles(s) || changed;
      if (_dead(s)) return false;
    }
    return true;
  }

  // -- clue filters ---------------------------------------------------

  /// One full pass over every clue, each applied arc-consistently; true
  /// when any candidate mask changed. Relational clues filter BOTH involved
  /// guests, including while both are unplaced.
  bool _applyClues(_State s) {
    var changed = false;
    for (final clue in _env.clues) {
      changed = _applyClue(s, clue) || changed;
    }
    return changed;
  }

  bool _applyClue(_State s, Clue clue) {
    // Room- and object-anchored kinds are unary masks; the target-bearing
    // kinds resolve their target (victim = known strip, suspect = relation).
    if (clue is InRoom || clue is BesideObject) return _roomAnchored(s, clue);
    final objectCell = _objectCellAnchored(s, clue);
    if (objectCell != null) return objectCell;
    return _targetAnchored(s, clue);
  }

  /// The issue-111 object-cell kinds' deduction; null when [clue] is none
  /// of them, so the caller falls through to the target anchors.
  bool? _objectCellAnchored(_State s, Clue clue) {
    if (clue is OnObject) return _onObjectAnchored(s, clue);
    if (clue is NearObject) return _nearObjectAnchored(s, clue);
    if (clue is SoleNearObject) return _soleNearAnchored(s, clue);
    return null;
  }

  bool _roomAnchored(_State s, Clue clue) {
    final si = _env.indexOf[clue.suspectId]!;
    if (clue is InRoom) {
      return _keep(
        s,
        si,
        _env.roomMask[_env.roomIndexOf[clue.roomId]!],
        clue.negated,
      );
    }
    clue as BesideObject;
    // ADR 0004: the item clue means the guest shares the item's room.
    final obj = _env.objectById[clue.objectId]!;
    return _keep(s, si, _env.cellRoomMask[_env.cellOf(obj.pos)], clue.negated);
  }

  /// OnObject keeps the item's single cell — a unary mask like the room
  /// anchors, negated the same way.
  bool _onObjectAnchored(_State s, OnObject clue) {
    final si = _env.indexOf[clue.suspectId]!;
    return _keep(
      s,
      si,
      _nearMask(clue.objectId, singleCell: true),
      clue.negated,
    );
  }

  /// NearObject keeps the item's cell plus its orthogonal neighbours.
  bool _nearObjectAnchored(_State s, NearObject clue) {
    final si = _env.indexOf[clue.suspectId]!;
    return _keep(
      s,
      si,
      _nearMask(clue.objectId, singleCell: false),
      clue.negated,
    );
  }

  /// SoleNearObject (positive only): the card's guest keeps the near mask,
  /// every other guest loses it. The negated form never ships — the engine
  /// rejects it loudly instead of applying an unsound per-guest inversion.
  bool _soleNearAnchored(_State s, SoleNearObject clue) {
    if (clue.negated) {
      throw ArgumentError('negated soleNearObject never ships: $clue');
    }
    final si = _env.indexOf[clue.suspectId]!;
    final mask = _nearMask(clue.objectId, singleCell: false);
    var changed = _keep(s, si, mask, false);
    for (var i = 0; i < _env.suspectCount; i++) {
      if (i == si) continue;
      changed = s.cands[i].subtract(mask) || changed;
    }
    return changed;
  }

  /// The item's own cell (when [singleCell]) or that cell plus its
  /// orthogonal neighbours (the NearObject neighbourhood).
  _Mask _nearMask(String objectId, {required bool singleCell}) {
    final cell = _env.cellOf(_env.objectById[objectId]!.pos);
    final m = singleCell ? _Mask() : _env.neighborMask[cell].copy();
    m.set(cell);
    return m;
  }

  bool _targetAnchored(_State s, Clue clue) {
    final si = _env.indexOf[clue.suspectId]!;
    if (clue is SameRow) {
      return _targetRowCol(s, si, clue.targetId, clue.negated, cols: false);
    }
    if (clue is SameCol) {
      return _targetRowCol(s, si, clue.targetId, clue.negated, cols: true);
    }
    if (clue is DirectionClue) {
      return _directionClue(s, si, clue.targetId, clue.direction, clue.negated);
    }
    clue as Beside;
    return _besideClue(s, si, clue.targetId, clue.negated);
  }

  /// SameRow/SameColumn: the victim's position is known, so the clue
  /// collapses to a unary strip; a suspect target makes it a relational
  /// filter on rows or columns.
  bool _targetRowCol(
    _State s,
    int si,
    String targetId,
    bool negated, {
    required bool cols,
  }) {
    if (targetId == victimId) {
      final mask = cols
          ? _env.colMask[_env.victimCol]
          : _env.rowMask[_env.victimRow];
      return _keep(s, si, mask, negated);
    }
    return _relRowCol(
      s,
      si,
      _env.indexOf[targetId]!,
      negated: negated,
      cols: cols,
    );
  }

  bool _directionClue(
    _State s,
    int si,
    String targetId,
    Direction d,
    bool negated,
  ) {
    if (targetId == victimId) return _keep(s, si, _victimStrip(d), negated);
    return _relDirection(s, si, _env.indexOf[targetId]!, d, negated);
  }

  /// Cells strictly north/south/west/east of the victim.
  _Mask _victimStrip(Direction d) => switch (d) {
    Direction.north => _env.rowsBelow[_env.victimRow],
    Direction.south => _env.rowsAbove[_env.victimRow],
    Direction.west => _env.colsBelow[_env.victimCol],
    Direction.east => _env.colsAbove[_env.victimCol],
  };

  bool _besideClue(_State s, int si, String targetId, bool negated) {
    if (targetId == victimId) {
      return _keep(s, si, _env.victimBesideMask, negated);
    }
    return _relBeside(s, si, _env.indexOf[targetId]!, negated);
  }

  /// Positive keeps [mask], negated removes it.
  bool _keep(_State s, int i, _Mask mask, bool negated) =>
      negated ? s.cands[i].subtract(mask) : s.cands[i].intersect(mask);

  /// The union of the rows (or columns) guest [i] can still take, and how
  /// many distinct houses that is. Empty mask → an empty union, count 0.
  ({_Mask mask, int count}) _span(_State s, int i, {required bool cols}) {
    final houses = cols ? _env.colMask : _env.rowMask;
    final m = _Mask();
    var count = 0;
    for (var h = 0; h < _env.g; h++) {
      if (_hits(s.cands[i], houses[h])) {
        m.lo |= houses[h].lo;
        m.hi |= houses[h].hi;
        count++;
      }
    }
    return (mask: m, count: count);
  }

  /// First house index guest [i] can still take along an axis; null on an
  /// empty mask (empty spans simply have no strip to keep).
  int? _minHouse(_State s, int i, bool alongCol) {
    final houses = alongCol ? _env.colMask : _env.rowMask;
    for (var h = 0; h < _env.g; h++) {
      if (_hits(s.cands[i], houses[h])) return h;
    }
    return null;
  }

  /// Last house index guest [i] can still take along an axis; null on an
  /// empty mask.
  int? _maxHouse(_State s, int i, bool alongCol) {
    final houses = alongCol ? _env.colMask : _env.rowMask;
    for (var h = _env.g - 1; h >= 0; h--) {
      if (_hits(s.cands[i], houses[h])) return h;
    }
    return null;
  }

  /// Arc-consistent SameRow/SameColumn over a suspect pair. Positive: both
  /// guests keep the rows/columns the other can still take. Negated: only a
  /// single-row/column target forbids that house — a target spanning
  /// several houses forbids nothing (every cell keeps a support). Empty
  /// spans eliminate naturally (no support left anywhere).
  bool _relRowCol(
    _State s,
    int si,
    int ti, {
    required bool negated,
    required bool cols,
  }) {
    final tSpan = _span(s, ti, cols: cols);
    final sSpan = _span(s, si, cols: cols);
    return negated
        ? _rowColNegated(s, si, ti, tSpan, sSpan)
        : _rowColPositive(s, si, ti, tSpan, sSpan);
  }

  bool _rowColPositive(
    _State s,
    int si,
    int ti,
    ({_Mask mask, int count}) tSpan,
    ({_Mask mask, int count}) sSpan,
  ) {
    final a = _keep(s, si, tSpan.mask, false);
    final b = _keep(s, ti, sSpan.mask, false);
    return a || b;
  }

  bool _rowColNegated(
    _State s,
    int si,
    int ti,
    ({_Mask mask, int count}) tSpan,
    ({_Mask mask, int count}) sSpan,
  ) {
    final a = tSpan.count == 1 ? _keep(s, si, tSpan.mask, true) : false;
    final b = sSpan.count == 1 ? _keep(s, ti, sSpan.mask, true) : false;
    return a || b;
  }

  /// Arc-consistent strict direction over a suspect pair. Normalized: a
  /// north/west clue means the suspect is strictly LESSER (row/col) than
  /// the target, a south/east clue GREATER — the greater case is the lesser
  /// case with the pair swapped.
  bool _relDirection(_State s, int si, int ti, Direction d, bool negated) {
    final (a, b) = _lesserHalf(si, ti, d);
    return negated
        ? _dirLesserNegated(s, a, b, _alongCol(d))
        : _dirLesserPositive(s, a, b, _alongCol(d));
  }

  /// True for the half-map directions whose strict form means "lesser"
  /// along the axis (north on rows, west on cols).
  bool _alongCol(Direction d) => d == Direction.west || d == Direction.east;

  /// The (lesser, greater) guest pair for [d]: north/west keep the clue's
  /// own suspect as the lesser side, south/east swap the pair.
  (int, int) _lesserHalf(int si, int ti, Direction d) =>
      (d == Direction.north || d == Direction.west) ? (si, ti) : (ti, si);

  _Strips _strips(bool alongCol) => alongCol
      ? (
          below: _env.colsBelow,
          above: _env.colsAbove,
          from: _env.colsFrom,
          to: _env.colsTo,
        )
      : (
          below: _env.rowsBelow,
          above: _env.rowsAbove,
          from: _env.rowsFrom,
          to: _env.rowsTo,
        );

  /// Positive strict "a lesser than b": a keeps the cells strictly below
  /// b's span top, b keeps the cells strictly above a's span bottom.
  bool _dirLesserPositive(_State s, int a, int b, bool alongCol) {
    final maxB = _maxHouse(s, b, alongCol);
    final minA = _minHouse(s, a, alongCol);
    if (maxB == null || minA == null) return false;
    final strips = _strips(alongCol);
    final ca = _keep(s, a, strips.below[maxB], false);
    final cb = _keep(s, b, strips.above[minA], false);
    return ca || cb;
  }

  /// Negated "a lesser than b" — a is at or beyond b: a keeps the cells at
  /// or after b's span bottom, b keeps the cells at or before a's span top.
  bool _dirLesserNegated(_State s, int a, int b, bool alongCol) {
    final minB = _minHouse(s, b, alongCol);
    final maxA = _maxHouse(s, a, alongCol);
    if (minB == null || maxA == null) return false;
    final strips = _strips(alongCol);
    final ca = _keep(s, a, strips.from[minB], false);
    final cb = _keep(s, b, strips.to[maxA], false);
    return ca || cb;
  }

  /// Arc-consistent Manhattan-1 over a suspect pair, per candidate cell: a
  /// cell survives positive when the other guest can still take an adjacent
  /// cell, and survives negated when the other guest can still take a
  /// non-adjacent cell. Empty other-mask → no support anywhere.
  bool _relBeside(_State s, int si, int ti, bool negated) {
    final changed = _besidePass(s, si, ti, negated);
    return _besidePass(s, ti, si, negated) || changed;
  }

  bool _besidePass(_State s, int i, int other, bool negated) {
    final t = s.cands[other];
    var changed = false;
    for (final c in s.cands[i].cells(_env.n)) {
      final nb = _env.neighborMask[c];
      final supported = negated
          ? (t.lo & ~nb.lo) != 0 || (t.hi & ~nb.hi) != 0
          : _hits(t, nb);
      if (!supported) {
        s.cands[i].clear(c);
        changed = true;
      }
    }
    return changed;
  }

  // -- structural propagation ----------------------------------------

  /// A placed guest's cell, row, column and room leave every other
  /// unplaced guest's candidates (one guest per house).
  bool _applyStructural(_State s) {
    var changed = false;
    for (var p = 0; p < _env.suspectCount; p++) {
      if (!s.placed[p]) continue;
      changed = _removePlacedHouses(s, p, s.placedCell[p]) || changed;
    }
    return changed;
  }

  bool _removePlacedHouses(_State s, int p, int cell) {
    var changed = false;
    final houses = [
      _Mask()..set(cell),
      _env.cellRowMask[cell],
      _env.cellColMask[cell],
      _env.cellRoomMask[cell],
    ];
    for (var u = 0; u < _env.suspectCount; u++) {
      if (s.placed[u]) continue;
      for (final house in houses) {
        changed = s.cands[u].subtract(house) || changed;
      }
    }
    return changed;
  }

  // -- tier-1 placement rules ----------------------------------------

  /// Naked singles (a guest down to one candidate is placed there) and
  /// hidden singles (an unfilled house only one unplaced guest can still
  /// take — intersect, and place when single).
  bool _applySingles(_State s) {
    var changed = false;
    for (var i = 0; i < _env.suspectCount; i++) {
      if (!s.placed[i] && s.cands[i].length == 1) {
        _place(s, i, s.cands[i].cells(_env.n).single, DeduceRule.nakedSingle);
        changed = true;
      }
    }
    return _hiddenSingles(s) || changed;
  }

  /// Every row, column and room mask — the house list for the hidden rule
  /// and the dead check.
  List<_Mask> _houses() => [..._env.rowMask, ..._env.colMask, ..._env.roomMask];

  bool _hiddenSingles(_State s) {
    var changed = false;
    for (final house in _houses()) {
      final member = _soleCandidate(s, house);
      if (member == null) continue;
      if (!s.cands[member].intersect(house)) continue;
      changed = true;
      if (s.cands[member].length == 1) {
        _place(
          s,
          member,
          s.cands[member].cells(_env.n).single,
          DeduceRule.hiddenSingle,
        );
      }
    }
    return changed;
  }

  /// The only unplaced guest that can still take [house]; null when the
  /// house is already filled, contested, or has no possible guest left.
  int? _soleCandidate(_State s, _Mask house) {
    int? sole;
    for (var i = 0; i < _env.suspectCount; i++) {
      if (!_hits(s.cands[i], house)) continue;
      if (s.placed[i]) return null;
      if (sole != null) return null;
      sole = i;
    }
    return sole;
  }

  /// Marks [i] placed at [cell] and records the trace step.
  void _place(_State s, int i, int cell, DeduceRule rule) {
    s.placed[i] = true;
    s.placedCell[i] = cell;
    s.placedCount++;
    s.trace.add(
      DeduceStep(
        guestId: _env.suspectIds[i],
        cell: _env.posOf(cell),
        rule: rule,
      ),
    );
  }

  // -- contradiction check -------------------------------------------

  /// Contradiction: any candidate mask (placed guests included — their
  /// single-cell mask empties when a later filter pass conflicts with the
  /// placement) is empty, or an unfilled house has no possible guest left.
  bool _dead(_State s) => _anyEmptyMask(s) || _anyStarvedHouse(s);

  bool _anyEmptyMask(_State s) {
    for (var i = 0; i < _env.suspectCount; i++) {
      if (s.cands[i].isEmpty) return true;
    }
    return false;
  }

  bool _anyStarvedHouse(_State s) {
    for (final house in _houses()) {
      if (_starved(s, house)) return true;
    }
    return false;
  }

  /// True when no placed guest holds a cell of [house] and no unplaced
  /// guest can take one either — the house can never be filled.
  bool _starved(_State s, _Mask house) {
    var hasPlaced = false;
    var hasCover = false;
    for (var i = 0; i < _env.suspectCount; i++) {
      if (!_hits(s.cands[i], house)) continue;
      if (s.placed[i]) {
        hasPlaced = true;
      } else {
        hasCover = true;
      }
    }
    return !hasPlaced && !hasCover;
  }

  // -- tier-3 uniqueness probes --------------------------------------

  /// One probe round: for every unplaced guest × candidate cell (fixed
  /// ascending order), hypothesize the placement on a state copy and
  /// propagate it; a contradiction (empty candidate mask, or a still-
  /// unfilled house no unplaced guest can cover) proves the cell cannot
  /// hold the guest in ANY solution, so it is eliminated in the real state.
  /// True when anything was eliminated — the solve loop re-propagates.
  bool _probeRound(_State s) {
    var eliminated = false;
    for (var i = 0; i < _env.suspectCount; i++) {
      if (s.placed[i]) continue;
      for (final cell in s.cands[i].cells(_env.n)) {
        final hypothesis = s.copy();
        hypothesis.cands[i] = _Mask()..set(cell);
        if (!_propagate(hypothesis)) {
          s.cands[i].clear(cell);
          eliminated = true;
        }
      }
    }
    return eliminated;
  }
}
