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
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The discard-then-start test drives the real UI button, which starts
        // a case without an explicit seed; pin the seed so the generated clue
        // mix (and with it the coverage data the CRAP gate consumes) is
        // deterministic per run.
        forcedSeedProvider.overrideWithValue(3),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

  /// Explicit, bounded frame wait: pumps [step] at a time until [finder]
  /// matches, then returns. Fails fast with a precise reason instead of
  /// asserting against a possibly unsettled frame (issue 25): pumpAndSettle's
  /// exit condition can race with post-frame/timer frame scheduling, so the
  /// multi-dialog flow's stage gates wait on UI presence explicitly. The
  /// budget (6s of fake time at the default step) is far above any route
  /// transition and far below pumpAndSettle's runaway timeout.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration step = const Duration(milliseconds: 100),
    int maxPumps = 60,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('pumpUntil gave up after $maxPumps pumps: $finder');
  }

  testWidgets('no save: Continue button absent; nav rows present', (
    tester,
  ) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.continueCase), findsNothing);
    expect(find.text(l10n.newCase), findsOneWidget);
    expect(find.text(l10n.dailyCase), findsOneWidget);
    expect(find.text(l10n.statsTitle), findsOneWidget);
    expect(find.text(l10n.settingsTitle), findsOneWidget);
    expect(find.text(l10n.howToPlayTitle), findsOneWidget);
  });

  testWidgets('saved game: Continue visible with difficulty label', (
    tester,
  ) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    await tester.pumpAndSettle();

    expect(find.text(l10n.continueCase), findsOneWidget);
    // Difficulty label inside the "Easy · mm:ss" subtitle.
    expect(find.textContaining(l10n.difficultyEasy), findsOneWidget);
  });

  testWidgets('new case over an active save asks to discard, then starts', (
    tester,
  ) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.newCase));
    // Issue 25 — explicit waiting, no timing guesses: dispatch the frame
    // that pushes the sheet, then run its entrance animation to completion.
    await tester.pump();
    await tester.pumpAndSettle();
    // Stage gate: the difficulty chooser is fully open before interacting.
    expect(find.text(l10n.chooseDifficulty), findsOneWidget);

    // Difficulty chooser bottom sheet.
    await tester.tap(find.text(l10n.difficultyHard).last);
    // Dispatch the frame that pops the sheet and pushes the discard dialog;
    // settle both concurrent animations.
    await tester.pump();
    await tester.pumpAndSettle();
    // Stage gate: the confirm dialog is present.
    await pumpUntil(tester, find.text(l10n.discardTitle));
    expect(find.text(l10n.discardTitle), findsOneWidget);

    await tester.tap(find.text(l10n.discard));
    // Dispatch the frame carrying the dialog pop, the new-case start and the
    // /game navigation; settle the concurrent dialog exit and page
    // transition.
    await tester.pump();
    await tester.pumpAndSettle();
    // Stage gate: the game screen is mounted and settled despite its
    // 1-second tick timer scheduling frames.
    await pumpUntil(tester, find.byType(GameScreen));

    // New hard case started and navigated to the game screen.
    expect(find.byType(GameScreen), findsOneWidget);
    final state = container.read(gameControllerProvider)!;
    expect(state.caseData.difficulty, Difficulty.hard);
  });

  testWidgets('daily done state renders the completed marker', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final preRepo = PrefsRepository(prefs);
    await preRepo.saveDailyState(
      DailyState(
        lastCompletedDate: formatUtcDate(DateTime.now().toUtc()),
        streak: 1,
      ),
    );
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    expect(find.text(l10n.dailyCompleted), findsOneWidget);
  });

  testWidgets('cartoon skin: home cards use the token card container '
      '(issue 23)', (tester) async {
    await pumpHome(tester); // default skin: sticker
    final cardContainers = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Container),
        )
        .evaluate()
        .where(
          (e) =>
              (e.widget as Container).decoration is BoxDecoration &&
              ((e.widget as Container).decoration as BoxDecoration).color ==
                  stickerTokens.card.background,
        )
        .toList();
    expect(
      cardContainers.length,
      3,
      reason: 'new case, daily case and the nav card restyle to tokens',
    );
  });
}
