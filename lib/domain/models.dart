/// Pure domain models for Murdoku cases. No Flutter imports — this file must
/// stay testable in isolation.
library;

/// Row/col position on the case grid. JSON-encoded as `[row, col]`.
typedef Pos = ({int row, int col});

/// UTC-date → deterministic daily seed, per the design spec §2.5.
int dailySeedFor(DateTime utcDate) =>
    utcDate.year * 10000 + utcDate.month * 100 + utcDate.day;

/// The victim marker shown on the map. Never a suspect id.
const victimId = 'V';

List<int> posToJson(Pos p) => [p.row, p.col];
Pos posFromJson(List<dynamic> json) => (row: json[0] as int, col: json[1] as int);

enum Difficulty { easy, standard, hard }

extension DifficultyX on Difficulty {
  int get gridSize => switch (this) {
        Difficulty.easy => 5,
        Difficulty.standard => 6,
        Difficulty.hard => 7,
      };
  int get objectCount => switch (this) {
        Difficulty.easy => 2,
        Difficulty.standard => 3,
        Difficulty.hard => 4,
      };
  int get minClues => switch (this) {
        Difficulty.easy => 6,
        Difficulty.standard => 8,
        Difficulty.hard => 10,
      };
  int get maxClues => switch (this) {
        Difficulty.easy => 9,
        Difficulty.standard => 12,
        Difficulty.hard => 14,
      };

  static Difficulty fromName(String name) =>
      Difficulty.values.firstWhere((d) => d.name == name);
}

enum Direction { north, south, east, west }

extension DirectionX on Direction {
  static Direction fromName(String name) =>
      Direction.values.firstWhere((d) => d.name == name);
}

enum ObjectKind { piano, plant, armor, chest, clock, globe, portrait, fireplace }

extension ObjectKindX on ObjectKind {
  static ObjectKind fromName(String name) =>
      ObjectKind.values.firstWhere((k) => k.name == name);
}

class Suspect {
  const Suspect({required this.id, required this.name});

  final String id; // "s0", "s1", ...
  final String name;

  @override
  bool operator ==(Object other) => other is Suspect && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory Suspect.fromJson(Map<String, Object?> json) =>
      Suspect(id: json['id'] as String, name: json['name'] as String);
}

class RoomDef {
  const RoomDef({required this.id, required this.name, required this.cells});

  final String id; // "r0", "r1", ...
  final String name;
  final List<Pos> cells; // orthogonally contiguous, disjoint

  bool contains(Pos p) => cells.contains(p);

  @override
  bool operator ==(Object other) =>
      other is RoomDef && other.id == id && other.name == name && _listsEqual(other.cells, cells);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(cells));

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'cells': cells.map(posToJson).toList(),
      };

  factory RoomDef.fromJson(Map<String, Object?> json) => RoomDef(
        id: json['id'] as String,
        name: json['name'] as String,
        cells: (json['cells'] as List).map((c) => posFromJson(c as List)).toList(),
      );
}

class ObjectDef {
  const ObjectDef({required this.id, required this.kind, required this.pos});

  final String id; // "o0", ...
  final ObjectKind kind;
  final Pos pos;

  @override
  bool operator ==(Object other) =>
      other is ObjectDef && other.id == id && other.kind == kind && other.pos == pos;

  @override
  int get hashCode => Object.hash(id, kind, pos);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind.name, 'pos': posToJson(pos)};

  factory ObjectDef.fromJson(Map<String, Object?> json) => ObjectDef(
        id: json['id'] as String,
        kind: ObjectKindX.fromName(json['kind'] as String),
        pos: posFromJson(json['pos'] as List),
      );
}

/// Returns the id of the room containing [p], or null when [p] is in no room.
String? roomOf(List<RoomDef> rooms, Pos p) {
  for (final room in rooms) {
    if (room.contains(p)) return room.id;
  }
  return null;
}

/// Base class for every clue. A clue is a *rule*: it must hold for the
/// unique solution. [suspectId] is the guest the clue card is attached to;
/// [negated] inverts the predicate.
sealed class Clue {
  const Clue({required this.suspectId, required this.negated});

  final String suspectId;
  final bool negated;

  String get typeName;

  Map<String, Object?> toJson() => {
        'type': typeName,
        'suspectId': suspectId,
        'negated': negated,
      };
}

class InRoom extends Clue {
  const InRoom({required super.suspectId, required this.roomId, required super.negated});

  final String roomId;

  @override
  String get typeName => 'inRoom';

  @override
  bool operator ==(Object other) =>
      other is InRoom &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.roomId == roomId;

  @override
  int get hashCode => Object.hash(InRoom, suspectId, negated, roomId);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'roomId': roomId};
}

/// [targetId] may be a suspect id or [victimId].
class SameRow extends Clue {
  const SameRow({required super.suspectId, required this.targetId, required super.negated});

  final String targetId;

  @override
  String get typeName => 'sameRow';

  @override
  bool operator ==(Object other) =>
      other is SameRow &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(SameRow, suspectId, negated, targetId);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'targetId': targetId};
}

/// [targetId] may be a suspect id or [victimId].
class SameCol extends Clue {
  const SameCol({required super.suspectId, required this.targetId, required super.negated});

  final String targetId;

  @override
  String get typeName => 'sameCol';

  @override
  bool operator ==(Object other) =>
      other is SameCol &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(SameCol, suspectId, negated, targetId);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'targetId': targetId};
}

/// Strict half-map relation: e.g. `north` means strictly smaller row.
class DirectionClue extends Clue {
  const DirectionClue({
    required super.suspectId,
    required this.targetId,
    required this.direction,
    required super.negated,
  });

  final String targetId;
  final Direction direction;

  @override
  String get typeName => 'direction';

  @override
  bool operator ==(Object other) =>
      other is DirectionClue &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.targetId == targetId &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(DirectionClue, suspectId, negated, targetId, direction);

  @override
  Map<String, Object?> toJson() =>
      {...super.toJson(), 'targetId': targetId, 'direction': direction.name};
}

/// Manhattan distance exactly 1 (diagonal does not count).
class Beside extends Clue {
  const Beside({required super.suspectId, required this.targetId, required super.negated});

  final String targetId;

  @override
  String get typeName => 'beside';

  @override
  bool operator ==(Object other) =>
      other is Beside &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(Beside, suspectId, negated, targetId);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'targetId': targetId};
}

class BesideObject extends Clue {
  const BesideObject({required super.suspectId, required this.objectId, required super.negated});

  final String objectId;

  @override
  String get typeName => 'besideObject';

  @override
  bool operator ==(Object other) =>
      other is BesideObject &&
      other.suspectId == suspectId &&
      other.negated == negated &&
      other.objectId == objectId;

  @override
  int get hashCode => Object.hash(BesideObject, suspectId, negated, objectId);

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'objectId': objectId};
}

Clue _clueFromJson(Map<String, Object?> json) {
  final suspectId = json['suspectId'] as String;
  final negated = json['negated'] as bool;
  switch (json['type'] as String) {
    case 'inRoom':
      return InRoom(suspectId: suspectId, roomId: json['roomId'] as String, negated: negated);
    case 'sameRow':
      return SameRow(suspectId: suspectId, targetId: json['targetId'] as String, negated: negated);
    case 'sameCol':
      return SameCol(suspectId: suspectId, targetId: json['targetId'] as String, negated: negated);
    case 'direction':
      return DirectionClue(
        suspectId: suspectId,
        targetId: json['targetId'] as String,
        direction: DirectionX.fromName(json['direction'] as String),
        negated: negated,
      );
    case 'beside':
      return Beside(suspectId: suspectId, targetId: json['targetId'] as String, negated: negated);
    case 'besideObject':
      return BesideObject(
          suspectId: suspectId, objectId: json['objectId'] as String, negated: negated);
    default:
      throw FormatException('unknown clue type: ${json['type']}');
  }
}

/// A fully generated murder case. [solution] is the complete truth: the
/// unique placement satisfying rows/columns/rooms and every clue.
class CaseData {
  const CaseData({
    required this.seed,
    required this.difficulty,
    required this.rooms,
    required this.objects,
    required this.suspects,
    required this.victimPos,
    required this.murdererId,
    required this.clues,
    required this.solution,
  });

  final int seed;
  final Difficulty difficulty;
  final List<RoomDef> rooms;
  final List<ObjectDef> objects;
  final List<Suspect> suspects; // length == gridSize
  final Pos victimPos;
  final String murdererId;
  final List<Clue> clues;
  final Map<String, Pos> solution; // suspectId -> pos

  int get gridSize => difficulty.gridSize;

  CaseData copyWith({
    int? seed,
    Difficulty? difficulty,
    List<RoomDef>? rooms,
    List<ObjectDef>? objects,
    List<Suspect>? suspects,
    Pos? victimPos,
    String? murdererId,
    List<Clue>? clues,
    Map<String, Pos>? solution,
  }) =>
      CaseData(
        seed: seed ?? this.seed,
        difficulty: difficulty ?? this.difficulty,
        rooms: rooms ?? this.rooms,
        objects: objects ?? this.objects,
        suspects: suspects ?? this.suspects,
        victimPos: victimPos ?? this.victimPos,
        murdererId: murdererId ?? this.murdererId,
        clues: clues ?? this.clues,
        solution: solution ?? this.solution,
      );

  @override
  bool operator ==(Object other) =>
      other is CaseData &&
      other.seed == seed &&
      other.difficulty == difficulty &&
      _listsEqual(other.rooms, rooms) &&
      _listsEqual(other.objects, objects) &&
      _listsEqual(other.suspects, suspects) &&
      other.victimPos == victimPos &&
      other.murdererId == murdererId &&
      _listsEqual(other.clues, clues) &&
      _mapsEqual(other.solution, solution);

  @override
  int get hashCode => Object.hash(
        seed,
        difficulty,
        Object.hashAll(rooms),
        Object.hashAll(objects),
        Object.hashAll(suspects),
        victimPos,
        murdererId,
        Object.hashAll(clues),
        Object.hashAllUnordered(solution.entries
            .map((e) => Object.hash(e.key, e.value))
            .toList()),
      );

  Map<String, Object?> toJson() => {
        'seed': seed,
        'difficulty': difficulty.name,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'objects': objects.map((o) => o.toJson()).toList(),
        'suspects': suspects.map((s) => s.toJson()).toList(),
        'victimPos': posToJson(victimPos),
        'murdererId': murdererId,
        'clues': clues.map((c) => c.toJson()).toList(),
        'solution': solution.map((k, v) => MapEntry(k, posToJson(v))),
      };

  factory CaseData.fromJson(Map<String, Object?> json) => CaseData(
        seed: json['seed'] as int,
        difficulty: DifficultyX.fromName(json['difficulty'] as String),
        rooms: (json['rooms'] as List).map((r) => RoomDef.fromJson(r as Map<String, Object?>)).toList(),
        objects: (json['objects'] as List)
            .map((o) => ObjectDef.fromJson(o as Map<String, Object?>))
            .toList(),
        suspects: (json['suspects'] as List)
            .map((s) => Suspect.fromJson(s as Map<String, Object?>))
            .toList(),
        victimPos: posFromJson(json['victimPos'] as List),
        murdererId: json['murdererId'] as String,
        clues: (json['clues'] as List).map((c) => _clueFromJson(c as Map<String, Object?>)).toList(),
        solution: (json['solution'] as Map<String, Object?>)
            .map((k, v) => MapEntry(k, posFromJson(v as List))),
      );
}

/// Persisted mid-game board state (what the player has done so far).
class BoardSnapshot {
  const BoardSnapshot({
    required this.placed,
    required this.xMarks,
    required this.elapsed,
    required this.hintsUsed,
    required this.wrongAccusations,
    this.eliminatedSuspects = const {},
  });

  final Map<String, Pos> placed; // suspectId -> pos
  final Set<Pos> xMarks;
  final Duration elapsed;
  final int hintsUsed;
  final int wrongAccusations;
  final Set<String> eliminatedSuspects; // Hint B exclusions

  @override
  bool operator ==(Object other) =>
      other is BoardSnapshot &&
      _mapsEqual(other.placed, placed) &&
      _setsEqual(other.xMarks, xMarks) &&
      other.elapsed == elapsed &&
      other.hintsUsed == hintsUsed &&
      other.wrongAccusations == wrongAccusations &&
      _setsEqual(other.eliminatedSuspects, eliminatedSuspects);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(placed.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(xMarks),
        elapsed,
        hintsUsed,
        wrongAccusations,
        Object.hashAllUnordered(eliminatedSuspects),
      );

  Map<String, Object?> toJson() => {
        'placed': placed.map((k, v) => MapEntry(k, posToJson(v))),
        'xMarks': xMarks.map(posToJson).toList(),
        'elapsedSeconds': elapsed.inSeconds,
        'hintsUsed': hintsUsed,
        'wrongAccusations': wrongAccusations,
        'eliminatedSuspects': eliminatedSuspects.toList(),
      };

  factory BoardSnapshot.fromJson(Map<String, Object?> json) => BoardSnapshot(
        placed: (json['placed'] as Map<String, Object?>)
            .map((k, v) => MapEntry(k, posFromJson(v as List))),
        xMarks: (json['xMarks'] as List).map((v) => posFromJson(v as List)).toSet(),
        elapsed: Duration(seconds: json['elapsedSeconds'] as int),
        hintsUsed: json['hintsUsed'] as int,
        wrongAccusations: json['wrongAccusations'] as int,
        eliminatedSuspects:
            (json['eliminatedSuspects'] as List? ?? []).cast<String>().toSet(),
      );
}

bool _setsEqual<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapsEqual<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (b[key] != a[key]) return false;
  }
  return true;
}
