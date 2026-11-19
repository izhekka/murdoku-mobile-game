import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/prefs_repository.dart';

/// Overridden with the real instance during bootstrap (main).
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main');
});

final prefsRepositoryProvider = Provider<PrefsRepository>(
    (ref) => PrefsRepository(ref.watch(sharedPreferencesProvider)));
