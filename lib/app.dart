import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';
import 'state/settings_controller.dart';

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
