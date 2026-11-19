import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates the app icon without any binary assets in the repo:
/// a dark indigo rounded-ish square, an amber 3x3 mini-grid, one amber
/// suspect dot and one red victim dot with a white "V".
///
/// Run: `dart run tool/gen_icon.dart`
void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);

  final indigo = img.ColorRgb8(26, 26, 46); // #1A1A2E
  final amber = img.ColorRgb8(200, 155, 60); // #C89B3C
  final red = img.ColorRgb8(178, 58, 58); // #B23A3A
  final white = img.ColorRgb8(240, 238, 230);

  img.fillRect(image, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: indigo);

  // 3x3 mini-grid, centered, amber strokes.
  const grid = 620;
  const cell = grid ~/ 3;
  final left = (size - grid) ~/ 2;
  final top = (size - grid) ~/ 2;
  const stroke = 22;

  for (final line in <(int, int, int, int)>[
    // verticals
    (left + cell, top, left + cell, top + grid),
    (left + 2 * cell, top, left + 2 * cell, top + grid),
    // horizontals
    (left, top + cell, left + grid, top + cell),
    (left, top + 2 * cell, left + grid, top + 2 * cell),
  ]) {
    img.fillRect(image,
        x1: line.$1 - stroke ~/ 2,
        y1: line.$2 - stroke ~/ 2,
        x2: line.$3 + stroke ~/ 2,
        y2: line.$4 + stroke ~/ 2,
        color: amber);
  }
  // Outer grid frame.
  img.drawRect(image,
      x1: left,
      y1: top,
      x2: left + grid,
      y2: top + grid,
      color: amber,
      thickness: stroke);

  // Amber suspect dot in the top-left cell.
  final suspectCx = left + cell ~/ 2;
  final suspectCy = top + cell ~/ 2;
  img.fillCircle(image,
      x: suspectCx, y: suspectCy, radius: 58, color: amber);

  // Red victim dot with a white "V" (two strokes) in the bottom-right cell.
  final victimCx = left + 2 * cell + cell ~/ 2;
  final victimCy = top + 2 * cell + cell ~/ 2;
  img.fillCircle(image, x: victimCx, y: victimCy, radius: 58, color: red);
  img.drawLine(image,
      x1: victimCx - 26,
      y1: victimCy - 24,
      x2: victimCx,
      y2: victimCy + 26,
      color: white,
      thickness: 12);
  img.drawLine(image,
      x1: victimCx,
      y1: victimCy + 26,
      x2: victimCx + 26,
      y2: victimCy - 24,
      color: white,
      thickness: 12);

  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(image));
  // Foreground variant: same drawing on transparent background for Android
  // adaptive icons (safe zone keeps the grid visible).
  final fg = img.Image(width: size, height: size);
  img.fillRect(fg,
      x1: left,
      y1: top,
      x2: left + grid,
      y2: top + grid,
      color: indigo,
      radius: 90);
  for (final line in <(int, int, int, int)>[
    (left + cell, top, left + cell, top + grid),
    (left + 2 * cell, top, left + 2 * cell, top + grid),
    (left, top + cell, left + grid, top + cell),
    (left, top + 2 * cell, left + grid, top + 2 * cell),
  ]) {
    img.fillRect(fg,
        x1: line.$1 - stroke ~/ 2,
        y1: line.$2 - stroke ~/ 2,
        x2: line.$3 + stroke ~/ 2,
        y2: line.$4 + stroke ~/ 2,
        color: amber);
  }
  img.fillCircle(fg, x: suspectCx, y: suspectCy, radius: 58, color: amber);
  img.fillCircle(fg, x: victimCx, y: victimCy, radius: 58, color: red);
  img.drawLine(fg,
      x1: victimCx - 26,
      y1: victimCy - 24,
      x2: victimCx,
      y2: victimCy + 26,
      color: white,
      thickness: 12);
  img.drawLine(fg,
      x1: victimCx,
      y1: victimCy + 26,
      x2: victimCx + 26,
      y2: victimCy - 24,
      color: white,
      thickness: 12);
  File('assets/icon/icon_foreground.png').writeAsBytesSync(img.encodePng(fg));

  stdout.writeln('icons written: assets/icon/icon.png, '
      'assets/icon/icon_foreground.png');
}
