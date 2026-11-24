import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:murdoku/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overrides every test container/scope that can host a case start must
/// carry (issue 36): the prefs mock plus a pinned forced seed, so no test
/// path — present or future — reaches the Random() fallback in
/// GameNotifier.startNewCase (lib/state/game_controller.dart) and flips
/// coverage-derived CRAP gate data between runs.
///
/// Daily starts are date-seeded via dailySeedFor and ignore the forced
/// seed; a daily tap is wall-clock deterministic only when the harness
/// also pins clockProvider to a fixed date (issue 49) — see pumpHome in
/// test/ui/screens/home_screen_test.dart.
///
/// The full-app paths these overrides cannot reach are the murdokuBootstrap
/// callers — the bootstrap contract (test/main_test.dart) and the smoke
/// test (integration_test/smoke_test.dart): murdokuBootstrap builds its own
/// ProviderScope, so container overrides never apply there. Instead:
/// (1) an unseeded murdokuBootstrap() test must stay start-free — no case
/// start may run in it, enforced by the guard test 'unseeded bootstrap
/// performs no case start (issue 48)'; and (2) any start-driven variant
/// must pass forcedSeed to murdokuBootstrap itself (see 'seeded bootstrap
/// drives a case start through the UI (issue 48)').
///
/// The quoted titles are grep anchors, not contracts — grep
/// test/main_test.dart for 'issue 48' if either title drifts.
List<Override> seededOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  forcedSeedProvider.overrideWithValue(3),
];
