import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show GoRouter;
import 'package:material_ui/material_ui.dart';

import 'package:murdoku/core/routes.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart'
    show LanguageSetting, Settings, SkinSetting;

/// Single source of truth for the app's localization delegates: both
/// MurdokuApp and test/support/localized_test_app.dart pass exactly this
/// const (identity-checked by tests) so they cannot drift (issue 24).
const List<LocalizationsDelegate<dynamic>> murdokuLocalizationsDelegates = [
  // material_ui's own MaterialLocalizations must come last: components
  // look up material_ui's type, which the SDK flutter_localizations
  // delegates do not provide (they implement the deprecated
  // flutter/material type). Without this, non-English locales crash.
  // Cupertino: cupertino_ui's delegate likewise provides the type
  // material_ui's WidgetsApp checks (the SDK one implements the
  // deprecated flutter/cupertino type).
  ...AppLocalizations.localizationsDelegates,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class MurdokuApp extends ConsumerStatefulWidget {
  const MurdokuApp({super.key});

  @override
  ConsumerState<MurdokuApp> createState() => _MurdokuAppState();
}

class _MurdokuAppState extends ConsumerState<MurdokuApp> {
  /// One router for the app's lifetime (issue 76, found by the iOS pixel
  /// fidelity capture driver): `buildRouter()` in `build` handed
  /// MaterialApp.router a fresh GoRouter on every settings-driven rebuild
  /// (theme/skin/language change), which reset navigation to the home route
  /// and kicked the player out of the settings screen.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp.router(
      title: 'Murdoku',
      theme: AppTheme.forSkin(settings.skin, Brightness.light),
      darkTheme: AppTheme.forSkin(settings.skin, Brightness.dark),
      themeMode: _themeModeFor(settings),
      locale: _localeFor(settings.language),
      localizationsDelegates: murdokuLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
      builder: (context, child) {
        // The builder context sits below MaterialApp, so the theme here is
        // the resolved one — classic tokens derive from its live scheme and
        // can never drift from the seed output.
        final tokens = skinTokensFor(
          settings.skin,
          Theme.of(context).colorScheme,
        );
        return SkinScope(
          tokens: tokens,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Cartoon skins are light-only designs: the ThemeMode choice applies to
/// the classic skin alone (issue 23).
ThemeMode _themeModeFor(Settings settings) =>
    settings.skin == SkinSetting.classic ? settings.themeMode : ThemeMode.light;

/// The app locale for a language preference; null follows the platform.
Locale? _localeFor(LanguageSetting language) => switch (language) {
  LanguageSetting.system => null,
  LanguageSetting.russian => const Locale('ru'),
  LanguageSetting.english => const Locale('en'),
};

/// Friendly replacement for the default red error screen; resolved inside
/// the app so localizations are available.
Widget fatalErrorWidget(FlutterErrorDetails details) {
  return Builder(
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n?.fatalErrorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ),
      );
    },
  );
}
