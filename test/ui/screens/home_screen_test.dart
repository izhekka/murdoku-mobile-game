import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/case_pool.dart';
import 'package:murdoku/state/clock.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/game_screen.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/widgets/skin_card.dart' as skin_widgets;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/case_pool_fixture.dart';
import '../../support/seeded_overrides.dart';

Pos p(int row, int col) => (row: row, col: col);

void main() {
  late ProviderContainer container;

  testWidgets('home init triggers the pool refill check (issue 108)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PrefsRepository(prefs).saveTutorialSeen(true);
    final calls = <(Difficulty, int)>[];
    final testContainer = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // No forcedSeed pin: the refill check must actually run. All pools
        // are empty, so each difficulty gets its own background batch.
        casePoolBatchProvider.overrideWithValue((difficulty, count) async {
          calls.add((difficulty, count));
          return [
            for (var i = 0; i < count; i++) poolCase(difficulty, 1000 + i),
          ];
        }),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 15)),
      ],
    );
    addTearDown(testContainer.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: testContainer,
        child: const MurdokuApp(),
      ),
    );
    // First pump runs home's post-frame callbacks (the refill check);
    // the stub batches complete in microtasks flushed by the next pump.
    // pumpEventQueue is unusable here: inside a widget test's FakeAsync
    // zone its bounded timeout never elapses in fake time.
    await tester.pump();
    await tester.pump();

    expect(calls, [
      (Difficulty.easy, 10),
      (Difficulty.standard, 10),
      (Difficulty.hard, 10),
    ]);
  });

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
        // Issue 49: the daily card starts startDaily(utcToday(clockProvider)),
        // so the tapped daily case is date-seeded from the wall clock. Pin the
        // clock so a UTC-midnight crossing between runs cannot flip the
        // generated daily case and with it the coverage DA sets.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 15)),
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
  /// asserting against a possibly unsettled frame (issues 25/32):
  /// pumpAndSettle's exit condition can race with post-frame/timer frame
  /// scheduling, so the multi-dialog flow's stage gates wait on UI presence
  /// explicitly. The
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

  /// Margin-inclusive rect of every home [SkinCard], top-sorted, as the
  /// consecutive outer gaps between neighbors. Both skin implementations
  /// keep the card margin inside this render box (cartoon: SkinCard's own
  /// default `Padding(4)`; classic: the Card theme margin's inline
  /// `Padding`), so the drawn cream separator between two card surfaces
  /// equals `outerGap + 2 * skinMargin` (issue 96).
  List<double> homeCardGaps(WidgetTester tester) {
    final boxes = <Rect>[];
    for (final element in find.byType(skin_widgets.SkinCard).evaluate()) {
      final box = element.findRenderObject()! as RenderBox;
      boxes.add(box.localToGlobal(Offset.zero) & box.size);
    }
    boxes.sort((a, b) => a.top.compareTo(b.top));
    return [
      for (var i = 0; i < boxes.length - 1; i++)
        boxes[i + 1].top - boxes[i].bottom,
    ];
  }

  /// Pin the surface to the issue's 402×874 logical phone frame.
  Future<void> usePhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1206, 2622); // 402x874 @ dpr 3
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The issue's acceptance shape: every drawn separator identical within
  /// 1 logical px, and each one on the skin's uniform value (sticker: 16 =
  /// 2×4 margin + 8 spacer; classic: 24 = 2×8 + 8).
  void expectUniformRhythm(
    WidgetTester tester, {
    required double skinMargin,
    required double separator,
    required int gapCount,
  }) {
    final gaps = homeCardGaps(tester);
    expect(gaps, hasLength(gapCount));
    final separators = gaps.map((g) => g + 2 * skinMargin).toList();
    for (final s in separators.skip(1)) {
      expect(
        s,
        closeTo(separators.first, 1),
        reason: 'separators must be equal within 1 px: $separators',
      );
    }
    for (final s in separators) {
      expect(
        s,
        closeTo(separator, 1),
        reason: 'separator must hold the skin rhythm: $separators',
      );
    }
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
    // Issue 25/32 — explicit waiting, no timing guesses, and no dependence
    // on the scheduler's hasScheduledFrame state (pumpAndSettle's exit
    // condition), which can interact with timer/post-frame frame scheduling
    // under suite-level load. A fixed fake-time budget is exact: one
    // jump-frame completes the sheet entrance animation (250 ms Material
    // default), deterministically.
    await tester.pump(); // dispatch: sheet route pushed
    await tester.pump(const Duration(milliseconds: 400));
    // Stage gate: the difficulty chooser is fully open before interacting.
    expect(find.text(l10n.chooseDifficulty), findsOneWidget);

    // Difficulty chooser bottom sheet.
    await tester.tap(find.text(l10n.difficultyHard).last);
    // Dispatch the frame carrying the concurrent sheet pop + dialog push.
    await tester.pump();
    // Fixed budget: both animations (sheet exit 250 ms, dialog entrance
    // 200 ms) complete in one jump-frame — no scheduler-state dependence.
    await tester.pump(const Duration(milliseconds: 400));
    // Stage gate: the confirm dialog is present.
    await pumpUntil(tester, find.text(l10n.discardTitle));
    expect(find.text(l10n.discardTitle), findsOneWidget);

    await tester.tap(find.text(l10n.discard));
    // Dispatch the frame carrying the dialog pop; the microtask flush inside
    // this pump also runs the confirm side effects (startNewCase +
    // go('/game'), synchronous completers on Route.didPop).
    await tester.pump();
    // Fixed budget: dialog exit (200 ms), home exit and /game zoom
    // transition (300 ms) complete in one jump-frame.
    await tester.pump(const Duration(milliseconds: 600));
    // Margin pump for any status-followup frame. The flow's total fake time
    // stays >= 600 ms below GameScreen's 1-second tick timer's first fire,
    // so the timer can never fire between the pumps of this flow (issue 32).
    await tester.pump(const Duration(milliseconds: 300));
    // Stage gate: the game screen is mounted; a bounded presence gate is
    // immune to late-scheduled frames from the route chain. tick() is
    // elapsed-only and the assertions below are elapsed-independent, so
    // even a pumpUntil hunt cannot break them.
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
      const DailyState(lastCompletedDate: '2026-11-20', streak: 1),
    );
    container = ProviderContainer(
      overrides: [
        ...seededOverrides(prefs),
        // Issue 49: same fixed clock as pumpHome, so the done marker asserts
        // against a pinned date instead of the wall clock.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 15)),
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

  group('navigation coverage pins (issue 35)', () {
    testWidgets('continue card resumes the saved case on /game', (
      tester,
    ) async {
      await pumpHome(tester);
      final l10n = l10nOf(tester);
      final notifier = container.read(gameControllerProvider.notifier);
      notifier.startNewCase(Difficulty.easy, seed: 3);
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.continueCase));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board_view')), findsOneWidget);
    });

    testWidgets('daily card starts the daily case on /game', (tester) async {
      await pumpHome(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.dailyCase));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board_view')), findsOneWidget);
      final state = container.read(gameControllerProvider)!;
      expect(state.isDaily, isTrue);
      // Issue 49: the daily card seeds from the wall clock; with the pinned
      // clock the tapped case must be exactly the 2026-11-20 daily.
      expect(state.dailyDate, '2026-11-20');
      expect(
        state.caseData.toJson(),
        generateCase(
          difficulty: Difficulty.standard,
          seed: dailySeedFor(parseUtcDate('2026-11-20')),
        ).toJson(),
        reason: "the daily tap builds standard's seed 20261120",
      );
    });

    testWidgets('how-to-play, stats and settings tiles navigate', (
      tester,
    ) async {
      await pumpHome(tester);
      final l10n = l10nOf(tester);

      Future<void> backHome() async {
        final context = tester.element(find.byType(Scaffold).first);
        GoRouter.of(context).go('/');
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(l10n.howToPlayTitle));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.text(l10n.howToPlayTitle), findsOneWidget);
      await backHome();

      await tester.tap(find.text(l10n.statsTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.statsTitle), findsOneWidget);
      expect(find.text(l10n.statsEmpty), findsOneWidget);
      await backHome();

      await tester.tap(find.text(l10n.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsTitle), findsOneWidget);
    });
  });

  group('home block gaps keep one rhythm (issue 96)', () {
    testWidgets('no save: both separators land on the 16 px rhythm', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpHome(tester);

      expectUniformRhythm(tester, skinMargin: 4, separator: 16, gapCount: 2);
    });

    testWidgets('saved game: the continue card joins the same rhythm', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpHome(tester);
      container
          .read(gameControllerProvider.notifier)
          .startNewCase(Difficulty.easy, seed: 3);
      await tester.pumpAndSettle();

      expectUniformRhythm(tester, skinMargin: 4, separator: 16, gapCount: 3);
    });

    testWidgets('no save, classic light: one uniform 24 px rhythm', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpHome(tester);
      container
          .read(settingsControllerProvider.notifier)
          .setSkin(SkinSetting.classic);
      await tester.pumpAndSettle();

      expectUniformRhythm(tester, skinMargin: 8, separator: 24, gapCount: 2);
    });

    testWidgets('saved game, classic dark: continue card joins the rhythm', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpHome(tester);
      container
          .read(settingsControllerProvider.notifier)
          .setSkin(SkinSetting.classic);
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      container
          .read(gameControllerProvider.notifier)
          .startNewCase(Difficulty.easy, seed: 3);
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomeScreen));
      expect(Theme.of(homeContext).brightness, Brightness.dark);
      expectUniformRhythm(tester, skinMargin: 8, separator: 24, gapCount: 3);
    });

    testWidgets('cartoon is light-only: dark request keeps the 16 px rhythm', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await pumpHome(tester);
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomeScreen));
      expect(Theme.of(homeContext).brightness, Brightness.light);
      expectUniformRhythm(tester, skinMargin: 4, separator: 16, gapCount: 2);
    });
  });
}
