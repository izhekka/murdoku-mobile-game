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
}
