import 'dart:typed_data' show Uint8List;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart' show AppTheme;
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:murdoku/ui/screens/stats_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/seeded_overrides.dart';

Future<SharedPreferences> mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('home renders the app title from l10n', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(context)!;
    expect(find.text(l10n.appTitle), findsOneWidget);
  });

  testWidgets('dark mode toggle changes material app brightness for the '
      'classic skin (issue 23)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // The theme swap rebuilds the tree; read the live element afterwards.
    final rebuilt = tester.element(find.byType(HomeScreen));
    expect(Theme.of(rebuilt).brightness, Brightness.dark);
  });

  testWidgets('cartoon skins are light-only: themeMode is ignored (issue 23)', (
    tester,
  ) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    // Default skin is sticker; asking for dark must not darken it.
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    final rebuilt = tester.element(find.byType(HomeScreen));
    expect(Theme.of(rebuilt).brightness, Brightness.light);
  });

  testWidgets('the app shell exposes the active skin tokens in context '
      '(issue 23)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    SkinTokens tokensOfHome() =>
        SkinScope.maybeOf(tester.element(find.byType(HomeScreen)))!;
    expect(tokensOfHome().skin, SkinSetting.sticker);

    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.comic);
    await tester.pumpAndSettle();

    expect(tokensOfHome().skin, SkinSetting.comic);
    expect(tokensOfHome(), comicTokens);
  });

  testWidgets('MurdokuApp holds the shared delegate const (identity check, '
      'issue 24)', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.localizationsDelegates, same(murdokuLocalizationsDelegates));
  });

  testWidgets('navigating to /stats renders the stats placeholder via l10n', (
    tester,
  ) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    final l10n = AppLocalizations.of(context)!;
    GoRouter.of(context).go('/stats');
    await tester.pumpAndSettle();

    expect(find.byType(StatsScreen), findsOneWidget);
    expect(find.text(l10n.statsTitle), findsOneWidget);
  });

  testWidgets('settings changes keep the navigation stack (issue 76)', (
    tester,
  ) async {
    // Every MurdokuApp rebuild must reuse the same GoRouter: a fresh router
    // on each rebuild resets navigation to '/', kicking the player out of
    // Settings on every theme/skin/language switch (found by the iOS
    // pixel-fidelity capture driver).
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    GoRouter.of(context).go('/settings');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    container
        .read(settingsControllerProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    container
        .read(settingsControllerProvider.notifier)
        .setSkin(SkinSetting.classic);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  const phoneViewport = Size(1170, 2532); // 390x844 @ dpr 3
  const phoneLogical = Size(390, 844);

  testWidgets('every skin renders the Scaffold full-bleed to the viewport '
      '(issue 86)', (tester) async {
    // Phone viewport per the issue; the frame previously kept a 12 px
    // (+ border/ring) inset, so this pins the removal itself.
    tester.view.physicalSize = phoneViewport;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final skin in SkinSetting.values) {
      // Tutorial seen: without this the first-launch overlay's black54
      // barrier covers the viewport and the corner pixels sample the scrim.
      SharedPreferences.setMockInitialValues({'murdoku.tutorialSeen': true});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: seededOverrides(prefs),
          child: RepaintBoundary(
            key: const ValueKey('app-shell-capture'),
            child: const MurdokuApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(settingsControllerProvider.notifier)
          .setSkin(skin);
      await tester.pumpAndSettle();

      // Nothing insets the app anymore: the Scaffold owns the whole window.
      expect(
        tester.getRect(find.byType(Scaffold)),
        Offset.zero & phoneLogical,
        reason: '$skin Scaffold must fill the viewport edge-to-edge',
      );

      // Pixel proof (render-path diff): rasterize the shell headless and
      // assert the four screen corners show the skin's paper background —
      // the removed frame's page color was most visible at the corners.
      // toImage submits to the real IO task queue, which the fake-async
      // test zone forbids: run the capture in runAsync (like the golden
      // matchers' captureImage does).
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('app-shell-capture')),
      );
      Uint8List bytes = Uint8List(0);
      int width = 0;
      int height = 0;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        width = image.width;
        height = image.height;
        bytes = Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List(),
        );
        image.dispose();
      });
      expect(
        _pixelAt(bytes, width, 0, 0),
        _paperOf(skin),
        reason: '$skin top-left corner pixel',
      );
      expect(
        _pixelAt(bytes, width, width - 1, 0),
        _paperOf(skin),
        reason: '$skin top-right corner pixel',
      );
      expect(
        _pixelAt(bytes, width, 0, height - 1),
        _paperOf(skin),
        reason: '$skin bottom-left corner pixel',
      );
      expect(
        _pixelAt(bytes, width, width - 1, height - 1),
        _paperOf(skin),
        reason: '$skin bottom-right corner pixel',
      );
    }
  });
}

/// The skin's paper background (what must reach every screen edge), as a
/// raw ARGB32 value. Cartoon skins return their token constant; classic
/// derives from the same theme scheme the Scaffold paints.
int _paperOf(SkinSetting skin) =>
    skinTokensFor(skin, AppTheme.light.colorScheme).appBackground.toARGB32();

/// The ARGB32 value of device pixel (x, y) in a rawRgba [bytes] raster.
int _pixelAt(Uint8List bytes, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (bytes[i + 3] << 24) |
      (bytes[i] << 16) |
      (bytes[i + 1] << 8) |
      bytes[i + 2];
}
