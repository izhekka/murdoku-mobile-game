import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murdoku/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/providers.dart';

Future<void> main() => murdokuBootstrap();

/// App bootstrap. [forcedSeed] pins the random seed of the next new case —
/// used by integration tests for determinism. [skipTutorial] pre-marks the
/// first-launch tutorial as seen (integration tests).
@visibleForTesting
Future<void> murdokuBootstrap({int? forcedSeed, bool skipTutorial = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };
  ErrorWidget.builder = fatalErrorWidget;
  await runZonedGuarded(() async {
    final prefs = await SharedPreferences.getInstance();
    if (skipTutorial) {
      await prefs.setBool('murdoku.tutorialSeen', true);
    }
    runApp(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (forcedSeed != null)
          forcedSeedProvider.overrideWithValue(forcedSeed),
      ],
      child: const MurdokuApp(),
    ));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}
