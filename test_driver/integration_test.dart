import 'package:integration_test/integration_test_driver.dart';

/// Host-side driver for the integration tests (Flutter docs standard
/// harness). Required to run `integration_test/smoke_test.dart` through
/// `flutter drive` — e.g. on the web where `flutter test -d <web device>`
/// is not supported:
///
/// ```sh
/// chromedriver --port=4444 &
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/smoke_test.dart \
///   -d chrome
/// ```
Future<void> main() => integrationDriver();
