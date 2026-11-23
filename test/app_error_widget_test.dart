import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';

import 'support/localized_test_app.dart';

void main() {
  testWidgets('fatalErrorWidget renders the localized message with delegates', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        child: fatalErrorWidget(
          FlutterErrorDetails(exception: Exception('boom')),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Something went wrong. Please restart the app.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'fatalErrorWidget falls back to plain English without delegates',
    (tester) async {
      // A bare MaterialApp (no localization delegates): AppLocalizations.of
      // resolves null, so the hard-coded fallback sentence renders.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => fatalErrorWidget(
              FlutterErrorDetails(exception: Exception('boom')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong.'), findsOneWidget);
    },
  );
}
