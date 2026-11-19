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
}
