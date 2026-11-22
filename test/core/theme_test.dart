import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/theme.dart';
import 'package:murdoku/storage/prefs_repository.dart';

/// Squared RGB distance on the 0–255 channel scale, per the UX plan.
double _channelSq(double a, double b) {
  final d = (a - b) * 255;
  return d * d;
}

double colorDistance(Color a, Color b) =>
    _channelSq(a.r, b.r) + _channelSq(a.g, b.g) + _channelSq(a.b, b.b);

void main() {
  test('room palette: first 7 colors pairwise distant (UX-3)', () {
    final colors = AppTheme.roomColors(8);
    for (var i = 0; i < 7; i++) {
      for (var j = i + 1; j < 7; j++) {
        expect(colorDistance(colors[i], colors[j]), greaterThan(9000),
            reason: 'room colors $i and $j are too close to tell apart');
      }
    }
  });

  test('room palette: every color bright, not muddy (UX-3)', () {
    final colors = AppTheme.roomColors(8);
    for (var i = 0; i < colors.length; i++) {
      final lightness = HSLColor.fromColor(colors[i]).lightness;
      expect(lightness, inInclusiveRange(0.45, 0.75),
          reason: 'room color $i lightness $lightness outside 0.45–0.75');
    }
  });

  test('forSkin(classic) keeps the current light/dark pair (issue 23)', () {
    expect(identical(AppTheme.forSkin(SkinSetting.classic, Brightness.light),
        AppTheme.light), isTrue);
    expect(identical(AppTheme.forSkin(SkinSetting.classic, Brightness.dark),
        AppTheme.dark), isTrue);
  });

  test('cartoon skins are light-only, even when asked for dark (issue 23)',
      () {
    for (final skin in SkinSetting.values.where((s) => s != SkinSetting.classic)) {
      final theme = AppTheme.forSkin(skin, Brightness.dark);
      expect(theme.brightness, Brightness.light, reason: '$skin brightness');
      expect(theme.colorScheme.brightness, Brightness.light,
          reason: '$skin scheme brightness');
    }
  });

  test('roomColors(count, skin) stays classic by default (issue 23)', () {
    expect(AppTheme.roomColors(8),
        AppTheme.roomColors(8, SkinSetting.classic));
  });

  test('roomColors(8, cartoon skin) has no duplicate colors (issue 23)', () {
    for (final skin in SkinSetting.values.where((s) => s != SkinSetting.classic)) {
      final colors = AppTheme.roomColors(8, skin);
      expect(colors.toSet().length, 8,
          reason: '$skin room tints must be pairwise distinct');
    }
  });
}
