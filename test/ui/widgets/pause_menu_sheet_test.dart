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
  Size size = const Size(800, 600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          tokens == null ? child! : SkinScope(tokens: tokens, child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => PauseMenuSheet.show(context, onAbandon: () {}),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

/// Issue 109: at SE-landscape height with large text the sheet cannot fit
/// its content — prove the clip first, then drag-scroll each of the four
/// entries into the sheet's visible bounds, and finally tap the bottom-most
/// entry (Abandon) to prove it is hittable: a missed tap fails the test, and
/// the sheet closes.
Future<void> scrollToAndHitAbandon(WidgetTester tester) async {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(PauseMenuSheet)),
  )!;
  final sheetFinder = find.byType(PauseMenuSheet);
  // The clip: the last entry starts below the sheet's visible bottom.
  expect(
    tester.getRect(find.text(l10n.abandonCase)).bottom,
    greaterThan(tester.getRect(sheetFinder).bottom),
    reason: 'the sheet clips content without scrolling',
  );

  bool inView(Finder label) {
    final rect = tester.getRect(label);
    final sheet = tester.getRect(sheetFinder);
    return rect.top >= sheet.top && rect.bottom <= sheet.bottom;
  }

  for (final label in [
    l10n.resume,
    l10n.howToPlayTitle,
    l10n.settingsTitle,
    l10n.abandonCase,
  ]) {
    final finder = find.text(label);
    var reached = inView(finder);
    for (var i = 0; i < 8 && !reached; i++) {
      await tester.drag(sheetFinder, const Offset(0, -100));
      await tester.pumpAndSettle();
      reached = inView(finder);
    }
    expect(reached, isTrue, reason: '$label scroll-reachable');
  }
  await tester.tap(find.text(l10n.abandonCase));
  await tester.pumpAndSettle();
  expect(find.byType(PauseMenuSheet), findsNothing);
}

void main() {
  testWidgets('classic skin keeps the icon list tiles (issue 23)', (
    tester,
  ) async {
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
      find
          .descendant(
            of: find.byType(PauseMenuSheet),
            matching: find.text('Abandon case'),
          )
          .first,
    );
    expect(abandon.style?.color, comicTokens.dangerColor);
    // Rows render in the skin ink.
    final resume = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(PauseMenuSheet),
            matching: find.text('Resume'),
          )
          .first,
    );
    expect(resume.style?.color, comicTokens.ink);
  });

  testWidgets('SE landscape with large text: every entry scroll-reachable '
      'and hittable, classic (issue 109)', (tester) async {
    await pumpSheet(tester, size: const Size(667, 375), textScale: 2.0);
    await scrollToAndHitAbandon(tester);
  });

  testWidgets('SE landscape with large text: every entry scroll-reachable '
      'and hittable, cartoon (issue 109)', (tester) async {
    await pumpSheet(
      tester,
      size: const Size(667, 375),
      textScale: 2.0,
      tokens: comicTokens,
    );
    await scrollToAndHitAbandon(tester);
  });
}
