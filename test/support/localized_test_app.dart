import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';

/// MaterialApp with the app's exact localization setup (lib/app.dart) for
/// widget tests: it passes [murdokuLocalizationsDelegates] — the single
/// exported const in lib/app.dart — verbatim, so the helper can never drift
/// from the production localization setup (identity-checked by tests,
/// issue 24). The SDK flutter_localizations delegates inside that const do
/// not provide material_ui's lookup types, so non-English locales raise
/// "A MaterialLocalizations delegate that supports the ru locale was not
/// found" without the appended material_ui/cupertino_ui delegates (issue 21;
/// the local fix in suspect_panel_test.dart came from issue 18).
Widget localizedTestApp({
  Locale locale = const Locale('en'),
  required Widget child,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: murdokuLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
