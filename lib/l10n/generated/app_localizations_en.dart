// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Murdoku';

  @override
  String get fatalErrorMessage =>
      'Something went wrong. Please restart the app.';

  @override
  String get howToPlayTitle => 'How to play';

  @override
  String get gameTitle => 'Case';

  @override
  String get statsTitle => 'Statistics';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get continueCase => 'Continue case';

  @override
  String get newCase => 'New case';

  @override
  String get dailyCase => 'Daily case';

  @override
  String get dailyCompleted => 'Completed today';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyStandard => 'Standard';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get discardTitle => 'Discard current case?';

  @override
  String get discardBody =>
      'Starting a new case discards your current progress.';

  @override
  String get discard => 'Discard';

  @override
  String get cancel => 'Cancel';

  @override
  String get chooseDifficulty => 'Choose difficulty';

  @override
  String get objectPiano => 'Piano';

  @override
  String get objectPlant => 'Plant';

  @override
  String get objectArmor => 'Suit of armor';

  @override
  String get objectChest => 'Chest';

  @override
  String get objectClock => 'Clock';

  @override
  String get objectGlobe => 'Globe';

  @override
  String get objectPortrait => 'Portrait';

  @override
  String get objectFireplace => 'Fireplace';

  @override
  String get victimLabel => 'Victim';

  @override
  String cellSemantics(int row, int column, String room, String state) {
    return 'Row $row, column $column, $room, $state';
  }

  @override
  String get stateEmpty => 'empty';

  @override
  String get stateExcluded => 'marked empty';

  @override
  String get stateVictim => 'victim';

  @override
  String get victimName => 'the victim';

  @override
  String get dirNorth => 'north';

  @override
  String get dirSouth => 'south';

  @override
  String get dirEast => 'east';

  @override
  String get dirWest => 'west';

  @override
  String clueInRoom(String room) {
    return '— in the $room';
  }

  @override
  String clueInRoomNot(String room) {
    return '— not in the $room';
  }

  @override
  String clueSameRow(String target) {
    return '— in the same row as $target';
  }

  @override
  String clueSameRowNot(String target) {
    return '— not in the same row as $target';
  }

  @override
  String clueSameCol(String target) {
    return '— in the same column as $target';
  }

  @override
  String clueSameColNot(String target) {
    return '— not in the same column as $target';
  }

  @override
  String clueDirection(String direction, String target) {
    return '— $direction of $target';
  }

  @override
  String clueDirectionNot(String direction, String target) {
    return '— not $direction of $target';
  }

  @override
  String clueBeside(String target) {
    return '— beside $target';
  }

  @override
  String clueBesideNot(String target) {
    return '— not beside $target';
  }

  @override
  String clueBesideObject(String object) {
    return '— in the same room as the $object';
  }

  @override
  String clueBesideObjectNot(String object) {
    return '— not in the same room as the $object';
  }

  @override
  String clueOnObject(String object) {
    return '— sits on the $object';
  }

  @override
  String clueNearObject(String object) {
    return '— stays near the $object';
  }

  @override
  String clueSoleNearObject(String object) {
    return '— the only guest near the $object';
  }

  @override
  String get accuse => 'Accuse';

  @override
  String get accuseTitle => 'Who did it?';

  @override
  String get toolPlace => 'Place';

  @override
  String get toolMark => 'Mark';

  @override
  String get toolHint => 'Hint';

  @override
  String get toolAccuse => 'Accuse';

  @override
  String get toolMarkTooltip => 'Mark a cell as empty';

  @override
  String get toolHintTooltip => 'Get a hint';

  @override
  String timerSemantics(String difficulty, String time) {
    return '$difficulty, elapsed $time';
  }

  @override
  String alibi(String name) {
    return '$name has an airtight alibi.';
  }

  @override
  String get victoryTitle => 'Case closed!';

  @override
  String victoryTime(String time) {
    return 'Time: $time';
  }

  @override
  String victoryMistakes(int count) {
    return 'Mistakes: $count';
  }

  @override
  String get victoryDone => 'Done';

  @override
  String get revealSolution => 'Reveal solution';

  @override
  String get revealConfirmTitle => 'Reveal the solution?';

  @override
  String get revealConfirmBody => 'This forfeits the case.';

  @override
  String get quitCase => 'Quit case';

  @override
  String get quitConfirmTitle => 'Quit this case?';

  @override
  String get quitConfirmBody => 'Your progress on this case will be lost.';

  @override
  String get resume => 'Resume';

  @override
  String get hintTitle => 'Choose a hint';

  @override
  String get hintPlace => 'Reveal a suspect\'s position';

  @override
  String get hintEliminate => 'Rule out a suspect';

  @override
  String hintsLeft(int count) {
    return 'Hints left: $count';
  }

  @override
  String get noActiveCase => 'No active case.';

  @override
  String get backToHome => 'Back to home';

  @override
  String get playAgain => 'Play again';

  @override
  String statsSolved(int n) {
    return 'Solved: $n';
  }

  @override
  String statsBest(String time) {
    return 'Best: $time';
  }

  @override
  String statsAverage(String time) {
    return 'Average: $time';
  }

  @override
  String currentStreak(int n) {
    return 'Daily streak: $n';
  }

  @override
  String totalCasesLabel(int n) {
    return 'Total cases: $n';
  }

  @override
  String get statsEmpty => 'No cases solved yet. Start a new case!';

  @override
  String get themeModeLabel => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get skinLabel => 'Skin';

  @override
  String get skinClassic => 'Classic';

  @override
  String get skinCandy => 'Candy';

  @override
  String get skinSticker => 'Sticker';

  @override
  String get skinComic => 'Comic';

  @override
  String get hapticsLabel => 'Haptics';

  @override
  String get resetProgress => 'Reset all progress';

  @override
  String get resetConfirmTitle => 'Reset all progress?';

  @override
  String get resetConfirmBody =>
      'This clears saves, statistics and the daily streak. Your settings are kept.';

  @override
  String get progressReset => 'Progress reset.';

  @override
  String get rule1Text =>
      'Each guest appears exactly once in every row, column and room — like a sudoku of suspects.';

  @override
  String get rule2Text => 'Every clue is true. Clues are rules, not hints.';

  @override
  String get rule3Text =>
      'The map is evidence — rooms and objects are where the story happens.';

  @override
  String get rule4Text =>
      'One guest shares a room with the victim. That guest is the murderer. Find them last.';

  @override
  String get tutorialXHint =>
      'Use X marks to eliminate cells you know are impossible.';

  @override
  String get tutorialNext => 'Next';

  @override
  String get tutorialDone => 'Got it';

  @override
  String get tutorialClose => 'Close tutorial';

  @override
  String get glossaryTitle => 'Clue glossary';

  @override
  String get glossaryBeside =>
      'Beside: directly adjacent (up, down, left, right).';

  @override
  String get glossaryDirections =>
      'North is up, south is down, west is left, east is right.';

  @override
  String get glossaryObjects =>
      'Near: in a cell next to the item (up, down, left, right) or sitting on it.';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageRussian => 'Русский';

  @override
  String get languageEnglish => 'English';

  @override
  String get stateBlocked => 'cannot hold a guest';

  @override
  String get legendTitle => 'Legend';

  @override
  String get suspectsHeader => 'Suspects';

  @override
  String get legendRooms => 'Rooms';

  @override
  String get legendItems => 'Items';

  @override
  String get legendOccupiable => 'a guest can sit here';

  @override
  String get pauseMenuTitle => 'Menu';

  @override
  String get abandonCase => 'Abandon case';
}
