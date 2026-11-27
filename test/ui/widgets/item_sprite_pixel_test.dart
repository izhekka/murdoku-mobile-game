import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/storage/prefs_repository.dart' show SkinSetting;
import 'package:murdoku/ui/widgets/item_sprite.dart';

/// Issue 100 render-path proof: ItemSprite recolors the game-icons piano
/// sprite to the active skin's opaque `spriteInk` at render (alpha
/// preserved — antialiased edges ride the art's own alpha), on every skin
/// and both classic brightnesses, over the weakest room tint that skin
/// paints under a sprite. Raw-pixel assertions (no asset changes: the
/// filter mixes at render; the original art family must vanish entirely).
///
/// The measured palette fact the bars pin (test/core/skins_contrast_test.dart):
/// candy ink #35406E vs the red tint #D45D48 misses the 3:1 bar, so candy
/// renders its deepened spriteInk #1F2440 — this test asserts the pixels.
const _captureKey = ValueKey('sprite-capture');

/// piano.png's opaque art family (measured from the asset: core alpha=255
/// pixels are ≈ #8B7BC4 / #8878C0 lavender-gray, only ~4% of pixels carry
/// partial alpha). Post-recolor none may survive at render.
const int _originalArt = 0xFF8B7BC4;

/// Pixels in [bytes] (premultiplied RGBA) whose RGB matches the sRGB
/// triplet of [target] within [tol] per channel.
int countMatches(Uint8List bytes, int target, {int tol = 0}) {
  final tr = (target >> 16) & 0xFF;
  final tg = (target >> 8) & 0xFF;
  final tb = target & 0xFF;
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    if ((bytes[i] - tr).abs() <= tol &&
        (bytes[i + 1] - tg).abs() <= tol &&
        (bytes[i + 2] - tb).abs() <= tol) {
      count++;
    }
  }
  return count;
}

/// Pixels whose RGB differs from [target] beyond [tol] on ANY channel.
int countNotMatches(Uint8List bytes, int target, {int tol = 6}) {
  final tr = (target >> 16) & 0xFF;
  final tg = (target >> 8) & 0xFF;
  final tb = target & 0xFF;
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    if ((bytes[i] - tr).abs() > tol ||
        (bytes[i + 1] - tg).abs() > tol ||
        (bytes[i + 2] - tb).abs() > tol) {
      count++;
    }
  }
  return count;
}

/// One render configuration: the SkinScope tokens, the ThemeData the
/// widget tree resolves its scheme from, the expected sprite ink, and the
/// board-like backdrop the sprite paints over.
typedef _Setup = (SkinTokens, ThemeData, Color, Color);

final ThemeData _candyTheme = AppTheme.forSkin(
  SkinSetting.candy,
  Brightness.light,
);
final ThemeData _stickerTheme = AppTheme.forSkin(
  SkinSetting.sticker,
  Brightness.light,
);
final ThemeData _comicTheme = AppTheme.forSkin(
  SkinSetting.comic,
  Brightness.light,
);
final SkinTokens _classicLight = skinTokensFor(
  SkinSetting.classic,
  AppTheme.light.colorScheme,
);
final SkinTokens _classicDark = skinTokensFor(
  SkinSetting.classic,
  AppTheme.dark.colorScheme,
);

List<(_Setup, String)> _configurations() {
  // The classic plain-blend backdrops pin the measured weakest tint per
  // mode (tint@55% alpha over the scheme surface, from the pinned bars):
  // light — coral tints[3] (plain pair 7.24:1 with the near-black ink),
  // dark — lime tints[4] (3.93:1 with the light ink); the bars iterate
  // every tint per mode.
  final classic = <(_Setup, String)>[
    (
      (
        _classicLight,
        AppTheme.light,
        _classicLight.spriteInk,
        Color.alphaBlend(
          classicRoomTints[3].withValues(alpha: 0.55),
          AppTheme.light.colorScheme.surface,
        ),
      ),
      'classic light on the coral tint blend #D63E2E',
    ),
    (
      (
        _classicDark,
        AppTheme.dark,
        _classicDark.spriteInk,
        Color.alphaBlend(
          classicRoomTints[4].withValues(alpha: 0.55),
          AppTheme.dark.colorScheme.surface,
        ),
      ),
      'classic dark on the lime tint blend #8FCB3A',
    ),
  ];
  return [
    (
      (
        candyTokens,
        _candyTheme,
        candyTokens.spriteInk,
        candyTokens.roomTints[7],
      ),
      'candy on the red tint #D45D48',
    ),
    (
      (
        stickerTokens,
        _stickerTheme,
        stickerTokens.spriteInk,
        stickerTokens.roomTints[0],
      ),
      'sticker on the red tint #FF6B6B',
    ),
    (
      (
        comicTokens,
        _comicTheme,
        comicTokens.spriteInk,
        comicTokens.roomTints[3],
      ),
      'comic on the violet tint #9B5DE5',
    ),
    ...classic,
  ];
}

void main() {
  for (final ((tokens, theme, ink, backdrop), label) in _configurations()) {
    testWidgets('ItemSprite recolors to $label (issue 100)', (tester) async {
      tester.view.physicalSize = const Size(300, 300);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            theme: theme,
            builder: (context, child) =>
                SkinScope(tokens: tokens, child: child!),
            home: Scaffold(
              body: ColoredBox(
                color: backdrop,
                child: Center(
                  child: ItemSprite(kind: ObjectKind.piano, size: 100),
                ),
              ),
            ),
          ),
        ),
      );
      // The asset decodes off the fake-async test zone: give the real IO
      // side a beat, then settle so the decoded image repaints before the
      // capture (the first configuration otherwise rasterizes the pre-decode
      // frame).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      Uint8List bytes = Uint8List(0);
      var pixels = 0;
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_captureKey),
        );
        final image = await boundary.toImage(pixelRatio: 2.0);
        pixels = image.width * image.height;
        bytes = Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List(),
        );
        image.dispose();
      });

      // 1. The art core recolors to exactly the skin's sprite ink (opaque
      //    silhouette at alpha 255).
      final strictInk = countMatches(bytes, ink.toARGB32());
      expect(
        strictInk,
        greaterThan(0),
        reason:
            '$label: no pixel of the sprite recolored to '
            'spriteInk ${ink.toARGB32().toRadixString(16)} — the ink filter '
            'is not applied at render',
      );

      // 2. Zero pixels of the original lavender-gray art family: the paint
      //    is a recolor, not a passthrough, and the asset is untouched.
      final originalArt = countMatches(bytes, _originalArt, tol: 6);
      expect(
        originalArt,
        0,
        reason:
            '$label: $originalArt pixels still render the original '
            'game-icons art color — the recolor did not happen',
      );

      // 3. Alpha preserved: antialiased/resampled edge pixels ride the
      //    art's own alpha — neither flat backdrop nor flat ink.
      final backdropExact = countMatches(bytes, backdrop.toARGB32());
      final blend = pixels - backdropExact - strictInk;
      expect(
        blend,
        greaterThan(0),
        reason:
            '$label: no alpha-blend edge pixels found — the sprite '
            'renders as flat ink without its art alpha',
      );

      // 4. The silhouette actually rendered at scale (guards the
      //    errorBuilder fallback icon and a blank/missing asset).
      final visible = countNotMatches(bytes, backdrop.toARGB32());
      expect(
        visible,
        greaterThan(2000),
        reason:
            '$label: only $visible non-backdrop pixels — the sprite '
            'was not rendered',
      );
    });
  }
}
