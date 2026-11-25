import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() => murdokuBootstrap();

/// App bootstrap. [forcedSeed] pins the random seed of the next new case —
/// used by integration tests for determinism. [skipTutorial] pre-marks the
/// first-launch tutorial as seen (integration tests).
///
/// Returns the [SemanticsHandle] for the semantics tree enabled at boot:
/// callers with a bounded lifetime (integration tests) can dispose it, while
/// the production entrypoint ignores it and keeps semantics on for the whole
/// app run.
///
/// Zone discipline (issue 81): the whole bootstrap runs inside one guarded
/// zone so `WidgetsFlutterBinding.ensureInitialized` and `runApp` execute in
/// the same zone. With the binding initialized before the guarded zone,
/// the binding's zone check (`BindingBase.debugCheckZone`) reports
/// "Zone mismatch" during `runApp` — absorbed under an attached `flutter run`,
/// but terminal for first paint on a detached debug launch (install +
/// `simctl launch` without `flutter run`).
@visibleForTesting
Future<SemanticsHandle> murdokuBootstrap({
  int? forcedSeed,
  bool skipTutorial = false,
}) async {
  // The body is an async closure, so it cannot throw synchronously and
  // runZonedGuarded never returns null here (null is only for synchronous
  // throws); its `!` documents that and keeps the return type clean.
  return (await runZonedGuarded<Future<SemanticsHandle>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Веб: семантическое дерево сразу — скринридеры и автоматизация видят
      // все виджеты (кнопки, доску, карточки с уликами).
      final semanticsHandle = SemanticsBinding.instance.ensureSemantics();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exception}');
      };
      ErrorWidget.builder = fatalErrorWidget;
      final prefs = await SharedPreferences.getInstance();
      if (skipTutorial) {
        await prefs.setBool('murdoku.tutorialSeen', true);
      }
      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            if (forcedSeed != null)
              forcedSeedProvider.overrideWithValue(forcedSeed),
          ],
          child: const MurdokuApp(),
        ),
      );
      return semanticsHandle;
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
    },
  ))!;
}
