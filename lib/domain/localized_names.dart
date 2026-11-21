import 'models.dart';

/// A Russian name in the two grammatical forms the clue templates need:
/// nominative (subject) and an oblique form — genitive for suspects
/// (около/севернее ...) and instrumental for items (в комнате с ...).
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

/// Item names by kind: nominative + instrumental (в комнате с ...); the
/// same-room item clue (UX-8) replaced the old genitive forms (около ...).
const Map<ObjectKind, NameForm> ruObjectForms = {
  ObjectKind.piano: (nom: 'Пианино', gen: 'Пианино'),
  ObjectKind.plant: (nom: 'Растение', gen: 'Растением'),
  ObjectKind.armor: (nom: 'Доспехи', gen: 'Доспехами'),
  ObjectKind.chest: (nom: 'Сундук', gen: 'Сундуком'),
  ObjectKind.clock: (nom: 'Часы', gen: 'Часами'),
  ObjectKind.globe: (nom: 'Глобус', gen: 'Глобусом'),
  ObjectKind.portrait: (nom: 'Портрет', gen: 'Портретом'),
  ObjectKind.fireplace: (nom: 'Камин', gen: 'Камином'),
  ObjectKind.table: (nom: 'Стол', gen: 'Столом'),
  ObjectKind.chair: (nom: 'Стул', gen: 'Стулом'),
  ObjectKind.flowers: (nom: 'Цветы', gen: 'Цветами'),
  ObjectKind.sofa: (nom: 'Диван', gen: 'Диваном'),
  ObjectKind.bookshelf: (nom: 'Стеллаж', gen: 'Стеллажом'),
  ObjectKind.lamp: (nom: 'Лампа', gen: 'Лампой'),
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

  String objectGen(ObjectKind kind) {
    if (_ru) {
      return ruObjectForms[kind]?.gen ?? objectNom(kind);
    }
    // The en templates already carry the article
    // ("in the same room as the {object}").
    return _capitalized(kind.name);
  }

  String _capitalized(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
