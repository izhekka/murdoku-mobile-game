import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/ui/screens/how_to_play_screen.dart';
import 'package:murdoku/ui/widgets/tutorial_overlay.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

Future<ProviderContainer> pumpApp(WidgetTester tester,
    {SharedPreferences? withPrefs}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = withPrefs ?? await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MurdokuApp(),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('first launch shows the tutorial overlay', (tester) async {
    await pumpApp(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(TutorialOverlay), findsOneWidget);
    expect(find.text(l10n.rule1Text), findsOneWidget);
  });

  testWidgets('dismissing the tutorial persists the flag', (tester) async {
    final container = await pumpApp(tester);
    final l10n = l10nOf(tester);
    final repo = container.read(prefsRepositoryProvider);
    expect(repo.loadTutorialSeen(), isFalse);

    // Walk through the three pages, then finish.
    await tester.tap(find.text(l10n.tutorialNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.tutorialNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.tutorialDone));
    await tester.pumpAndSettle();

    expect(find.byType(TutorialOverlay), findsNothing);
    expect(repo.loadTutorialSeen(), isTrue);
  });

  testWidgets('tutorial is not shown again after the flag is set',
      (tester) async {
    SharedPreferences.setMockInitialValues({'murdoku.tutorialSeen': true});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, withPrefs: prefs);

    expect(find.byType(TutorialOverlay), findsNothing);
  });

  testWidgets('how-to-play screen shows all four rules and the glossary',
      (tester) async {
    await pumpApp(tester);
    final l10n = l10nOf(tester);
    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/how-to-play');
    await tester.pumpAndSettle();

    expect(find.byType(HowToPlayScreen), findsOneWidget);
    expect(find.text(l10n.rule1Text), findsOneWidget);
    expect(find.text(l10n.rule2Text), findsOneWidget);
    expect(find.text(l10n.rule3Text), findsOneWidget);
    expect(find.text(l10n.rule4Text), findsOneWidget);
    expect(find.text(l10n.glossaryBeside), findsOneWidget);
    expect(find.text(l10n.glossaryDirections), findsOneWidget);
    expect(find.text(l10n.glossaryRowCol), findsOneWidget);
  });
}
