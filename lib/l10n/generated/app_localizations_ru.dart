// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Murdoku';

  @override
  String get fatalErrorMessage =>
      'Что-то пошло не так. Перезапустите приложение.';

  @override
  String get howToPlayTitle => 'Как играть';

  @override
  String get gameTitle => 'Дело';

  @override
  String get statsTitle => 'Статистика';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get continueCase => 'Продолжить дело';

  @override
  String get newCase => 'Новое дело';

  @override
  String get dailyCase => 'Дело дня';

  @override
  String get dailyCompleted => 'Сегодня решено';

  @override
  String get difficultyEasy => 'Легко';

  @override
  String get difficultyStandard => 'Средне';

  @override
  String get difficultyHard => 'Сложно';

  @override
  String get discardTitle => 'Сбросить текущее дело?';

  @override
  String get discardBody => 'Новое дело сбросит текущий прогресс.';

  @override
  String get discard => 'Сбросить';

  @override
  String get cancel => 'Отмена';

  @override
  String get chooseDifficulty => 'Выберите сложность';

  @override
  String get objectPiano => 'Пианино';

  @override
  String get objectPlant => 'Растение';

  @override
  String get objectArmor => 'Доспехи';

  @override
  String get objectChest => 'Сундук';

  @override
  String get objectClock => 'Часы';

  @override
  String get objectGlobe => 'Глобус';

  @override
  String get objectPortrait => 'Портрет';

  @override
  String get objectFireplace => 'Камин';

  @override
  String get victimLabel => 'Жертва';

  @override
  String cellSemantics(int row, int column, String room, String state) {
    return 'Ряд $row, колонка $column, $room, $state';
  }

  @override
  String get stateEmpty => 'пусто';

  @override
  String get stateExcluded => 'помечено пустым';

  @override
  String get stateVictim => 'жертва';

  @override
  String get victimName => 'жертва';

  @override
  String get dirNorth => 'севернее';

  @override
  String get dirSouth => 'южнее';

  @override
  String get dirEast => 'восточнее';

  @override
  String get dirWest => 'западнее';

  @override
  String clueInRoom(String room) {
    return '— $room.';
  }

  @override
  String clueInRoomNot(String room) {
    return '— не $room.';
  }

  @override
  String clueSameRow(String target) {
    return '— на том же этаже, что и $target.';
  }

  @override
  String clueSameRowNot(String target) {
    return '— не на том же этаже, что и $target.';
  }

  @override
  String clueSameCol(String target) {
    return '— в том же коридоре, что и $target.';
  }

  @override
  String clueSameColNot(String target) {
    return '— не в том же коридоре, что и $target.';
  }

  @override
  String clueDirection(String direction, String target) {
    return '— $direction $target.';
  }

  @override
  String clueDirectionNot(String direction, String target) {
    return '— не $direction $target.';
  }

  @override
  String clueBeside(String target) {
    return '— около $target.';
  }

  @override
  String clueBesideNot(String target) {
    return '— не около $target.';
  }

  @override
  String clueBesideObject(String object) {
    return '— в комнате $object.';
  }

  @override
  String clueBesideObjectNot(String object) {
    return '— не в комнате $object.';
  }

  @override
  String get accuse => 'Обвинить';

  @override
  String get accuseTitle => 'Кто убийца?';

  @override
  String get toolPlace => 'Поставить';

  @override
  String get toolMark => 'Крестик';

  @override
  String get toolErase => 'Стереть';

  @override
  String get toolUndo => 'Отменить';

  @override
  String get toolCheck => 'Проверить';

  @override
  String get toolHint => 'Подсказка';

  @override
  String get toolAccuse => 'Обвинить';

  @override
  String get toolCheckTooltip => 'Проверить расстановку гостей';

  @override
  String get toolMarkTooltip => 'Пометить клетку как пустую';

  @override
  String get toolHintTooltip => 'Получить подсказку';

  @override
  String timerSemantics(String difficulty, String time) {
    return '$difficulty, прошло $time';
  }

  @override
  String alibi(String name) {
    return 'У $name железное алиби.';
  }

  @override
  String checkResult(int n, int total) {
    return '$n из $total гостей на своих местах.';
  }

  @override
  String get victoryTitle => 'Дело закрыто!';

  @override
  String victoryTime(String time) {
    return 'Время: $time';
  }

  @override
  String victoryMistakes(int count) {
    return 'Ошибок: $count';
  }

  @override
  String get victoryDone => 'Готово';

  @override
  String get revealSolution => 'Показать решение';

  @override
  String get revealConfirmTitle => 'Показать решение?';

  @override
  String get revealConfirmBody => 'Дело будет засчитано как проваленное.';

  @override
  String get quitCase => 'Выйти из дела';

  @override
  String get quitConfirmTitle => 'Покинуть дело?';

  @override
  String get quitConfirmBody => 'Прогресс этого дела будет потерян.';

  @override
  String get resume => 'Продолжить';

  @override
  String get hintTitle => 'Выберите подсказку';

  @override
  String get hintPlace => 'Открыть позицию гостя';

  @override
  String get hintEliminate => 'Исключить подозреваемого';

  @override
  String hintsLeft(int count) {
    return 'Подсказок осталось: $count';
  }

  @override
  String get noActiveCase => 'Нет активного дела.';

  @override
  String get backToHome => 'На главную';

  @override
  String get playAgain => 'Играть снова';

  @override
  String statsSolved(int n) {
    return 'Решено: $n';
  }

  @override
  String statsBest(String time) {
    return 'Лучшее: $time';
  }

  @override
  String statsAverage(String time) {
    return 'Среднее: $time';
  }

  @override
  String currentStreak(int n) {
    return 'Серия дней: $n';
  }

  @override
  String totalCasesLabel(int n) {
    return 'Всего дел: $n';
  }

  @override
  String get statsEmpty => 'Пока ничего не решено. Начните новое дело!';

  @override
  String get themeModeLabel => 'Тема';

  @override
  String get themeSystem => 'Системная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get skinLabel => 'Стиль';

  @override
  String get skinClassic => 'Классика';

  @override
  String get skinCandy => 'Карамель';

  @override
  String get skinSticker => 'Стикеры';

  @override
  String get skinComic => 'Комикс';

  @override
  String get themeModeCaption =>
      'Светлая/тёмная тема применяется к классическому стилю.';

  @override
  String get hapticsLabel => 'Вибрация';

  @override
  String get resetProgress => 'Сбросить прогресс';

  @override
  String get resetConfirmTitle => 'Сбросить весь прогресс?';

  @override
  String get resetConfirmBody =>
      'Будут удалены сохранения, статистика и серия дней. Настройки сохранятся.';

  @override
  String get progressReset => 'Прогресс сброшен.';

  @override
  String get rule1Text =>
      'Каждый гость встречается ровно один раз в каждом ряду, колонке и комнате — как судоку из подозреваемых.';

  @override
  String get rule2Text =>
      'Каждая улика правдива. Улики — это правила, а не подсказки.';

  @override
  String get rule3Text =>
      'Карта — это улика. Комнаты и предметы — место действия.';

  @override
  String get rule4Text =>
      'С жертвой в одной комнате остался один гость. Это и есть убийца. Найдите его последним.';

  @override
  String get tutorialXHint =>
      'Ставьте крестики на клетки, которые точно не подходят.';

  @override
  String get tutorialNext => 'Далее';

  @override
  String get tutorialDone => 'Понятно';

  @override
  String get tutorialClose => 'Закрыть обучение';

  @override
  String get glossaryTitle => 'Словарь улик';

  @override
  String get glossaryBeside =>
      'Рядом: вплотную (сверху, снизу, слева, справа).';

  @override
  String get glossaryDirections =>
      'Север — вверх, юг — вниз, запад — влево, восток — вправо.';

  @override
  String get glossaryRowCol =>
      'Тот же этаж: та же строка. Тот же коридор: та же колонка.';

  @override
  String get languageLabel => 'Язык';

  @override
  String get languageSystem => 'Системный';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get stateBlocked => 'нельзя занять';

  @override
  String get legendTitle => 'Легенда';

  @override
  String get suspectsHeader => 'Подозреваемые';

  @override
  String get legendRooms => 'Комнаты';

  @override
  String get legendItems => 'Предметы';

  @override
  String get legendOccupiable => 'гость может сесть';

  @override
  String get pauseMenuTitle => 'Меню';

  @override
  String get abandonCase => 'Покинуть дело';
}
