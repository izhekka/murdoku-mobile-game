import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';

/// Contract test for the issue 87 contrast bars — the binding source of
/// truth for the token palette, not the palette itself. All color math is
/// hand-written here with only `dart:math` (no new dependencies):
///
/// - WCAG 2.1 relative luminance and contrast ratio (4.5 / 2.5 / 1.5 / 1.3
///   bars),
/// - sRGB → CIE Lab → CIE76 ΔE for pairwise distinctness (≥ 15),
/// - Machado, Oliveira & Fernandes 2009 0.6-impact deuteranopia /
///   protanopia simulation on linear RGB (ΔE ≥ 12 after each), so a
///   color-vision-deficient player can still tell the 8 rooms apart.
///
/// The 0.6-impact matrices are the published Machado et al. 2009 values
/// (cross-checked against the authors' page and the DaltonLens-Python
/// implementation); they apply to linear RGB with per-channel clamping.

/// Machado et al. 2009, deuteranomaly, severity 0.6 — rows R, G, B.
const _machadoDeutan06 = <List<double>>[
  [0.498864, 0.674741, -0.173604],
  [0.205199, 0.754872, 0.039929],
  [-0.011131, 0.030969, 0.980162],
];

/// Machado et al. 2009, protanomaly, severity 0.6 — rows R, G, B.
const _machadoProtan06 = <List<double>>[
  [0.385450, 0.769005, -0.154455],
  [0.100526, 0.829802, 0.069673],
  [-0.007442, -0.022190, 1.029632],
];

const _white = Color(0xFFFFFFFF);

/// The WCAG/IEC sRGB transfer function (gamma → linear).
double _srgbToLinear(double gamma) => gamma <= 0.04045
    ? gamma / 12.92
    : math.pow((gamma + 0.055) / 1.055, 2.4).toDouble();

/// Inverse of [_srgbToLinear] (linear → gamma).
double _linearToSrgb(double linear) => linear <= 0.0031308
    ? 12.92 * linear
    : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;

double _relativeLuminance(Color color) {
  final linear = _channelsOf(color).map(_srgbToLinear).toList();
  return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}

/// WCAG 2.1 contrast ratio between two opaque sRGB colors.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Gamma-encoded 0..1 channels, straight from the 8-bit constants.
List<double> _channelsOf(Color color) {
  final argb = color.toARGB32();
  return [
    ((argb >> 16) & 0xFF) / 255,
    ((argb >> 8) & 0xFF) / 255,
    (argb & 0xFF) / 255,
  ];
}

(double, double, double) _labOf(Color color) {
  final linear = _channelsOf(color).map(_srgbToLinear).toList();
  const xyz = <List<double>>[
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041],
  ];
  double x = 0, y = 0, z = 0;
  for (var i = 0; i < 3; i++) {
    x += xyz[0][i] * linear[i];
    y += xyz[1][i] * linear[i];
    z += xyz[2][i] * linear[i];
  }
  const white = [0.95047, 1.0, 1.08883];
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : t / 0.12841855 + 4 / 29;
  final fx = f(x / white[0]);
  final fy = f(y / white[1]);
  final fz = f(z / white[2]);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// CIE76 color difference between two sRGB colors.
double _deltaE(Color a, Color b) {
  final (l1, aStar1, bStar1) = _labOf(a);
  final (l2, aStar2, bStar2) = _labOf(b);
  final dl = l1 - l2, da = aStar1 - aStar2, db = bStar1 - bStar2;
  return math.sqrt(dl * dl + da * da + db * db);
}

/// Simulates the deficiency with the Machado matrix on **linear** RGB and
/// clamps each channel back into the sRGB gamut.
Color _simulateCvd(Color color, List<List<double>> matrix) {
  final linear = _channelsOf(color).map(_srgbToLinear).toList();
  int channel(int row) {
    var value =
        matrix[row][0] * linear[0] +
        matrix[row][1] * linear[1] +
        matrix[row][2] * linear[2];
    value = value.clamp(0.0, 1.0);
    final gamma = _linearToSrgb(value) * 255;
    return gamma.round().clamp(0, 255);
  }

  return Color.fromARGB(0xFF, channel(0), channel(1), channel(2));
}

String _hexOf(Color color) {
  final argb = color.toARGB32() & 0xFFFFFF;
  return '#${argb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

void main() {
  final skins = [candyTokens, stickerTokens, comicTokens];

  test(
    'toolbar pill/glyph pairs meet WCAG AA on every cartoon skin (issue 87)',
    () {
      for (final t in skins) {
        for (final entry in {
          'place': t.actions.place,
          'mark': t.actions.mark,
          'erase': t.actions.erase,
          'undo': t.actions.undo,
          'hint': t.actions.hint,
          'check': t.actions.check,
          'menu': t.actions.menu,
        }.entries) {
          final ratio = _contrastRatio(t.ink, entry.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${t.skin} ${entry.key}: ink ${_hexOf(t.ink)} on '
                '${_hexOf(entry.value)} must reach AA 4.5:1, measured $ratio',
          );
        }
        final danger = _contrastRatio(_white, t.dangerColor);
        expect(
          danger,
          greaterThanOrEqualTo(4.5),
          reason:
              '${t.skin}: white on danger ${_hexOf(t.dangerColor)} must reach '
              'AA 4.5:1, measured $danger',
        );
        expect(
          t.actions.accuse,
          t.dangerColor,
          reason: '${t.skin}: the accuse pill carries the danger accent itself',
        );
      }
    },
  );

  test('candy inkSoft meets AA on white (issue 87)', () {
    // The clue text paints onSurfaceVariant == inkSoft (suspect_panel.dart)
    // and renders directly on the white cards since issue 89 removed the
    // chip surface — the on-white bar is the binding one.
    final onWhite = _contrastRatio(candyTokens.inkSoft, _white);
    expect(
      onWhite,
      greaterThanOrEqualTo(4.5),
      reason:
          'candy inkSoft ${_hexOf(candyTokens.inkSoft)} on white '
          'must reach AA 4.5:1, measured $onWhite',
    );
  });

  test('candy room tints separate from the page (issue 87)', () {
    final page = candyTokens.appBackground;
    for (var i = 0; i < candyTokens.roomTints.length; i++) {
      final tint = candyTokens.roomTints[i];
      final ratio = _contrastRatio(tint, page);
      expect(
        ratio,
        greaterThanOrEqualTo(1.5),
        reason:
            'candy room tint[$i] ${_hexOf(tint)} vs page '
            '${_hexOf(page)} must reach 1.5:1, measured $ratio',
      );
    }
  });

  test('candy room tints stay distinct with and without CVD (issue 87)', () {
    final tints = candyTokens.roomTints;
    expect(tints.length, 8);
    for (var i = 0; i < tints.length; i++) {
      for (var j = i + 1; j < tints.length; j++) {
        final plain = _deltaE(tints[i], tints[j]);
        expect(
          plain,
          greaterThanOrEqualTo(15),
          reason:
              'candy tints[$i]/[$j] ${_hexOf(tints[i])} vs '
              '${_hexOf(tints[j])}: CIE76 ΔE must be >= 15, measured $plain',
        );
        final deutan = _deltaE(
          _simulateCvd(tints[i], _machadoDeutan06),
          _simulateCvd(tints[j], _machadoDeutan06),
        );
        expect(
          deutan,
          greaterThanOrEqualTo(12),
          reason:
              'candy tints[$i]/[$j] ${_hexOf(tints[i])} vs '
              '${_hexOf(tints[j])}: deuteranopia ΔE must be >= 12, '
              'measured $deutan',
        );
        final protan = _deltaE(
          _simulateCvd(tints[i], _machadoProtan06),
          _simulateCvd(tints[j], _machadoProtan06),
        );
        expect(
          protan,
          greaterThanOrEqualTo(12),
          reason:
              'candy tints[$i]/[$j] ${_hexOf(tints[i])} vs '
              '${_hexOf(tints[j])}: protanopia ΔE must be >= 12, '
              'measured $protan',
        );
      }
    }
  });

  test('candy victim cell separates (issue 87)', () {
    final page = candyTokens.appBackground;
    final fill = _contrastRatio(candyTokens.victimFill, page);
    expect(
      fill,
      greaterThanOrEqualTo(1.5),
      reason:
          'candy victim fill ${_hexOf(candyTokens.victimFill)} vs page '
          'must reach 1.5:1, measured $fill',
    );
    final stripe = _contrastRatio(
      candyTokens.victimStripeColor,
      candyTokens.victimFill,
    );
    expect(
      stripe,
      greaterThanOrEqualTo(2.5),
      reason:
          'candy victim stripes '
          '${_hexOf(candyTokens.victimStripeColor)} vs their fill '
          '${_hexOf(candyTokens.victimFill)} must reach 2.5:1, '
          'measured $stripe',
    );
    // The clue chip's surface-vs-card bar (issue 87) is gone with the pill
    // (issue 89): the sentences paint directly on the card.
  });
}
