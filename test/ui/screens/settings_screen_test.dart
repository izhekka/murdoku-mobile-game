import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/seeded_overrides.dart';

Future<(ProviderContainer, PrefsRepository)> pumpSettings(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MurdokuApp()),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/settings');
  await tester.pumpAndSettle();
  return (container, container.read(prefsRepositoryProvider));
}

AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

void main() {
  testWidgets('theme change persists across container reload', (tester) async {
    final (container, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    // Issue 109: the Theme section exists only on the classic skin.
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.themeDark));
    await tester.pumpAndSettle();

    // A fresh repository over the same prefs proves persistence.
    final prefs2 = await SharedPreferences.getInstance();
    expect(PrefsRepository(prefs2).loadSettings().themeMode, ThemeMode.dark);
    expect(repo.loadSettings().themeMode, ThemeMode.dark);
  });

  testWidgets('haptics toggle persists', (tester) async {
    final (_, repo) = await pumpSettings(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repo.loadSettings().haptics, isFalse);
  });

  testWidgets('reset clears saves/stats/daily but keeps settings', (
    tester,
  ) async {
    final (container, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);
    // Seed progress data.
    await repo.saveSettings(const Settings(themeMode: ThemeMode.dark));
    final notifier = container.read(gameControllerProvider.notifier);
    notifier.startNewCase(Difficulty.easy, seed: 3);
    // Advance the fake clock so the async persist completes.
    await tester.pump();
    await repo.saveStats(Stats()..totalCases = 9);
    await repo.saveDailyState(
      const DailyState(lastCompletedDate: '2026-11-19', streak: 2),
    );

    await tester.tap(find.text(l10n.resetProgress));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.resetProgress).last);
    await tester.pumpAndSettle();

    expect(repo.loadActiveGame(), isNull);
    expect(repo.loadStats().totalCases, 0);
    expect(repo.loadDailyState().streak, 0);
    // Settings are kept.
    expect(repo.loadSettings().themeMode, ThemeMode.dark);
    expect(find.text(l10n.progressReset), findsOneWidget);
  });

  testWidgets('skin picker offers the four localized skins (issue 23)', (
    tester,
  ) async {
    await pumpSettings(tester);
    final l10n = l10nOf(tester);
    for (final label in [
      l10n.skinClassic,
      l10n.skinCandy,
      l10n.skinSticker,
      l10n.skinComic,
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'segment $label');
    }
    // Issue 109: the classic-only caption is gone — the arb entries and the
    // generated getter were removed, so absence is enforced at compile time.
  });

  testWidgets('Skin section precedes Theme; Theme only on classic; themeMode '
      'persists while hidden (issue 109)', (tester) async {
    final (container, _) = await pumpSettings(tester);
    // Default skin is sticker (cartoon): the Theme section is hidden.
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);

    // Park dark, hide the section behind a cartoon skin, bring it back:
    // the persisted selection re-applies.
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.candy);
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);
    expect(
      container.read(settingsControllerProvider).themeMode,
      ThemeMode.dark,
    );
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<ThemeMode>>(
            find.byType(SegmentedButton<ThemeMode>),
          )
          .selected,
      {ThemeMode.dark},
    );

    // Skin first, Theme second, Language third.
    expect(
      tester.getRect(find.byType(SegmentedButton<SkinSetting>)).top,
      lessThan(tester.getRect(find.byType(SegmentedButton<ThemeMode>)).top),
    );
    expect(
      tester.getRect(find.byType(SegmentedButton<ThemeMode>)).top,
      lessThan(
        tester.getRect(find.byType(SegmentedButton<LanguageSetting>)).top,
      ),
    );
  });

  testWidgets('haptics label is titleMedium at the section-label offset with '
      'the switch trailing right (issue 109)', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622); // 402x874 @ dpr 3
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSettings(tester);
    final l10n = l10nOf(tester);

    final labelRect = tester.getRect(find.text(l10n.hapticsLabel));
    final switchRect = tester.getRect(find.byType(Switch));
    expect(
      labelRect.left,
      tester.getRect(find.text(l10n.skinLabel)).left,
      reason: 'same section-label left offset',
    );
    final label = tester.widget<Text>(find.text(l10n.hapticsLabel));
    expect(
      label.style,
      Theme.of(tester.element(find.text(l10n.hapticsLabel)))
          .textTheme
          .titleMedium,
      reason: 'the haptics label renders in titleMedium',
    );
    expect(switchRect.right, greaterThan(labelRect.right));
    expect(
      switchRect.right,
      closeTo(402 - 12, 6),
      reason: 'the switch presses against the trailing edge (ListView pad 12)',
    );
  });

  testWidgets('selecting Комикс updates the controller and persists '
      '(issue 23)', (tester) async {
    final (container, repo) = await pumpSettings(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.skinComic));
    await tester.pumpAndSettle();

    expect(container.read(settingsControllerProvider).skin, SkinSetting.comic);
    // A fresh repository over the same prefs proves persistence.
    final prefs2 = await SharedPreferences.getInstance();
    expect(PrefsRepository(prefs2).loadSettings().skin, SkinSetting.comic);
    expect(repo.loadSettings().skin, SkinSetting.comic);
  });

  testWidgets('skin segment labels stay single-line at the iPhone size '
      '(issue 76)', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (container, _) = await pumpSettings(tester);
    // Issue 109: the Theme section renders only on classic; select it so
    // all three segmented buttons are up for the height assertions below.
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);

    // Issue 76 run-1 evidence (per-PNG verdicts travel with the issue's run
    // report; screenshots are uncommitted build/ artifacts): at the 402x874
    // logical viewport
    // the selected segment's check icon squeezed long skin names into
    // mid-word wraps («Классик/а», «Стик/еры», «Stick/er», «Class/ic» on the
    // ru/en × light/dark settings shots). One text line is ~24px tall at the
    // fixed segment style; two lines ~40px.
    for (final label in [
      l10n.skinClassic,
      l10n.skinCandy,
      l10n.skinSticker,
      l10n.skinComic,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.height,
        lessThan(28),
        reason: 'skin label "$label" must stay on one line',
      );
    }
    // Rubric item 5 (issue 76): interactive controls stay >= 44 logical pt
    // tall; the segmented rows are 12px-label one-line controls.
    expect(
      tester.getRect(find.byType(SegmentedButton<SkinSetting>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getRect(find.byType(SegmentedButton<ThemeMode>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getRect(find.byType(SegmentedButton<LanguageSetting>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ru + dark settings segments stay single-line and overflow-free '
      'at the iPhone size (issue 76)', (tester) async {
    // The issue-76 criterion's example: Russian + dark, no overflow
    // exceptions at the iPhone 18 Pro logical size. Dark only exists on the
    // classic skin (cartoon skins are light-only, lib/app.dart).
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'murdoku.settings': jsonEncode(
        const Settings(
          skin: SkinSetting.classic,
          themeMode: ThemeMode.dark,
        ).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: seededOverrides(prefs));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();
    final home = tester.element(find.byType(Scaffold).first);
    GoRouter.of(home).go('/settings');
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    )!;

    for (final label in [
      l10n.skinClassic,
      l10n.skinCandy,
      l10n.skinSticker,
      l10n.skinComic,
      l10n.themeDark,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.height,
        lessThan(28),
        reason: 'label "$label" must stay on one line (ru + dark)',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
