import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/pause_menu_sheet.dart';

/// Pumps a MaterialApp with the skin scope at the builder level (mirroring
/// lib/app.dart: modal sheets live on the navigator, above any home-body
/// scope) and opens the pause menu sheet.
Future<void> pumpSheet(
  WidgetTester tester, {
  SkinTokens? tokens,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => tokens == null
        ? child!
        : SkinScope(tokens: tokens, child: child!),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () =>
                PauseMenuSheet.show(context, onAbandon: () {}),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('classic skin keeps the icon list tiles (issue 23)',
      (tester) async {
    await pumpSheet(tester);
    expect(find.byType(PauseMenuSheet), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('cartoon skin renders an icon-free list card with hairline '
      'separators and a danger accent (issue 23)', (tester) async {
    await pumpSheet(tester, tokens: comicTokens);
    expect(find.byType(PauseMenuSheet), findsOneWidget);
    // Icon-free rows.
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.menu_book), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
    // Hairline separators between title and rows.
    expect(find.byType(Divider), findsNWidgets(4));
    // «Покинуть дело» keeps the orange danger accent.
    final abandon = tester.widget<Text>(
        find.descendant(
            of: find.byType(PauseMenuSheet),
            matching: find.text('Abandon case')).first);
    expect(abandon.style?.color, comicTokens.dangerColor);
    // Rows render in the skin ink.
    final resume = tester.widget<Text>(
        find.descendant(
            of: find.byType(PauseMenuSheet),
            matching: find.text('Resume')).first);
    expect(resume.style?.color, comicTokens.ink);
  });
}
