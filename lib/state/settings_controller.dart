import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import 'providers.dart';
import '../storage/prefs_repository.dart';

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() => ref.watch(prefsRepositoryProvider).loadSettings();

  void setThemeMode(ThemeMode mode) {
    state = _copy(themeMode: mode);
    _persist();
  }

  void setHaptics(bool enabled) {
    state = _copy(haptics: enabled);
    _persist();
  }

  void setLanguage(LanguageSetting language) {
    state = _copy(language: language);
    _persist();
  }

  void setSkin(SkinSetting skin) {
    state = _copy(skin: skin);
    _persist();
  }

  Settings _copy({
    ThemeMode? themeMode,
    bool? haptics,
    LanguageSetting? language,
    SkinSetting? skin,
  }) =>
      Settings(
        themeMode: themeMode ?? state.themeMode,
        haptics: haptics ?? state.haptics,
        language: language ?? state.language,
        skin: skin ?? state.skin,
      );

  void _persist() {
    ref.read(prefsRepositoryProvider).saveSettings(state);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);
