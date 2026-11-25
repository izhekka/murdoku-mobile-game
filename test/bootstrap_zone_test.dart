// Plain `test()` — deliberately not testWidgets (issue 81): flutter_test's
// TestWidgetsFlutterBinding overrides debugCheckZone to always pass, so a
// widget test cannot observe the production zone mismatch. With no
// testWidgets in this file, murdokuBootstrap's
// WidgetsFlutterBinding.ensureInitialized() actually initializes a real
// WidgetsFlutterBinding and its zone check is live, exactly like the
// detached `simctl launch` path.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'murdokuBootstrap initializes the binding and launches in one zone',
    () async {
      SharedPreferences.setMockInitialValues({});

      final savedDebugPrint = debugPrint;
      final savedErrorBuilder = ErrorWidget.builder;
      final savedOnError = FlutterError.onError;
      final printed = StringBuffer();
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.writeln(message);
        savedDebugPrint(message, wrapWidth: wrapWidth);
      };
      addTearDown(() {
        debugPrint = savedDebugPrint;
        ErrorWidget.builder = savedErrorBuilder;
        FlutterError.onError = savedOnError;
      });

      final handle = await murdokuBootstrap(forcedSeed: 42);

      // runApp schedules the root-widget attach on real timers inside the
      // boot zone: wait (bounded) for the tree to mount. The bound is
      // deliberately generous (15s) so a loaded runner fails only on a real
      // regression, never on mount-time jitter (review round, issue 81).
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (WidgetsBinding.instance.rootElement == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(WidgetsBinding.instance.rootElement, isNotNull);
      handle.dispose();

      // Pre-fix: the binding's debugCheckZone reports "Zone mismatch" during
      // runApp; the bootstrap's guarded sink additionally prints
      // "Uncaught zone error". Neither may appear.
      expect(printed.toString(), isNot(contains('Zone mismatch')));
      expect(printed.toString(), isNot(contains('Uncaught zone error')));
    },
  );
}
