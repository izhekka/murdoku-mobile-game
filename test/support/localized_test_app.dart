import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';

/// MaterialApp with the app's exact localization setup (lib/app.dart) for
/// widget tests: the generated AppLocalizations delegates plus material_ui's
/// and cupertino_ui's own Global delegates appended LAST. The SDK
/// flutter_localizations delegates inside
/// AppLocalizations.localizationsDelegates do not provide material_ui's
/// lookup types, so non-English locales raise "A MaterialLocalizations
/// delegate that supports the ru locale was not found" without them
/// (issue 21; the local fix in suspect_panel_test.dart came from issue 18).
Widget localizedTestApp({
  Locale locale = const Locale('en'),
  required Widget child,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
