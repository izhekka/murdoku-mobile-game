import 'package:murdoku/domain/models.dart';

/// Which board interaction is active.
enum Tool { place, markX, erase }

/// True when [pos] can host [suspectId] right now: the cell must be free of
/// other guests and must not be the victim's cell.
bool canPlace(CaseData c, Map<String, Pos> placed, String suspectId, Pos pos) {
  if (pos == c.victimPos) return false;
  if (_occupiedByOther(placed, suspectId, pos)) return false;
  if (_blockedByObject(c.objects, pos)) return false;
  return true;
}

/// True when a guest other than [suspectId] already sits at [pos].
bool _occupiedByOther(Map<String, Pos> placed, String suspectId, Pos pos) {
  for (final entry in placed.entries) {
    if (entry.key != suspectId && entry.value == pos) return true;
  }
  return false;
}

/// True when [pos] holds furniture a guest may not share.
bool _blockedByObject(List<ObjectDef> objects, Pos pos) {
  for (final item in objects) {
    if (item.pos == pos && !item.occupiable) return true;
  }
  return false;
}

/// Number of guests sitting at their true solution position.
int correctCount(CaseData c, Map<String, Pos> placed) {
  var n = 0;
  for (final entry in placed.entries) {
    if (c.solution[entry.key] == entry.value) n++;
  }
  return n;
}

/// True when every guest is placed and every placement is exact.
bool boardSolved(CaseData c, Map<String, Pos> placed) {
  if (placed.length != c.suspects.length) return false;
  for (final entry in placed.entries) {
    if (c.solution[entry.key] != entry.value) return false;
  }
  return true;
}
