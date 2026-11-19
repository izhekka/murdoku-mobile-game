import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates flat top-down item sprites (64x64, transparent background) for
/// every ObjectKind into `assets/items/<kind>.png`, in the app's noir palette.
///
/// Run: `dart run tool/gen_items.dart`
void main() {
  const size = 64;
  final outline = img.ColorRgb8(45, 42, 52); // #2D2A34
  final wood = img.ColorRgb8(139, 94, 60); // #8B5E3C
  final woodDark = img.ColorRgb8(107, 66, 38); // #6B4226
  final fabric = img.ColorRgb8(122, 143, 191); // #7A8FBF
  final fabricDark = img.ColorRgb8(94, 113, 160); // #5E71A0
  final leaf = img.ColorRgb8(96, 140, 86); // #608C56
  final leafDark = img.ColorRgb8(72, 112, 64); // #487040
  final metal = img.ColorRgb8(142, 146, 158); // #8E929E
  final metalDark = img.ColorRgb8(108, 112, 124); // #6C707C
  final cream = img.ColorRgb8(226, 221, 205); // #E2DDCD
  final amber = img.ColorRgb8(200, 155, 60); // #C89B3C
  final red = img.ColorRgb8(178, 58, 58); // #B23A3A
  final blue = img.ColorRgb8(94, 148, 193); // #5E94C1

  /// Thick circle outline: image 4.x drawCircle is 1px, so layer radii.
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
      img.fillRect(image, x1: 8, y1: 8, x2: 55, y2: 55, color: wood);
      img.drawRect(image, x1: 8, y1: 8, x2: 55, y2: 55, color: outline, thickness: 3);
      img.fillRect(image, x1: 14, y1: 14, x2: 49, y2: 49, color: woodDark);
    },
    'chair': (image) {
      img.fillRect(image, x1: 18, y1: 22, x2: 45, y2: 50, color: wood);
      img.drawRect(image, x1: 18, y1: 22, x2: 45, y2: 50, color: outline, thickness: 3);
      img.fillRect(image, x1: 18, y1: 10, x2: 45, y2: 18, color: woodDark);
      img.drawRect(image, x1: 18, y1: 10, x2: 45, y2: 18, color: outline, thickness: 3);
    },
    'flowers': (image) {
      img.fillCircle(image, x: 32, y: 40, radius: 14, color: red);
      ring(image, x: 32, y: 40, radius: 14, color: outline, thickness: 3);
      img.fillCircle(image, x: 26, y: 26, radius: 7, color: leaf);
      img.fillCircle(image, x: 38, y: 26, radius: 7, color: leafDark);
      img.fillCircle(image, x: 32, y: 18, radius: 7, color: amber);
      ring(image, x: 32, y: 18, radius: 7, color: outline, thickness: 2);
    },
    'sofa': (image) {
      img.fillRect(image, x1: 6, y1: 18, x2: 57, y2: 52, color: fabric);
      img.drawRect(image, x1: 6, y1: 18, x2: 57, y2: 52, color: outline, thickness: 3);
      img.fillRect(image, x1: 8, y1: 8, x2: 55, y2: 20, color: fabricDark);
      img.drawRect(image, x1: 8, y1: 8, x2: 55, y2: 20, color: outline, thickness: 3);
      img.fillRect(image, x1: 30, y1: 20, x2: 33, y2: 50, color: fabricDark);
    },
    'bookshelf': (image) {
      img.fillRect(image, x1: 10, y1: 6, x2: 53, y2: 57, color: woodDark);
      img.drawRect(image, x1: 10, y1: 6, x2: 53, y2: 57, color: outline, thickness: 3);
      for (final y in [18, 30, 42]) {
        img.fillRect(image, x1: 14, y1: y - 5, x2: 49, y2: y + 1, color: wood);
        img.fillRect(image, x1: 16, y1: y - 4, x2: 22, y2: y, color: red);
        img.fillRect(image, x1: 25, y1: y - 4, x2: 31, y2: y, color: blue);
        img.fillRect(image, x1: 34, y1: y - 4, x2: 40, y2: y, color: amber);
        img.fillRect(image, x1: 43, y1: y - 4, x2: 47, y2: y, color: cream);
      }
    },
    'lamp': (image) {
      img.fillRect(image, x1: 28, y1: 30, x2: 35, y2: 52, color: metalDark);
      img.fillRect(image, x1: 22, y1: 50, x2: 41, y2: 56, color: metal);
      img.fillCircle(image, x: 32, y: 22, radius: 15, color: amber);
      ring(image, x: 32, y: 22, radius: 15, color: outline, thickness: 3);
      img.fillCircle(image, x: 32, y: 22, radius: 6, color: cream);
    },
    'piano': (image) {
      img.fillRect(image, x1: 6, y1: 14, x2: 57, y2: 50, color: img.ColorRgb8(34, 32, 42));
      img.drawRect(image, x1: 6, y1: 14, x2: 57, y2: 50, color: outline, thickness: 3);
      img.fillRect(image, x1: 10, y1: 40, x2: 53, y2: 46, color: cream);
      for (var x = 14; x <= 50; x += 6) {
        img.fillRect(image, x1: x, y1: 40, x2: x + 1, y2: 46, color: outline);
      }
    },
    'plant': (image) {
      img.fillRect(image, x1: 22, y1: 40, x2: 41, y2: 56, color: red);
      img.drawRect(image, x1: 22, y1: 40, x2: 41, y2: 56, color: outline, thickness: 3);
      img.fillCircle(image, x: 32, y: 24, radius: 14, color: leaf);
      ring(image, x: 32, y: 24, radius: 14, color: outline, thickness: 3);
      img.fillCircle(image, x: 24, y: 18, radius: 8, color: leafDark);
      img.fillCircle(image, x: 40, y: 18, radius: 8, color: leafDark);
    },
    'armor': (image) {
      img.fillRect(image, x1: 20, y1: 8, x2: 43, y2: 50, color: metal);
      img.drawRect(image, x1: 20, y1: 8, x2: 43, y2: 50, color: outline, thickness: 3);
      img.fillRect(image, x1: 26, y1: 20, x2: 37, y2: 44, color: metalDark);
      img.fillRect(image, x1: 26, y1: 34, x2: 37, y2: 38, color: amber);
    },
    'chest': (image) {
      img.fillRect(image, x1: 10, y1: 20, x2: 53, y2: 54, color: wood);
      img.drawRect(image, x1: 10, y1: 20, x2: 53, y2: 54, color: outline, thickness: 3);
      img.fillRect(image, x1: 10, y1: 20, x2: 53, y2: 30, color: woodDark);
      img.fillRect(image, x1: 29, y1: 28, x2: 34, y2: 38, color: amber);
      img.drawRect(image, x1: 29, y1: 28, x2: 34, y2: 38, color: outline, thickness: 2);
    },
    'clock': (image) {
      img.fillCircle(image, x: 32, y: 32, radius: 22, color: cream);
      ring(image, x: 32, y: 32, radius: 22, color: outline, thickness: 3);
      ring(image, x: 32, y: 32, radius: 16, color: outline, thickness: 2);
      img.drawLine(image, x1: 32, y1: 32, x2: 32, y2: 20, color: outline, thickness: 3);
      img.drawLine(image, x1: 32, y1: 32, x2: 42, y2: 36, color: red, thickness: 3);
    },
    'globe': (image) {
      img.fillCircle(image, x: 32, y: 28, radius: 20, color: blue);
      ring(image, x: 32, y: 28, radius: 20, color: outline, thickness: 3);
      img.fillCircle(image, x: 26, y: 20, radius: 7, color: leaf);
      img.fillCircle(image, x: 38, y: 32, radius: 6, color: leaf);
      img.fillRect(image, x1: 29, y1: 46, x2: 35, y2: 54, color: metalDark);
      img.fillRect(image, x1: 22, y1: 52, x2: 42, y2: 58, color: metal);
    },
    'portrait': (image) {
      img.fillRect(image, x1: 14, y1: 10, x2: 49, y2: 54, color: amber);
      img.drawRect(image, x1: 14, y1: 10, x2: 49, y2: 54, color: outline, thickness: 3);
      img.fillRect(image, x1: 20, y1: 16, x2: 43, y2: 48, color: cream);
      img.fillCircle(image, x: 32, y: 28, radius: 7, color: metalDark);
      img.fillRect(image, x1: 24, y1: 36, x2: 40, y2: 48, color: fabric);
    },
    'fireplace': (image) {
      img.fillRect(image, x1: 8, y1: 12, x2: 55, y2: 56, color: metalDark);
      img.drawRect(image, x1: 8, y1: 12, x2: 55, y2: 56, color: outline, thickness: 3);
      img.fillRect(image, x1: 18, y1: 24, x2: 45, y2: 54, color: outline);
      img.fillCircle(image, x: 26, y: 44, radius: 8, color: red);
      img.fillCircle(image, x: 38, y: 46, radius: 7, color: amber);
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
