import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import 'providers.dart';
import '../storage/prefs_repository.dart';

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() => ref.watch(prefsRepositoryProvider).loadSettings();

  void setThemeMode(ThemeMode mode) {
    state = Settings(themeMode: mode, haptics: state.haptics);
    _persist();
  }

  void setHaptics(bool enabled) {
    state = Settings(themeMode: state.themeMode, haptics: enabled);
    _persist();
  }

  void _persist() {
    ref.read(prefsRepositoryProvider).saveSettings(state);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
