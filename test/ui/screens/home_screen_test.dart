import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/game_screen.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

void main() {
  late ProviderContainer container;

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Home layout tests assume the first-launch tutorial is already dismissed;
    // the tutorial has its own test suite.
    await PrefsRepository(prefs).saveTutorialSeen(true);
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MurdokuApp(),
    ));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

  testWidgets('no save: Continue button absent; nav rows present', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.continueCase), findsNothing);
    expect(find.text(l10n.newCase), findsOneWidget);
    expect(find.text(l10n.dailyCase), findsOneWidget);
    expect(find.text(l10n.statsTitle), findsOneWidget);
    expect(find.text(l10n.settingsTitle), findsOneWidget);
    expect(find.text(l10n.howToPlayTitle), findsOneWidget);
  });

  testWidgets('saved game: Continue visible with difficulty label', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    await tester.pumpAndSettle();

    expect(find.text(l10n.continueCase), findsOneWidget);
    // Difficulty label inside the "Easy · mm:ss" subtitle.
    expect(find.textContaining(l10n.difficultyEasy), findsOneWidget);
  });

  testWidgets('new case over an active save asks to discard, then starts',
      (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.newCase));
    await tester.pumpAndSettle();

    // Difficulty chooser bottom sheet.
    await tester.tap(find.text(l10n.difficultyHard).last);
    await tester.pumpAndSettle();

    // Discard confirmation dialog.
    expect(find.text(l10n.discardTitle), findsOneWidget);
    await tester.tap(find.text(l10n.discard));
    await tester.pumpAndSettle();

    // New hard case started and navigated to the game screen.
    expect(find.byType(GameScreen), findsOneWidget);
    final state = container.read(gameControllerProvider)!;
    expect(state.caseData.difficulty, Difficulty.hard);
  });

  testWidgets('daily done state renders the completed marker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final preRepo = PrefsRepository(prefs);
    await preRepo.saveDailyState(DailyState(
      lastCompletedDate: formatUtcDate(DateTime.now().toUtc()),
      streak: 1,
    ));
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MurdokuApp(),
    ));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    expect(find.text(l10n.dailyCompleted), findsOneWidget);
  });

  testWidgets('cartoon skin: home cards use the token card container '
      '(issue 23)', (tester) async {
    await pumpHome(tester); // default skin: sticker
    final cardContainers = find
        .descendant(
            of: find.byType(HomeScreen), matching: find.byType(Container))
        .evaluate()
        .where((e) =>
            (e.widget as Container).decoration is BoxDecoration &&
            ((e.widget as Container).decoration as BoxDecoration).color ==
                stickerTokens.card.background)
        .toList();
    expect(cardContainers.length, 3,
        reason: 'new case, daily case and the nav card restyle to tokens');
  });
}
