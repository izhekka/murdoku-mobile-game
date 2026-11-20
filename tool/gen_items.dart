import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates flat top-down item sprites (128x128, transparent background) for
/// every ObjectKind into `assets/items/<kind>.png`, in the app's bright
/// game-piece palette (UX-4): saturated fills, thin dark outlines, shapes
/// filling ~80% of the canvas.
///
/// Run: `dart run tool/gen_items.dart`
void main() {
  const size = 128;
  final outline = img.ColorRgb8(45, 42, 52); // #2D2A34
  final wood = img.ColorRgb8(201, 138, 75); // #C98A4B
  final woodDark = img.ColorRgb8(169, 113, 61); // #A9713D
  final fabric = img.ColorRgb8(127, 168, 224); // #7FA8E0
  final fabricDark = img.ColorRgb8(98, 137, 204); // #6289CC
  final leaf = img.ColorRgb8(111, 191, 90); // #6FBF5A
  final leafDark = img.ColorRgb8(82, 160, 62); // #52A03E
  final metal = img.ColorRgb8(184, 190, 201); // #B8BEC9
  final metalDark = img.ColorRgb8(143, 150, 166); // #8F96A6
  final cream = img.ColorRgb8(226, 221, 205); // #E2DDCD
  final amber = img.ColorRgb8(240, 178, 74); // #F0B24A
  final red = img.ColorRgb8(224, 90, 90); // #E05A5A
  final blue = img.ColorRgb8(111, 174, 232); // #6FAEE8
  final pianoBody = img.ColorRgb8(96, 88, 116); // #605874

  /// Thin outline ring: image 4.x drawCircle is 1px, so layer radii.
void ring(img.Image image,
    {required int x,
    required int y,
    required int radius,
    required img.ColorRgb8 color,
    required int thickness}) {
  for (var t = 0; t < thickness; t++) {
    final r = radius - t;
    if (r < 1) break;
    img.drawCircle(image, x: x, y: y, radius: r, color: color);
  }
}

final sprites = <String, void Function(img.Image)>{
    'piano': (image) {
      img.fillRect(image, x1: 16, y1: 32, x2: 110, y2: 96, color: pianoBody);
      img.drawRect(image, x1: 16, y1: 32, x2: 110, y2: 96, color: outline, thickness: 4);
      img.fillRect(image, x1: 24, y1: 76, x2: 102, y2: 88, color: cream);
      for (var x = 28; x <= 100; x += 8) {
        img.fillRect(image, x1: x, y1: 76, x2: x + 2, y2: 88, color: outline);
      }
      img.fillRect(image, x1: 24, y1: 40, x2: 102, y2: 68, color: amber);
    },
    'victim': (image) {
      // Classic chalk body outline: head + spine + splayed arms/legs.
      final chalk = img.ColorRgba8(238, 233, 218, 235);
      void chalkLine(int x1, int y1, int x2, int y2) {
        img.drawLine(image, x1: x1, y1: y1, x2: x2, y2: y2,
            color: chalk, thickness: 6);
        // Slight offset pass for a hand-drawn chalk feel.
        img.drawLine(image, x1: x1 + 2, y1: y1 - 1, x2: x2 + 2, y2: y2 - 1,
            color: img.ColorRgba8(238, 233, 218, 120), thickness: 3);
      }
      // Head
      img.drawCircle(image, x: 34, y: 64, radius: 14, color: chalk);
      img.drawCircle(image, x: 34, y: 64, radius: 13, color: chalk);
      // Spine
      chalkLine(50, 64, 80, 64);
      // Arms
      chalkLine(58, 62, 68, 36);
      chalkLine(58, 66, 68, 92);
      // Legs
      chalkLine(80, 64, 112, 44);
      chalkLine(80, 64, 112, 84);
    },
  };

  Directory('assets/items').createSync(recursive: true);
  for (final entry in sprites.entries) {
    final image = img.Image(width: size, height: size);
    entry.value(image);
    File('assets/items/${entry.key}.png')
        .writeAsBytesSync(img.encodePng(image));
  }
  stdout.writeln('generated ${sprites.length} item sprites in assets/items/');
}
