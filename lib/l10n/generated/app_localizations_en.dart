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
}
