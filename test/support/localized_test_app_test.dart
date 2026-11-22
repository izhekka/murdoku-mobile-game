import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';

import 'localized_test_app.dart';

void main() {
  testWidgets('ru locale pumps without the MaterialLocalizations delegate '
      'exception (issue 21)', (tester) async {
    AppLocalizations? l10n;
    MaterialLocalizations? material;
    await tester.pumpWidget(localizedTestApp(
      locale: const Locale('ru'),
      child: Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        material = MaterialLocalizations.of(context);
        return const SizedBox.shrink();
      }),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'the helper carries the app delegate list (lib/app.dart)');
    expect(l10n?.localeName, 'ru',
        reason: 'AppLocalizations resolves for the pinned locale');
    expect(material?.backButtonTooltip, 'Назад',
        reason: 'material_ui\'s own MaterialLocalizations resolves with '
            'ru content (the delegates the generated list lacks)');
  });

  testWidgets('defaults to en', (tester) async {
    AppLocalizations? l10n;
    await tester.pumpWidget(localizedTestApp(
      child: Builder(
        builder: (context) {
          l10n = AppLocalizations.of(context);
          return const SizedBox.shrink();
        },
      ),
    ));
    await tester.pump();

    expect(l10n?.localeName, 'en');
  });
}
