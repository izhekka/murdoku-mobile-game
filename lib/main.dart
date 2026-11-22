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
@visibleForTesting
Future<SemanticsHandle> murdokuBootstrap({
  int? forcedSeed,
  bool skipTutorial = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Веб: семантическое дерево сразу — скринридеры и автоматизация видят
  // все виджеты (кнопки, доску, карточки с уликами).
  final semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };
  ErrorWidget.builder = fatalErrorWidget;
  await runZonedGuarded(
    () async {
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
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
    },
  );
  return semanticsHandle;
}
