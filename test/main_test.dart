import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/main.dart';
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
    final handle = await murdokuBootstrap();
    await tester.pumpAndSettle();

    expect(find.text('Murdoku'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('murdoku.tutorialSeen'), isNull);

    handle.dispose();
  });
}
