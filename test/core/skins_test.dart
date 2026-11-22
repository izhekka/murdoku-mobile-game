import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/storage/prefs_repository.dart';

const scheme = _FakeScheme();

/// Minimal stand-in for a resolved ColorScheme: skinTokensFor(classic, …)
/// derives classic tokens from it, so the mapping must be verified against
/// the very values passed in.
class _FakeScheme implements ColorScheme {
  const _FakeScheme();

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeScheme';

  @override
  dynamic noSuchMethod(Invocation invocation) => switch (invocation.memberName) {
        #surface => const Color(0xFFAAAAAA),
        #onSurface => const Color(0xFFBBBBBB),
        #onSurfaceVariant => const Color(0xFFCCCCCC),
        #primaryContainer => const Color(0xFFDDDDDD),
        #onPrimaryContainer => const Color(0xFFEEEEEE),
        #outline => const Color(0xFFF1F1F1),
        #outlineVariant => const Color(0xFFF2F2F2),
        #errorContainer => const Color(0xFFF3F3F3),
        #error => const Color(0xFFF4F4F4),
        #primary => const Color(0xFFF5F5F5),
        _ => throw UnimplementedError('${invocation.memberName}'),
      };
}

Color c(int value) => Color(value);

void main() {
  test('candy tokens carry the mockup values (issue 23)', () {
    final t = candyTokens;
    expect(t.skin, SkinSetting.candy);
    expect(t.isCartoon, isTrue);
    expect(t.solidRooms, isTrue);
    expect(t.ink, c(0xFF35406E));
    expect(t.inkSoft, c(0xFF6B76A8));
    expect(t.appBackground, c(0xFFFFFFFF));
    expect(t.pageColor, c(0xFF6FCBFF));
    expect(t.pageGradient,
        [c(0xFF6FCBFF), c(0xFFA9EBFF), c(0xFFC6F6FF)]);
    expect(t.card.background, c(0xFFFFFFFF));
    expect(t.card.borderColor, c(0xFFFFFFFF));
    expect(t.card.borderWidth, 4);
    expect(t.card.radius, 20);
    expect(t.card.shadow.color, c(0x241F6C9E));
    expect(t.card.shadow.offset, const Offset(0, 6));
    expect(t.mortarColor, c(0xFFFFFFFF));
    expect(t.roomTints.take(6).toList(), [
      c(0xFFFF9EB5),
      c(0xFFFFC078),
      c(0xFFFFE999),
      c(0xFFD0BFFF),
      c(0xFF8FF2C8),
      c(0xFF9FD5FF),
    ]);
    expect(t.victimStripeColor, isNot(t.victimFill));
    expect(t.menuIcons, isFalse);
  });

  test('sticker tokens carry the mockup values (issue 23)', () {
    final t = stickerTokens;
    expect(t.skin, SkinSetting.sticker);
    expect(t.isCartoon, isTrue);
    expect(t.solidRooms, isTrue);
    expect(t.ink, c(0xFF1D3557));
    expect(t.inkSoft, c(0xFF457B9D));
    expect(t.appBackground, c(0xFFFFF8EF));
    expect(t.pageColor, c(0xFF45C4B0));
    expect(t.pageDotColor, isNotNull);
    expect(t.card.background, c(0xFFFFFFFF));
    expect(t.card.borderColor, c(0xFF1D3557));
    expect(t.card.borderWidth, 3);
    expect(t.card.shadow.color, c(0xFF1D3557));
    expect(t.card.shadow.offset, const Offset(6, 6));
    expect(t.mortarColor, c(0xFF1D3557));
    expect(t.roomTints.take(6).toList(), [
      c(0xFFFF6B6B),
      c(0xFFFFA94D),
      c(0xFFFFD43B),
      c(0xFFB197FC),
      c(0xFF63E6BE),
      c(0xFF74C0FC),
    ]);
    expect(t.menuIcons, isFalse);
  });

  test('comic tokens carry the mockup values (issue 23)', () {
    final t = comicTokens;
    expect(t.skin, SkinSetting.comic);
    expect(t.isCartoon, isTrue);
    expect(t.solidRooms, isTrue);
    expect(t.ink, c(0xFF111111));
    expect(t.inkSoft, c(0xFF444444));
    expect(t.appBackground, c(0xFFFFFFFF));
    expect(t.pageColor, c(0xFFFFD43B));
    expect(t.pageDotColor, isNotNull);
    expect(t.card.borderColor, c(0xFF111111));
    expect(t.card.borderWidth, 3.5);
    expect(t.card.shadow.color, c(0xFF111111));
    expect(t.card.shadow.offset, const Offset(7, 7));
    expect(t.mortarColor, c(0xFF111111));
    expect(t.roomTints.take(6).toList(), [
      c(0xFFFF595E),
      c(0xFFFFCA3A),
      c(0xFFFFE24A),
      c(0xFF9B5DE5),
      c(0xFF70E000),
      c(0xFF00B4D8),
    ]);
    expect(t.menuIcons, isFalse);
  });

  test('comic renders panel headers uppercase; other skins title case (issue 27)',
      () {
    expect(comicTokens.panelHeaderUppercase, isTrue);
    for (final t in [candyTokens, stickerTokens]) {
      expect(t.panelHeaderUppercase, isFalse,
          reason: '${t.skin} header stays title case per its mockup');
    }
    expect(
        skinTokensFor(SkinSetting.classic, scheme).panelHeaderUppercase,
        isFalse,
        reason: 'classic header is plain, no uppercase');
  });

  test('shared toolbar action colors on every cartoon skin (issue 23)', () {
    for (final t in [candyTokens, stickerTokens, comicTokens]) {
      expect(t.actions.place, c(0xFFFF6B9D), reason: '${t.skin} place');
      expect(t.actions.mark, c(0xFFFFA94D), reason: '${t.skin} mark');
      expect(t.actions.erase, c(0xFF38D9A9), reason: '${t.skin} erase');
      expect(t.actions.undo, c(0xFF74C0FC), reason: '${t.skin} undo');
      expect(t.actions.hint, c(0xFFFFC078), reason: '${t.skin} hint');
      expect(t.actions.check, c(0xFF51CF66), reason: '${t.skin} check');
      expect(t.actions.menu, c(0xFFB197FC), reason: '${t.skin} menu');
      expect(t.dangerColor, c(0xFFE8590C), reason: '${t.skin} danger');
    }
  });

  test('every skin exposes 8 distinct room tints (issue 23)', () {
    final classic = skinTokensFor(SkinSetting.classic, scheme);
    for (final t in [classic, candyTokens, stickerTokens, comicTokens]) {
      expect(t.roomTints.length, 8, reason: '${t.skin} tint count');
      expect(t.roomTints.toSet().length, 8,
          reason: '${t.skin} tints must be pairwise distinct');
    }
  });

  test('every cartoon skin exposes the mockup clue chip (issue 26)', () {
    for (final t in [candyTokens, stickerTokens, comicTokens]) {
      expect(t.chip, isNotNull, reason: '${t.skin} chip token');
      expect(t.chip!.background, c(0xFFF1F3F5), reason: '${t.skin} chip color');
      expect(t.chip!.radius, 12, reason: '${t.skin} chip radius');
      expect(
          t.chip!.padding,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          reason: '${t.skin} chip padding');
      expect(t.chip!.gap, 6, reason: '${t.skin} chip gap');
    }
  });

  test('classic keeps the pre-existing plain clue look (issue 26)', () {
    expect(skinTokensFor(SkinSetting.classic, scheme).chip, isNull);
  });

  test('classic tokens derive from the resolved scheme (issue 23)', () {
    final t = skinTokensFor(SkinSetting.classic, scheme);
    expect(t.skin, SkinSetting.classic);
    expect(t.isCartoon, isFalse);
    expect(t.solidRooms, isFalse);
    expect(t.appBackground, c(0xFFAAAAAA));
    expect(t.ink, c(0xFFBBBBBB));
    expect(t.inkSoft, c(0xFFCCCCCC));
    expect(t.mortarColor, c(0xFFF1F1F1));
    expect(t.badge.background, c(0xFFDDDDDD));
    expect(t.badge.ink, c(0xFFEEEEEE));
    expect(t.victimFill, c(0xFFF3F3F3));
    expect(t.dangerColor, c(0xFFF4F4F4));
    expect(t.menuIcons, isTrue);
    expect(t.frame, isNull, reason: 'classic has no cartoon page frame');
  });

  testWidgets('SkinScope exposes tokens; maybeOf is null without a scope',
      (tester) async {
    late final SkinTokens fromOf;
    late final SkinTokens? fromMaybe;
    late final SkinTokens? outside;

    await tester.pumpWidget(Column(children: [
      SkinScope(
        tokens: stickerTokens,
        child: Builder(builder: (context) {
          fromOf = SkinScope.of(context);
          fromMaybe = SkinScope.maybeOf(context);
          return const SizedBox.shrink();
        }),
      ),
      Builder(builder: (context) {
        outside = SkinScope.maybeOf(context);
        return const SizedBox.shrink();
      }),
    ]));

    expect(fromOf, same(stickerTokens));
    expect(fromMaybe, same(stickerTokens));
    expect(outside, isNull);
  });
}
