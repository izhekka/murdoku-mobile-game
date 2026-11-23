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
/// seed; daily taps stay deterministic without this pin.
List<Override> seededOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  forcedSeedProvider.overrideWithValue(3),
];
