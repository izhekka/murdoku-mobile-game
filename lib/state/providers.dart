import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden with the real instance during bootstrap (main).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main',
  );
});

/// Optional fixed seed for [startNewCase]; overridden in integration tests.
final forcedSeedProvider = Provider<int?>((ref) => null);

final prefsRepositoryProvider = Provider<PrefsRepository>(
  (ref) => PrefsRepository(ref.watch(sharedPreferencesProvider)),
);
