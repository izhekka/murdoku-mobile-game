import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/main.dart';
import 'package:murdoku/state/case_pool.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/ui/screens/game_screen.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('murdokuBootstrap boots the home screen and honors flags', (
    tester,
  ) async {
    // murdokuBootstrap installs production error handlers; restore the test
    // binding's values afterwards so no state leaks between tests.
    final errorWidgetBuilder = ErrorWidget.builder;
    final flutterOnError = FlutterError.onError;
    addTearDown(() {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = flutterOnError;
    });

    SharedPreferences.setMockInitialValues({});
    final handle = await murdokuBootstrap(forcedSeed: 42, skipTutorial: true);
    await tester.pumpAndSettle();

    // The router's home route renders the app title.
    expect(find.text('Murdoku'), findsOneWidget);

    // skipTutorial pre-marks the first-launch tutorial as seen.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('murdoku.tutorialSeen'), isTrue);

    handle.dispose();
  });

  testWidgets('murdokuBootstrap without flags leaves the tutorial unseen', (
    tester,
  ) async {
    final errorWidgetBuilder = ErrorWidget.builder;
    final flutterOnError = FlutterError.onError;
    addTearDown(() {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = flutterOnError;
    });

    SharedPreferences.setMockInitialValues({});
    final handle = await murdokuBootstrap(
      // Unseeded boot runs home's pool refill check (issue 108); the empty
      // stub keeps this bootstrap test generation-free. Case starts are
      // unaffected (and none happen here — see the issue-48 test below).
      providerOverrides: [
        casePoolBatchProvider.overrideWithValue(
          (difficulty, count) async => const <CaseData>[],
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Murdoku'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('murdoku.tutorialSeen'), isNull);

    handle.dispose();
  });

  testWidgets('unseeded bootstrap performs no case start (issue 48)', (
    tester,
  ) async {
    // Standard teardown pair of the bootstrap tests (see the first test);
    // the semantics handle and the error handler are additionally released
    // right after settle so a failing expect below cannot wedge the run.
    final errorWidgetBuilder = ErrorWidget.builder;
    final flutterOnError = FlutterError.onError;
    addTearDown(() {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = flutterOnError;
    });

    SharedPreferences.setMockInitialValues({});
    final handle = await murdokuBootstrap(
      // Same empty batch stub as above: unseeded boot must stay
      // generation-free; the no-case-start contract below is unaffected.
      providerOverrides: [
        casePoolBatchProvider.overrideWithValue(
          (difficulty, count) async => const <CaseData>[],
        ),
      ],
    );
    await tester.pumpAndSettle();
    // Restore the test binding's error handler before asserting: with the
    // production FlutterError.onError still installed, a failing expect is
    // printed by that handler instead of reaching the test binding, and the
    // run wedges on the binding's pending-exception assertion. Boot ran
    // under the production handler; assertions run under the framework's.
    FlutterError.onError = flutterOnError;
    // Release the semantics handle before any expect: the end-of-test
    // verification requires zero active handles, and an expect failure must
    // not leave it undisposed (the failure path stays diagnosable).
    handle.dispose();

    // The bootstrap-contract path is the one full-app path seededOverrides
    // cannot reach (murdokuBootstrap builds its own ProviderScope), so it
    // must stay start-free: any case start here is unseeded or
    // wall-clock-dated (Random() fallback for new cases, UTC-date seed for
    // daily) and flips coverage-derived CRAP gate data between runs.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(gameControllerProvider), isNull);
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets(
    'seeded bootstrap drives a case start through the UI (issue 48)',
    (tester) async {
      // Standard teardown pair of the bootstrap tests (see the first test);
      // the semantics handle and the error handler are additionally released
      // right after settle so a failing expect below cannot wedge the run.
      final errorWidgetBuilder = ErrorWidget.builder;
      final flutterOnError = FlutterError.onError;
      addTearDown(() {
        ErrorWidget.builder = errorWidgetBuilder;
        FlutterError.onError = flutterOnError;
      });

      SharedPreferences.setMockInitialValues({});
      final handle = await murdokuBootstrap(forcedSeed: 3, skipTutorial: true);
      await tester.pumpAndSettle();
      FlutterError.onError = flutterOnError;
      handle.dispose();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      )!;

      // New case → difficulty sheet → Easy (no save exists: no discard
      // dialog). The forcedSeed pin makes the generated case — and with it
      // the coverage this start contributes to the CRAP gate — identical on
      // every run. Pump budgets and stage gates follow the home-screen suite
      // pattern (issues 25/32): pumpAndSettle's exit condition races with
      // post-frame/timer frame scheduling, so each stage waits explicitly.
      await tester.tap(find.text(l10n.newCase));
      await tester.pump(); // dispatch: sheet route pushed
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.chooseDifficulty), findsOneWidget);

      await tester.tap(find.text(l10n.difficultyEasy).last);
      // Dispatch the frame carrying the concurrent sheet pop + /game push.
      await tester.pump();
      // Fixed budget: sheet exit (250 ms) and the /game zoom transition
      // (300 ms) complete in one jump-frame.
      await tester.pump(const Duration(milliseconds: 600));

      final state = container.read(gameControllerProvider);
      expect(state, isNotNull);
      expect(state!.isDaily, isFalse);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.byType(SuspectPanel), findsOneWidget);
      expect(find.byType(ItemSprite), findsWidgets);
    },
  );
}
