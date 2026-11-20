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
    'table': (image) {
      img.fillRect(image, x1: 16, y1: 16, x2: 110, y2: 110, color: wood);
      img.drawRect(image, x1: 16, y1: 16, x2: 110, y2: 110, color: outline, thickness: 2);
      img.fillRect(image, x1: 28, y1: 28, x2: 98, y2: 98, color: woodDark);
    },
    'chair': (image) {
      img.fillRect(image, x1: 26, y1: 40, x2: 100, y2: 108, color: wood);
      img.drawRect(image, x1: 26, y1: 40, x2: 100, y2: 108, color: outline, thickness: 2);
      img.fillRect(image, x1: 26, y1: 16, x2: 100, y2: 38, color: woodDark);
      img.drawRect(image, x1: 26, y1: 16, x2: 100, y2: 38, color: outline, thickness: 2);
    },
    'flowers': (image) {
      img.fillCircle(image, x: 64, y: 82, radius: 32, color: red);
      ring(image, x: 64, y: 82, radius: 32, color: outline, thickness: 2);
      img.fillCircle(image, x: 48, y: 50, radius: 16, color: leaf);
      img.fillCircle(image, x: 80, y: 50, radius: 16, color: leafDark);
      img.fillCircle(image, x: 64, y: 32, radius: 16, color: amber);
      ring(image, x: 64, y: 32, radius: 16, color: outline, thickness: 2);
    },
    'sofa': (image) {
      img.fillRect(image, x1: 12, y1: 36, x2: 114, y2: 104, color: fabric);
      img.drawRect(image, x1: 12, y1: 36, x2: 114, y2: 104, color: outline, thickness: 2);
      img.fillRect(image, x1: 16, y1: 16, x2: 110, y2: 40, color: fabricDark);
      img.drawRect(image, x1: 16, y1: 16, x2: 110, y2: 40, color: outline, thickness: 2);
      img.fillRect(image, x1: 60, y1: 40, x2: 66, y2: 100, color: fabricDark);
    },
    'bookshelf': (image) {
      img.fillRect(image, x1: 20, y1: 12, x2: 106, y2: 114, color: woodDark);
      img.drawRect(image, x1: 20, y1: 12, x2: 106, y2: 114, color: outline, thickness: 2);
      for (final y in [18, 30, 42]) {
        img.fillRect(image, x1: 28, y1: y - 5, x2: 98, y2: y + 1, color: wood);
        img.fillRect(image, x1: 32, y1: y - 4, x2: 44, y2: y, color: red);
        img.fillRect(image, x1: 50, y1: y - 4, x2: 62, y2: y, color: blue);
        img.fillRect(image, x1: 68, y1: y - 4, x2: 80, y2: y, color: amber);
        img.fillRect(image, x1: 86, y1: y - 4, x2: 94, y2: y, color: cream);
      }
    },
    'lamp': (image) {
      img.fillRect(image, x1: 54, y1: 58, x2: 72, y2: 104, color: metalDark);
      img.fillRect(image, x1: 40, y1: 98, x2: 86, y2: 112, color: metal);
      img.fillCircle(image, x: 64, y: 42, radius: 34, color: amber);
      ring(image, x: 64, y: 42, radius: 34, color: outline, thickness: 2);
      img.fillCircle(image, x: 64, y: 42, radius: 14, color: cream);
    },
    'piano': (image) {
      img.fillRect(image, x1: 16, y1: 32, x2: 110, y2: 96, color: pianoBody);
      img.drawRect(image, x1: 16, y1: 32, x2: 110, y2: 96, color: outline, thickness: 4);
      img.fillRect(image, x1: 24, y1: 76, x2: 102, y2: 88, color: cream);
      for (var x = 28; x <= 100; x += 8) {
        img.fillRect(image, x1: x, y1: 76, x2: x + 2, y2: 88, color: outline);
      }
      img.fillRect(image, x1: 24, y1: 40, x2: 102, y2: 68, color: amber);
    },
    'plant': (image) {
      img.fillRect(image, x1: 40, y1: 78, x2: 86, y2: 114, color: red);
      img.drawRect(image, x1: 40, y1: 78, x2: 86, y2: 114, color: outline, thickness: 2);
      img.fillCircle(image, x: 64, y: 46, radius: 32, color: leaf);
      ring(image, x: 64, y: 46, radius: 32, color: outline, thickness: 2);
      img.fillCircle(image, x: 46, y: 34, radius: 18, color: leafDark);
      img.fillCircle(image, x: 82, y: 34, radius: 18, color: leafDark);
    },
    'armor': (image) {
      img.fillRect(image, x1: 34, y1: 12, x2: 92, y2: 106, color: metal);
      img.drawRect(image, x1: 34, y1: 12, x2: 92, y2: 106, color: outline, thickness: 2);
      img.fillRect(image, x1: 46, y1: 38, x2: 80, y2: 88, color: metalDark);
      img.fillRect(image, x1: 46, y1: 66, x2: 80, y2: 76, color: amber);
    },
    'chest': (image) {
      img.fillRect(image, x1: 20, y1: 40, x2: 106, y2: 108, color: wood);
      img.drawRect(image, x1: 20, y1: 40, x2: 106, y2: 108, color: outline, thickness: 2);
      img.fillRect(image, x1: 20, y1: 40, x2: 106, y2: 60, color: woodDark);
      img.fillRect(image, x1: 58, y1: 56, x2: 68, y2: 76, color: amber);
      img.drawRect(image, x1: 58, y1: 56, x2: 68, y2: 76, color: outline, thickness: 2);
    },
    'clock': (image) {
      img.fillCircle(image, x: 64, y: 64, radius: 44, color: cream);
      ring(image, x: 64, y: 64, radius: 44, color: outline, thickness: 2);
      ring(image, x: 64, y: 64, radius: 32, color: outline, thickness: 2);
      img.drawLine(image, x1: 64, y1: 64, x2: 64, y2: 40, color: outline, thickness: 4);
      img.drawLine(image, x1: 64, y1: 64, x2: 84, y2: 72, color: red, thickness: 4);
    },
    'globe': (image) {
      img.fillCircle(image, x: 64, y: 56, radius: 40, color: blue);
      ring(image, x: 64, y: 56, radius: 40, color: outline, thickness: 2);
      img.fillCircle(image, x: 52, y: 40, radius: 14, color: leaf);
      img.fillCircle(image, x: 76, y: 64, radius: 12, color: leaf);
      img.fillRect(image, x1: 58, y1: 92, x2: 70, y2: 108, color: metalDark);
      img.fillRect(image, x1: 44, y1: 104, x2: 84, y2: 116, color: metal);
    },
    'portrait': (image) {
      img.fillRect(image, x1: 28, y1: 20, x2: 98, y2: 108, color: amber);
      img.drawRect(image, x1: 28, y1: 20, x2: 98, y2: 108, color: outline, thickness: 2);
      img.fillRect(image, x1: 40, y1: 32, x2: 86, y2: 96, color: cream);
      img.fillCircle(image, x: 64, y: 56, radius: 14, color: metalDark);
      img.fillRect(image, x1: 48, y1: 72, x2: 80, y2: 96, color: fabric);
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
    'fireplace': (image) {
      img.fillRect(image, x1: 16, y1: 24, x2: 110, y2: 112, color: metalDark);
      img.drawRect(image, x1: 16, y1: 24, x2: 110, y2: 112, color: outline, thickness: 2);
      img.fillRect(image, x1: 36, y1: 48, x2: 90, y2: 108, color: outline);
      img.fillCircle(image, x: 52, y: 88, radius: 16, color: red);
      img.fillCircle(image, x: 76, y: 92, radius: 14, color: amber);
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
