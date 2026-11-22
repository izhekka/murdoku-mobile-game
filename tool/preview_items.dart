import 'dart:io';

import 'package:image/image.dart' as img;

/// Renders all item sprites on a neutral background with their ru names —
/// a quick visual check after regenerating assets.
/// Run: `dart run tool/preview_items.dart`
void main() {
  final items = <String, String>{
    'table': 'Стол',
    'chair': 'Стул',
    'flowers': 'Цветы',
    'sofa': 'Диван',
    'bookshelf': 'Стеллаж',
    'lamp': 'Лампа',
    'piano': 'Пианино',
    'plant': 'Растение',
    'chest': 'Сундук',
    'clock': 'Часы',
    'portrait': 'Портрет',
    'fireplace': 'Камин',
    'globe': 'Глобус',
    'armor': 'Доспехи',
    'victim': 'Жертва',
  };
  final tile = 128;
  final cols = 5;
  final rows = (items.length + cols - 1) ~/ cols;
  final canvas = img.Image(
    width: cols * (tile + 40) + 20,
    height: rows * (tile + 60) + 20,
  );
  img.fill(canvas, color: img.ColorRgb8(120, 120, 130));
  var i = 0;
  for (final entry in items.entries) {
    final file = File('assets/items/${entry.key}.png');
    if (!file.existsSync()) {
      stderr.writeln('missing: ${file.path}');
      continue;
    }
    final image = img.decodePng(file.readAsBytesSync())!;
    final big = img.copyResize(image, width: tile, height: tile);
    final px = (i % cols) * (tile + 40) + 20;
    final py = (i ~/ cols) * (tile + 60) + 20;
    img.compositeImage(canvas, big, dstX: px, dstY: py);
    final label = img.Image(width: 200, height: 36);
    img.fill(label, color: img.ColorRgb8(255, 240, 150));
    img.drawString(
      label,
      entry.value,
      font: img.arial14,
      x: 4,
      y: 8,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.compositeImage(canvas, label, dstX: px, dstY: py + tile + 4);
    i++;
  }
  File('/tmp/items_preview.png').writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('wrote /tmp/items_preview.png');
}
