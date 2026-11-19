import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murdoku/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
  };
  ErrorWidget.builder = fatalErrorWidget;
  await runZonedGuarded(() async {
    final prefs = await SharedPreferences.getInstance();
    runApp(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MurdokuApp(),
    ));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}
