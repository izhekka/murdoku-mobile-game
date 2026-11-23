import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/how_to_play_screen.dart';
import 'package:murdoku/ui/widgets/tutorial_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/seeded_overrides.dart';

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

/// Pumps the full app at the issue-31 worst case — 320x569 viewport with
/// textScale 2.0 — for the given skin, with the tutorial unseen so the
/// first-run dialog opens over home. Russian is the Settings default and
/// the widest reported case (Cyrillic labels at scale 2.0), so it is
/// pinned via [Settings].
Future<ProviderContainer> pumpTutorialWorstCase(
  WidgetTester tester, {
  SkinSetting skin = SkinSetting.sticker,
  LanguageSetting language = LanguageSetting.russian,
}) async {
  SharedPreferences.setMockInitialValues({
    'murdoku.settings': jsonEncode(
      Settings(language: language, skin: skin).toJson(),
    ),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(320, 569);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  SharedPreferences? withPrefs,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = withPrefs ?? await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
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

  testWidgets('tutorial is not shown again after the flag is set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'murdoku.tutorialSeen': true});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, withPrefs: prefs);

    expect(find.byType(TutorialOverlay), findsNothing);
  });

  testWidgets('how-to-play screen shows all four rules and the glossary', (
    tester,
  ) async {
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
    // The cartoon skins' app frame margin (issue 23) leaves the glossary
    // just past the fold on the 800x600 test viewport — the lazy ListView
    // builds it on scroll, so scroll to it before asserting.
    final glossaryDirections = find.text(l10n.glossaryDirections);
    await tester.dragUntilVisible(
      glossaryDirections,
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.glossaryBeside), findsOneWidget);
    expect(glossaryDirections, findsOneWidget);
    expect(find.text(l10n.glossaryRowCol), findsOneWidget);
  });

  testWidgets('tutorial footer fits 320x569 at textScale 2.0 in all skins '
      'and stays tappable (issue 31)', (tester) async {
    for (final skin in SkinSetting.values) {
      await pumpTutorialWorstCase(tester, skin: skin);
      final l10n = l10nOf(tester);

      // No RenderFlex overflow anywhere in the frames with the dialog up.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'tutorial must not overflow at 320x569 scale 2.0 '
            '(${skin.name} skin)',
      );

      // Footer controls are laid out inside the viewport.
      final overlay = find.byType(TutorialOverlay);
      expect(overlay, findsOneWidget, reason: '${skin.name} skin');
      final closeRect = tester.getRect(
        find.descendant(of: overlay, matching: find.byIcon(Icons.close)),
      );
      expect(
        closeRect.left,
        greaterThanOrEqualTo(0.0),
        reason: '${skin.name} skin',
      );
      expect(
        closeRect.right,
        lessThanOrEqualTo(320.0),
        reason: '${skin.name} skin',
      );
      expect(
        closeRect.bottom,
        lessThanOrEqualTo(569.0),
        reason: '${skin.name} skin',
      );
      final buttonFinder = find.ancestor(
        of: find.text(l10n.tutorialNext),
        matching: find.byType(FilledButton),
      );
      final buttonRect = tester.getRect(buttonFinder);
      expect(
        buttonRect.left,
        greaterThanOrEqualTo(0.0),
        reason: '${skin.name} skin',
      );
      expect(
        buttonRect.right,
        lessThanOrEqualTo(320.0),
        reason: '${skin.name} skin',
      );
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(569.0),
        reason: '${skin.name} skin',
      );

      // Next is tappable and advances to page 2 (rule 3 + X hint).
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.tutorialXHint),
        findsOneWidget,
        reason: 'Next tap advances the page (${skin.name} skin)',
      );

      // Walk to the last page; Done dismisses and closes the tutorial.
      await tester.tap(find.text(l10n.tutorialNext));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.tutorialDone));
      await tester.pumpAndSettle();
      expect(
        find.byType(TutorialOverlay),
        findsNothing,
        reason: 'Done dismisses the tutorial (${skin.name} skin)',
      );
    }
  });
}
