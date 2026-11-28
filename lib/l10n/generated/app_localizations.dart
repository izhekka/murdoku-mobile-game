import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Murdoku'**
  String get appTitle;

  /// No description provided for @fatalErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please restart the app.'**
  String get fatalErrorMessage;

  /// No description provided for @howToPlayTitle.
  ///
  /// In en, this message translates to:
  /// **'How to play'**
  String get howToPlayTitle;

  /// No description provided for @gameTitle.
  ///
  /// In en, this message translates to:
  /// **'Case'**
  String get gameTitle;

  /// No description provided for @statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statsTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @continueCase.
  ///
  /// In en, this message translates to:
  /// **'Continue case'**
  String get continueCase;

  /// No description provided for @newCase.
  ///
  /// In en, this message translates to:
  /// **'New case'**
  String get newCase;

  /// No description provided for @dailyCase.
  ///
  /// In en, this message translates to:
  /// **'Daily case'**
  String get dailyCase;

  /// No description provided for @dailyCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get dailyCompleted;

  /// No description provided for @difficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// No description provided for @difficultyStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get difficultyStandard;

  /// No description provided for @difficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// No description provided for @discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard current case?'**
  String get discardTitle;

  /// No description provided for @discardBody.
  ///
  /// In en, this message translates to:
  /// **'Starting a new case discards your current progress.'**
  String get discardBody;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @chooseDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Choose difficulty'**
  String get chooseDifficulty;

  /// No description provided for @objectPiano.
  ///
  /// In en, this message translates to:
  /// **'Piano'**
  String get objectPiano;

  /// No description provided for @objectPlant.
  ///
  /// In en, this message translates to:
  /// **'Plant'**
  String get objectPlant;

  /// No description provided for @objectArmor.
  ///
  /// In en, this message translates to:
  /// **'Suit of armor'**
  String get objectArmor;

  /// No description provided for @objectChest.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get objectChest;

  /// No description provided for @objectClock.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get objectClock;

  /// No description provided for @objectGlobe.
  ///
  /// In en, this message translates to:
  /// **'Globe'**
  String get objectGlobe;

  /// No description provided for @objectPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get objectPortrait;

  /// No description provided for @objectFireplace.
  ///
  /// In en, this message translates to:
  /// **'Fireplace'**
  String get objectFireplace;

  /// No description provided for @victimLabel.
  ///
  /// In en, this message translates to:
  /// **'Victim'**
  String get victimLabel;

  /// No description provided for @cellSemantics.
  ///
  /// In en, this message translates to:
  /// **'Row {row}, column {column}, {room}, {state}'**
  String cellSemantics(int row, int column, String room, String state);

  /// No description provided for @stateEmpty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get stateEmpty;

  /// No description provided for @stateExcluded.
  ///
  /// In en, this message translates to:
  /// **'marked empty'**
  String get stateExcluded;

  /// No description provided for @stateVictim.
  ///
  /// In en, this message translates to:
  /// **'victim'**
  String get stateVictim;

  /// No description provided for @victimName.
  ///
  /// In en, this message translates to:
  /// **'the victim'**
  String get victimName;

  /// No description provided for @dirNorth.
  ///
  /// In en, this message translates to:
  /// **'north'**
  String get dirNorth;

  /// No description provided for @dirSouth.
  ///
  /// In en, this message translates to:
  /// **'south'**
  String get dirSouth;

  /// No description provided for @dirEast.
  ///
  /// In en, this message translates to:
  /// **'east'**
  String get dirEast;

  /// No description provided for @dirWest.
  ///
  /// In en, this message translates to:
  /// **'west'**
  String get dirWest;

  /// No description provided for @clueInRoom.
  ///
  /// In en, this message translates to:
  /// **'— in the {room}'**
  String clueInRoom(String room);

  /// No description provided for @clueInRoomNot.
  ///
  /// In en, this message translates to:
  /// **'— not in the {room}'**
  String clueInRoomNot(String room);

  /// No description provided for @clueSameRow.
  ///
  /// In en, this message translates to:
  /// **'— on the same floor as {target}'**
  String clueSameRow(String target);

  /// No description provided for @clueSameRowNot.
  ///
  /// In en, this message translates to:
  /// **'— not on the same floor as {target}'**
  String clueSameRowNot(String target);

  /// No description provided for @clueSameCol.
  ///
  /// In en, this message translates to:
  /// **'— in the same corridor as {target}'**
  String clueSameCol(String target);

  /// No description provided for @clueSameColNot.
  ///
  /// In en, this message translates to:
  /// **'— not in the same corridor as {target}'**
  String clueSameColNot(String target);

  /// No description provided for @clueDirection.
  ///
  /// In en, this message translates to:
  /// **'— {direction} of {target}'**
  String clueDirection(String direction, String target);

  /// No description provided for @clueDirectionNot.
  ///
  /// In en, this message translates to:
  /// **'— not {direction} of {target}'**
  String clueDirectionNot(String direction, String target);

  /// No description provided for @clueBeside.
  ///
  /// In en, this message translates to:
  /// **'— beside {target}'**
  String clueBeside(String target);

  /// No description provided for @clueBesideNot.
  ///
  /// In en, this message translates to:
  /// **'— not beside {target}'**
  String clueBesideNot(String target);

  /// No description provided for @clueBesideObject.
  ///
  /// In en, this message translates to:
  /// **'— in the same room as the {object}'**
  String clueBesideObject(String object);

  /// No description provided for @clueBesideObjectNot.
  ///
  /// In en, this message translates to:
  /// **'— not in the same room as the {object}'**
  String clueBesideObjectNot(String object);

  /// No description provided for @accuse.
  ///
  /// In en, this message translates to:
  /// **'Accuse'**
  String get accuse;

  /// No description provided for @accuseTitle.
  ///
  /// In en, this message translates to:
  /// **'Who did it?'**
  String get accuseTitle;

  /// No description provided for @toolPlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get toolPlace;

  /// No description provided for @toolMark.
  ///
  /// In en, this message translates to:
  /// **'Mark'**
  String get toolMark;

  /// No description provided for @toolHint.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get toolHint;

  /// No description provided for @toolAccuse.
  ///
  /// In en, this message translates to:
  /// **'Accuse'**
  String get toolAccuse;

  /// No description provided for @toolMarkTooltip.
  ///
  /// In en, this message translates to:
  /// **'Mark a cell as empty'**
  String get toolMarkTooltip;

  /// No description provided for @toolHintTooltip.
  ///
  /// In en, this message translates to:
  /// **'Get a hint'**
  String get toolHintTooltip;

  /// No description provided for @timerSemantics.
  ///
  /// In en, this message translates to:
  /// **'{difficulty}, elapsed {time}'**
  String timerSemantics(String difficulty, String time);

  /// No description provided for @alibi.
  ///
  /// In en, this message translates to:
  /// **'{name} has an airtight alibi.'**
  String alibi(String name);

  /// No description provided for @victoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Case closed!'**
  String get victoryTitle;

  /// No description provided for @victoryTime.
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String victoryTime(String time);

  /// No description provided for @victoryMistakes.
  ///
  /// In en, this message translates to:
  /// **'Mistakes: {count}'**
  String victoryMistakes(int count);

  /// No description provided for @victoryDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get victoryDone;

  /// No description provided for @revealSolution.
  ///
  /// In en, this message translates to:
  /// **'Reveal solution'**
  String get revealSolution;

  /// No description provided for @revealConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reveal the solution?'**
  String get revealConfirmTitle;

  /// No description provided for @revealConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This forfeits the case.'**
  String get revealConfirmBody;

  /// No description provided for @quitCase.
  ///
  /// In en, this message translates to:
  /// **'Quit case'**
  String get quitCase;

  /// No description provided for @quitConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Quit this case?'**
  String get quitConfirmTitle;

  /// No description provided for @quitConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your progress on this case will be lost.'**
  String get quitConfirmBody;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @hintTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a hint'**
  String get hintTitle;

  /// No description provided for @hintPlace.
  ///
  /// In en, this message translates to:
  /// **'Reveal a suspect\'s position'**
  String get hintPlace;

  /// No description provided for @hintEliminate.
  ///
  /// In en, this message translates to:
  /// **'Rule out a suspect'**
  String get hintEliminate;

  /// No description provided for @hintsLeft.
  ///
  /// In en, this message translates to:
  /// **'Hints left: {count}'**
  String hintsLeft(int count);

  /// No description provided for @noActiveCase.
  ///
  /// In en, this message translates to:
  /// **'No active case.'**
  String get noActiveCase;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @playAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get playAgain;

  /// No description provided for @statsSolved.
  ///
  /// In en, this message translates to:
  /// **'Solved: {n}'**
  String statsSolved(int n);

  /// No description provided for @statsBest.
  ///
  /// In en, this message translates to:
  /// **'Best: {time}'**
  String statsBest(String time);

  /// No description provided for @statsAverage.
  ///
  /// In en, this message translates to:
  /// **'Average: {time}'**
  String statsAverage(String time);

  /// No description provided for @currentStreak.
  ///
  /// In en, this message translates to:
  /// **'Daily streak: {n}'**
  String currentStreak(int n);

  /// No description provided for @totalCasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Total cases: {n}'**
  String totalCasesLabel(int n);

  /// No description provided for @statsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cases solved yet. Start a new case!'**
  String get statsEmpty;

  /// No description provided for @themeModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeModeLabel;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @skinLabel.
  ///
  /// In en, this message translates to:
  /// **'Skin'**
  String get skinLabel;

  /// No description provided for @skinClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get skinClassic;

  /// No description provided for @skinCandy.
  ///
  /// In en, this message translates to:
  /// **'Candy'**
  String get skinCandy;

  /// No description provided for @skinSticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get skinSticker;

  /// No description provided for @skinComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get skinComic;

  /// No description provided for @hapticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Haptics'**
  String get hapticsLabel;

  /// No description provided for @resetProgress.
  ///
  /// In en, this message translates to:
  /// **'Reset all progress'**
  String get resetProgress;

  /// No description provided for @resetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset all progress?'**
  String get resetConfirmTitle;

  /// No description provided for @resetConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This clears saves, statistics and the daily streak. Your settings are kept.'**
  String get resetConfirmBody;

  /// No description provided for @progressReset.
  ///
  /// In en, this message translates to:
  /// **'Progress reset.'**
  String get progressReset;

  /// No description provided for @rule1Text.
  ///
  /// In en, this message translates to:
  /// **'Each guest appears exactly once in every row, column and room — like a sudoku of suspects.'**
  String get rule1Text;

  /// No description provided for @rule2Text.
  ///
  /// In en, this message translates to:
  /// **'Every clue is true. Clues are rules, not hints.'**
  String get rule2Text;

  /// No description provided for @rule3Text.
  ///
  /// In en, this message translates to:
  /// **'The map is evidence — rooms and objects are where the story happens.'**
  String get rule3Text;

  /// No description provided for @rule4Text.
  ///
  /// In en, this message translates to:
  /// **'One guest shares a room with the victim. That guest is the murderer. Find them last.'**
  String get rule4Text;

  /// No description provided for @tutorialXHint.
  ///
  /// In en, this message translates to:
  /// **'Use X marks to eliminate cells you know are impossible.'**
  String get tutorialXHint;

  /// No description provided for @tutorialNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get tutorialNext;

  /// No description provided for @tutorialDone.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get tutorialDone;

  /// No description provided for @tutorialClose.
  ///
  /// In en, this message translates to:
  /// **'Close tutorial'**
  String get tutorialClose;

  /// No description provided for @glossaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clue glossary'**
  String get glossaryTitle;

  /// No description provided for @glossaryBeside.
  ///
  /// In en, this message translates to:
  /// **'Beside: directly adjacent (up, down, left, right).'**
  String get glossaryBeside;

  /// No description provided for @glossaryDirections.
  ///
  /// In en, this message translates to:
  /// **'North is up, south is down, west is left, east is right.'**
  String get glossaryDirections;

  /// No description provided for @glossaryRowCol.
  ///
  /// In en, this message translates to:
  /// **'Same floor: the same row. Same corridor: the same column.'**
  String get glossaryRowCol;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @stateBlocked.
  ///
  /// In en, this message translates to:
  /// **'cannot hold a guest'**
  String get stateBlocked;

  /// No description provided for @legendTitle.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get legendTitle;

  /// No description provided for @suspectsHeader.
  ///
  /// In en, this message translates to:
  /// **'Suspects'**
  String get suspectsHeader;

  /// No description provided for @legendRooms.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get legendRooms;

  /// No description provided for @legendItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get legendItems;

  /// No description provided for @legendOccupiable.
  ///
  /// In en, this message translates to:
  /// **'a guest can sit here'**
  String get legendOccupiable;

  /// No description provided for @pauseMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get pauseMenuTitle;

  /// No description provided for @abandonCase.
  ///
  /// In en, this message translates to:
  /// **'Abandon case'**
  String get abandonCase;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
