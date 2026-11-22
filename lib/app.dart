import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';
import 'storage/prefs_repository.dart' show LanguageSetting;
import 'state/settings_controller.dart';

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

class MurdokuApp extends ConsumerWidget {
  const MurdokuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp.router(
      title: 'Murdoku',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      locale: switch (settings.language) {
        LanguageSetting.system => null,
        LanguageSetting.russian => const Locale('ru'),
        LanguageSetting.english => const Locale('en'),
      },
      localizationsDelegates: murdokuLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: buildRouter(),
    );
  }
}

/// Friendly replacement for the default red error screen; resolved inside
/// the app so localizations are available.
Widget fatalErrorWidget(FlutterErrorDetails details) {
  return Builder(builder: (context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n?.fatalErrorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        ),
      ),
    );
  });
}
