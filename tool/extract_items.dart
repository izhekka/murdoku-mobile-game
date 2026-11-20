import 'dart:io';

import 'package:image/image.dart' as img;

/// Extracts furniture sprites from Kenney's CC0 Roguelike/RPG pack sheet
/// (tool/assets_src/roguelikeSheet_transparent.png, 16 px tiles, 1 px spacing)
/// into `assets/items/<kind>.png` for the kinds backed by Kenney tiles.
///
/// Piano and victim keep their procedural sprites (tool/gen_items.dart).
/// Run: `dart run tool/extract_items.dart`
const kenneyTileByKind = {
  'table': (20, 6), // round table on a stand
  'chair': (21, 3), // side chair with cushion
  'flowers': (30, 9), // flowers in a pot
  'sofa': (25, 2), // armchair, front view
  'bookshelf': (29, 2), // shelf with towels and jars
  'lamp': (48, 3), // mushroom table lamp
  'plant': (21, 9), // round bush
  'chest': (32, 10), // wooden chest with drawers
  'clock': (26, 8), // pendulum wall clock
  'portrait': (29, 10), // framed landscape
  'fireplace': (36, 1), // dark arch fireplace
};

void main() {
  final sheet = img.decodePng(File(
      'tool/assets_src/roguelikeSheet_transparent.png')
      .readAsBytesSync())!;
  final upscaled = img.Image(width: 128, height: 128);
  Directory('assets/items').createSync(recursive: true);
  var count = 0;
  kenneyTileByKind.forEach((kind, tile) {
    final (c, r) = tile;
    final tileImg = img.copyCrop(sheet, x: c * 17, y: r * 17, width: 16, height: 16);
    // 2x nearest upscale -> 32px, then smooth 4x to 128px for crisp scaling
    final mid = img.copyResize(tileImg,
        width: 32, height: 32, interpolation: img.Interpolation.nearest);
    final big = img.copyResize(mid,
        width: 128, height: 128, interpolation: img.Interpolation.nearest);
    img.compositeImage(upscaled, big, dstX: 0, dstY: 0);
    File('assets/items/$kind.png')
        .writeAsBytesSync(img.encodePng(big));
    count++;
  });
  stdout.writeln('extracted $count Kenney sprites into assets/items/');
}
