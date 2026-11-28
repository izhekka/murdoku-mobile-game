import 'package:murdoku/domain/models.dart';

/// A Russian suspect name in the two grammatical forms the clue templates
/// need: nominative (subject) and genitive (около/севернее ...).
typedef NameForm = ({String nom, String gen});

/// Suspect name pool, index-aligned with the factory's English pool.
const List<NameForm> ruSuspectForms = [
  (nom: 'Эшли', gen: 'Эшли'),
  (nom: 'Блэр', gen: 'Блэр'),
  (nom: 'Кейси', gen: 'Кейси'),
  (nom: 'Дрю', gen: 'Дрю'),
  (nom: 'Эллис', gen: 'Эллиса'),
  (nom: 'Франк', gen: 'Франка'),
  (nom: 'Гейл', gen: 'Гейл'),
  (nom: 'Харпер', gen: 'Харпер'),
  (nom: 'Ирис', gen: 'Ириса'),
  (nom: 'Джек', gen: 'Джека'),
  (nom: 'Кай', gen: 'Кая'),
  (nom: 'Лэйн', gen: 'Лэйна'),
  (nom: 'Морган', gen: 'Моргана'),
  (nom: 'Ноэль', gen: 'Ноэля'),
  (nom: 'Окли', gen: 'Окли'),
  (nom: 'Вера', gen: 'Веры'),
];

/// Room name pool: nominative + full prepositional phrase («в/на ...»),
/// index-aligned with the factory's English pool.
const List<(String, String)> ruRoomForms = [
  ('Холл', 'в холле'),
  ('Библиотека', 'в библиотеке'),
  ('Кухня', 'в кухне'),
  ('Погреб', 'в погребе'),
  ('Кабинет', 'в кабинете'),
  ('Бальный зал', 'в бальном зале'),
  ('Оранжерея', 'в оранжерее'),
  ('Гостиная', 'в гостиной'),
  ('Чердак', 'на чердаке'),
  ('Кладовая', 'в кладовой'),
  ('Галерея', 'в галерее'),
  ('Часовня', 'в часовне'),
  ('Солярий', 'в солярии'),
  ('Бильярдная', 'в бильярдной'),
  ('Прихожая', 'в прихожей'),
  ('Обсерватория', 'в обсерватории'),
];

/// An item name in the three forms the item clues and labels need:
/// nominative (standalone label), `prep` — the preposition-attached
/// lowercase instrumental the ru item-clue parameter carries (with the
/// euphonic «со» before с/ст-initial kinds), and `on` — the prepositional
/// form the sits-on clue parameter carries (issue 111).
typedef ObjectNameForm = ({String nom, String prep, String on});

/// Item names by kind: nominative + preposition-attached lowercase
/// instrumental + prepositional (hand-written per kind — no runtime
/// euphony logic). The same-room item clue (UX-8) replaced the old
/// genitive forms (около ...); the standalone capitalized instrumental
/// retired with #14; the on form landed with the sits-on clue (#111).
const Map<ObjectKind, ObjectNameForm> ruObjectForms = {
  ObjectKind.piano: (nom: 'Пианино', prep: 'с пианино', on: 'на пианино'),
  ObjectKind.plant: (nom: 'Растение', prep: 'с растением', on: 'на растении'),
  ObjectKind.armor: (nom: 'Доспехи', prep: 'с доспехами', on: 'на доспехах'),
  ObjectKind.chest: (nom: 'Сундук', prep: 'с сундуком', on: 'на сундуке'),
  ObjectKind.clock: (nom: 'Часы', prep: 'с часами', on: 'на часах'),
  ObjectKind.globe: (nom: 'Глобус', prep: 'с глобусом', on: 'на глобусе'),
  ObjectKind.portrait: (nom: 'Портрет', prep: 'с портретом', on: 'на портрете'),
  ObjectKind.fireplace: (nom: 'Камин', prep: 'с камином', on: 'на камине'),
  ObjectKind.table: (nom: 'Стол', prep: 'со столом', on: 'на столе'),
  ObjectKind.chair: (nom: 'Стул', prep: 'со стулом', on: 'на стуле'),
  ObjectKind.flowers: (nom: 'Цветы', prep: 'с цветами', on: 'на цветах'),
  ObjectKind.sofa: (nom: 'Диван', prep: 'с диваном', on: 'на диване'),
  ObjectKind.bookshelf: (
    nom: 'Стеллаж',
    prep: 'со стеллажом',
    on: 'на стеллаже',
  ),
  ObjectKind.lamp: (nom: 'Лампа', prep: 'с лампой', on: 'на лампе'),
};

const String victimNomRu = 'жертва';
const String victimGenRu = 'жертвы';

/// Resolves display strings for suspects, rooms, items and the victim in the
/// active locale. Suspects/rooms with `poolIndex >= 0` resolve through the
/// locale pools; anything else falls back to the stored (English) name.
class NameForms {
  NameForms._(this._locale, this._case);

  final String _locale;
  final CaseData _case;

  factory NameForms.forLocale(String locale, CaseData c) =>
      NameForms._(locale, c);

  bool get _ru => _locale == 'ru';

  Suspect _suspect(String id) => _case.suspects.firstWhere((s) => s.id == id);

  RoomDef _room(String roomId) => _case.rooms.firstWhere((r) => r.id == roomId);

  String nom(String suspectId) {
    final s = _suspect(suspectId);
    if (_ru && s.poolIndex >= 0 && s.poolIndex < ruSuspectForms.length) {
      return ruSuspectForms[s.poolIndex].nom;
    }
    return s.name;
  }

  String gen(String suspectOrVictimId) {
    if (suspectOrVictimId == victimId) return victimGen();
    final s = _suspect(suspectOrVictimId);
    if (_ru && s.poolIndex >= 0 && s.poolIndex < ruSuspectForms.length) {
      return ruSuspectForms[s.poolIndex].gen;
    }
    return s.name;
  }

  String victimNom() => _ru ? victimNomRu : 'the victim';

  String victimGen() => _ru ? victimGenRu : 'the victim';

  /// The `{room}` filler: full prep phrase in ru («в библиотеке»), bare name
  /// in en (the en template carries "in the").
  String roomPrep(String roomId) {
    final room = _room(roomId);
    if (_ru) {
      if (room.poolIndex >= 0 && room.poolIndex < ruRoomForms.length) {
        return ruRoomForms[room.poolIndex].$2;
      }
      return 'в ${room.name}';
    }
    return room.name;
  }

  String roomNom(String roomId) {
    final room = _room(roomId);
    if (_ru && room.poolIndex >= 0 && room.poolIndex < ruRoomForms.length) {
      return ruRoomForms[room.poolIndex].$1;
    }
    return room.name;
  }

  String objectNom(ObjectKind kind) {
    if (_ru) return ruObjectForms[kind]?.nom ?? kind.name;
    return _capitalized(kind.name);
  }

  /// The `{object}` filler of the same-room item clue: full preposition
  /// phrase in ru («со стулом»), bare capitalized name in en (the en template
  /// carries "in the same room as the").
  String objectPrep(ObjectKind kind) {
    if (_ru) {
      return ruObjectForms[kind]?.prep ?? 'с ${objectNom(kind)}';
    }
    // The en template already carries the article
    // ("in the same room as the {object}").
    return _capitalized(kind.name);
  }

  /// The `{object}` filler of the sits-on item clue (issue 111): the
  /// prepositional form in ru («на стуле»), bare capitalized name in en
  /// (the en template carries "sits on the").
  String objectOn(ObjectKind kind) {
    if (_ru) {
      return ruObjectForms[kind]?.on ?? 'на ${objectNom(kind)}';
    }
    return _capitalized(kind.name);
  }

  String _capitalized(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
