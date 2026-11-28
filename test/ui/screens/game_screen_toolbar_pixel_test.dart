// Heavy raster battery (issue 105): skipped by intermediate runs
// (`flutter test --exclude-tags=raster`); the final `make quality` gate
// still executes it.
@Tags(['raster'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/state/game_controller.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/seeded_overrides.dart';

/// Issue 87 render-path proof: the toolbar fix is a painting change (the
/// glyphs' rasterized pixels must show the skin's ink on every pastel pill
/// and white only on the danger pill), so this test rasterizes the game
/// screen headless and asserts on the raw pixels inside two pills — the
/// pixel-level claims prose and widget-level assertions cannot make.
///
/// Interior sampling insets 24 device pixels from each pill edge to stay
/// clear of the 14-logical-radius corners and the active-tool outline, so
/// glyph-count and fill-count assertions see only opaque pill pixels.
late ProviderContainer container;

Future<void> pumpCandyGame(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'murdoku.settings': jsonEncode(
      const Settings(skin: SkinSetting.candy).toJson(),
    ),
    'murdoku.tutorialSeen': true,
  });
  final prefs = await SharedPreferences.getInstance();
  container = ProviderContainer(overrides: seededOverrides(prefs));
  addTearDown(container.dispose);
  // dpr 3.0 rasterizes the pills for the pixel assertions; the logical
  // viewport must stay inside the app's supported range (≥320 wide — issue
  // 88 wraps the toolbar to two rows below 440 and the taller toolbar needs
  // panel room): 1206×2622 physical = 402×874 logical at 3x, the issue-88
  // acceptance viewport (iPhone 18 Pro class).
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  container
      .read(gameControllerProvider.notifier)
      .startNewCase(Difficulty.easy, seed: 3);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: const ValueKey('toolbar-capture'),
        child: const MurdokuApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  GoRouter.of(context).go('/game');
  await tester.pumpAndSettle();
}

/// Pixels inside the physical [rect] whose RGB matches [target] within
/// [tol] per channel.
int _countMatches(
  Uint8List bytes,
  int width,
  Rect rect,
  int target, {
  int tol = 0,
}) {
  final tr = (target >> 16) & 0xFF;
  final tg = (target >> 8) & 0xFF;
  final tb = target & 0xFF;
  var count = 0;
  for (var y = rect.top.round(); y < rect.bottom.round(); y++) {
    for (var x = rect.left.round(); x < rect.right.round(); x++) {
      final i = (y * width + x) * 4;
      if ((bytes[i] - tr).abs() <= tol &&
          (bytes[i + 1] - tg).abs() <= tol &&
          (bytes[i + 2] - tb).abs() <= tol) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  testWidgets('candy toolbar pixels: ink glyphs on the place pill, white '
      'on the danger pill (issue 87)', (tester) async {
    await pumpCandyGame(tester);

    // toImage submits to the real IO task queue, which the fake-async test
    // zone forbids: run the capture in runAsync (like the golden matchers'
    // captureImage does — same pattern as app_shell_test).
    Uint8List bytes = Uint8List(0);
    var width = 0;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('toolbar-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 3.0);
      width = image.width;
      bytes = Uint8List.fromList(
        (await image.toByteData())!.buffer.asUint8List(),
      );
      image.dispose();
    });

    // Physical (3x) pill interiors, inset 24 device px from the edges.
    Rect interiorOf(Key key) {
      final logical = tester.getRect(find.byKey(key));
      return Rect.fromLTRB(
        logical.left * 3,
        logical.top * 3,
        logical.right * 3,
        logical.bottom * 3,
      ).deflate(24);
    }

    const ink = 0xFF35406E; // candy ink glyphs
    const placeFill = 0xFFFF8FB3; // retuned pastel pill
    const dangerFill = 0xFFC2410C; // shared retuned danger accent
    const white = 0xFFFFFFFF;

    final place = interiorOf(const Key('tool_place'));
    final accuse = interiorOf(const Key('tool_accuse'));

    expect(
      _countMatches(bytes, width, place, placeFill),
      greaterThanOrEqualTo(500),
      reason: 'the retuned place pill paints its pastel fill (issue 87)',
    );
    expect(
      _countMatches(bytes, width, place, ink, tol: 8),
      greaterThanOrEqualTo(24),
      reason:
          'the place pill glyph pixels are the skin ink, not white '
          '(issue 87)',
    );
    expect(
      _countMatches(bytes, width, place, white),
      0,
      reason: 'no white glyph pixels may appear on a pastel pill (issue 87)',
    );

    expect(
      _countMatches(bytes, width, accuse, dangerFill),
      greaterThanOrEqualTo(500),
      reason: 'the accuse pill paints the retuned danger fill (issue 87)',
    );
    expect(
      _countMatches(bytes, width, accuse, white),
      greaterThanOrEqualTo(24),
      reason: 'the danger pill glyph pixels stay white (issue 87)',
    );
  });
}
