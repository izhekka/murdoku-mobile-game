import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart' show AppTheme;
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/state/settings_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/screens/settings_screen.dart';
import 'package:murdoku/ui/screens/stats_screen.dart';
import 'package:murdoku/ui/widgets/skin_card.dart'
    as skin_widgets
    show SkinCard;
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

  testWidgets('candy sky page: sky at the corners and card gaps, white '
      'cards read, no white text on the page (issue 97)', (tester) async {
    tester.view.physicalSize = phoneViewport; // 390x844 @ dpr 3
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'murdoku.settings': jsonEncode(
        const Settings(skin: SkinSetting.candy).toJson(),
      ),
      'murdoku.tutorialSeen': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: seededOverrides(prefs),
        child: RepaintBoundary(
          key: const ValueKey('sky-page-capture'),
          child: const MurdokuApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tokens = SkinScope.maybeOf(tester.element(find.byType(HomeScreen)))!;
    final sky = tokens.appBackground.toARGB32();
    final cardWhite = tokens.card.background.toARGB32();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));

    // toImage submits to the real IO task queue, which the fake-async test
    // zone forbids: run the capture in runAsync (same pattern as the
    // issue-86 full-bleed test above).
    Uint8List bytes = Uint8List(0);
    var width = 0;
    var height = 0;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('sky-page-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 3.0);
      width = image.width;
      height = image.height;
      bytes = Uint8List.fromList(
        (await image.toByteData())!.buffer.asUint8List(),
      );
      image.dispose();
    });

    for (final (x, y, name) in [
      (0, 0, 'top-left'),
      (width - 1, 0, 'top-right'),
      (0, height - 1, 'bottom-left'),
      (width - 1, height - 1, 'bottom-right'),
    ]) {
      expect(
        _pixelAt(bytes, width, x, y),
        sky,
        reason: '$name corner of the candy page must be the sky',
      );
    }

    // SkinCard wraps its token container in 4-logical padding: the sample
    // two logical px in from the outer left edge lands in the page gap
    // band between cards, the center lands inside the white container.
    Offset device(Offset logical) => Offset(
      (logical.dx * 3).round().toDouble(),
      (logical.dy * 3).round().toDouble(),
    );
    final card = tester.getRect(find.byType(skin_widgets.SkinCard).first);
    // SkinCard wraps its token container in 4-logical padding: sample the
    // container's interior by majority — the white cloud surface must
    // dominate it (title/subtitle glyphs are the ink minorities), and the
    // page gap two logical px in from the outer left edge must be sky.
    final containerRect = card.deflate(4);
    var whiteCount = 0;
    var sampleCount = 0;
    for (
      var y = (containerRect.top * 3).round();
      y < (containerRect.bottom * 3).round();
      y += 3
    ) {
      for (
        var x = (containerRect.left * 3).round();
        x < (containerRect.right * 3).round();
        x += 3
      ) {
        sampleCount++;
        if (_pixelAt(bytes, width, x, y) == cardWhite) whiteCount++;
      }
    }
    expect(
      whiteCount,
      greaterThanOrEqualTo(sampleCount * 2 ~/ 3),
      reason: 'the card interior is dominated by the white cloud surface',
    );
    final pageGap = device(Offset(card.left + 2, card.center.dy));
    expect(
      _pixelAt(bytes, width, pageGap.dx.round(), pageGap.dy.round()),
      sky,
      reason: 'the page gap beside the card is the sky',
    );

    // No white text on any page: walk every Text on home, settings, stats
    // and game; white answers are legal ONLY inside the danger accuse pill
    // (game_screen.dart's _foreground). White on the sky measures 1.80:1
    // (an AA failure — skins_contrast_test.dart); if a case is ever found
    // here it is flagged to the issue, not auto-fixed here.
    bool whiteTextOutsideAccuse() {
      final whiteTexts = find.byType(Text).evaluate().where((el) {
        final text = el.widget as Text;
        final resolved =
            text.style?.color ?? DefaultTextStyle.of(el).style.color;
        return resolved?.toARGB32() == 0xFFFFFFFF;
      }).toList();
      for (final el in whiteTexts) {
        final inAccuse = find
            .ancestor(
              of: find.byElementPredicate((e) => identical(e, el)),
              matching: find.byKey(const Key('tool_accuse')),
            )
            .evaluate()
            .isNotEmpty;
        if (!inAccuse) return true;
      }
      return false;
    }

    expect(
      whiteTextOutsideAccuse(),
      isFalse,
      reason: 'home: no white page text',
    );
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(
      whiteTextOutsideAccuse(),
      isFalse,
      reason: 'settings: no white page text',
    );
    router.go('/stats');
    await tester.pumpAndSettle();
    expect(
      whiteTextOutsideAccuse(),
      isFalse,
      reason: 'stats: no white page text',
    );
    // Route-coverage pin (absorbed review P3, issue 97): the tutorial-like
    // how-to-play page walks too — it renders text on the sky page directly.
    router.go('/how-to-play');
    await tester.pumpAndSettle();
    expect(
      whiteTextOutsideAccuse(),
      isFalse,
      reason: 'how-to-play: no white page text',
    );
    container
        .read(gameControllerProvider.notifier)
        .startNewCase(Difficulty.easy, seed: 3);
    router.go('/game');
    await tester.pumpAndSettle();
    expect(
      whiteTextOutsideAccuse(),
      isFalse,
      reason: 'game: no white page text',
    );
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
