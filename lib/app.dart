import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/routes.dart';
import 'core/skins.dart';
import 'core/theme.dart';
import 'l10n/generated/app_localizations.dart';
import 'storage/prefs_repository.dart' show LanguageSetting, SkinSetting;
import 'state/settings_controller.dart';

/// Single source of truth for the app's localization delegates: both
/// MurdokuApp and test/support/localized_test_app.dart pass exactly this
/// const (identity-checked by tests) so they cannot drift (issue 24).
const List<LocalizationsDelegate<dynamic>> murdokuLocalizationsDelegates = [
  // material_ui's own MaterialLocalizations must come last: components
  // look up material_ui's type, which the SDK flutter_localizations
  // delegates do not provide (they implement the deprecated
  // flutter/material type). Without this, non-English locales crash.
  // Cupertino: cupertino_ui's delegate likewise provides the type
  // material_ui's WidgetsApp checks (the SDK one implements the
  // deprecated flutter/cupertino type).
  ...AppLocalizations.localizationsDelegates,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class MurdokuApp extends ConsumerWidget {
  const MurdokuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    // Cartoon skins are light-only designs: the ThemeMode choice applies to
    // the classic skin alone (issue 23).
    final themeMode = settings.skin == SkinSetting.classic
        ? settings.themeMode
        : ThemeMode.light;
    return MaterialApp.router(
      title: 'Murdoku',
      theme: AppTheme.forSkin(settings.skin, Brightness.light),
      darkTheme: AppTheme.forSkin(settings.skin, Brightness.dark),
      themeMode: themeMode,
      locale: switch (settings.language) {
        LanguageSetting.system => null,
        LanguageSetting.russian => const Locale('ru'),
        LanguageSetting.english => const Locale('en'),
      },
      localizationsDelegates: murdokuLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: buildRouter(),
      builder: (context, child) {
        // The builder context sits below MaterialApp, so the theme here is
        // the resolved one — classic tokens derive from its live scheme and
        // can never drift from the seed output.
        final tokens =
            skinTokensFor(settings.skin, Theme.of(context).colorScheme);
        return SkinScope(
          tokens: tokens,
          child: SkinFrame(tokens: tokens, child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// The cartoon page: skin backdrop (gradient / polka dots / clouds) with
/// the app content in a rounded token card. Classic has no frame and no
/// backdrop — its child passes through unchanged.
class SkinFrame extends StatelessWidget {
  const SkinFrame({super.key, required this.tokens, required this.child});

  final SkinTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frame = tokens.frame;
    if (!tokens.isCartoon || frame == null) return child;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: frame.background,
        borderRadius: BorderRadius.circular(frame.radius),
        border: Border.all(
            color: frame.borderColor, width: frame.borderWidth),
        boxShadow: [frame.shadow],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(frame.radius),
        child: child,
      ),
    );
    // Comic's white ring sits between the black border and the page.
    if (tokens.frameRingWidth > 0) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.frameRingColor,
          borderRadius: BorderRadius.circular(
              frame.radius + tokens.frameRingWidth),
          boxShadow: [frame.shadow],
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.frameRingWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: frame.background,
              borderRadius: BorderRadius.circular(frame.radius),
              border: Border.all(
                  color: frame.borderColor, width: frame.borderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(frame.radius),
              child: child,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.pageColor,
        gradient: tokens.pageGradient.isEmpty
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.pageGradient,
              ),
      ),
      // Background painter: the pattern belongs to the page behind the app
      // frame; the opaque frame content covers it inside the margins.
      child: CustomPaint(
        painter: SkinBackdropPainter(tokens: tokens),
        isComplex: true,
        child: Padding(
          padding: EdgeInsets.all(tokens.frameMargin),
          child: content,
        ),
      ),
    );
  }
}

/// Paints the skin's page pattern over the backdrop: white polka dots for
/// sticker/comic, soft cloud blobs for candy.
class SkinBackdropPainter extends CustomPainter {
  const SkinBackdropPainter({required this.tokens});

  final SkinTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = tokens.pageDotColor;
    if (dot != null) {
      const spacing = 56.0;
      const radius = 7.0;
      final paint = Paint()..color = dot;
      var offsetRow = false;
      for (double y = spacing / 2; y < size.height + radius; y += spacing) {
        for (double x = offsetRow ? spacing / 2 : 0;
            x < size.width + radius;
            x += spacing) {
          canvas.drawCircle(Offset(x, y), radius, paint);
        }
        offsetRow = !offsetRow;
      }
    }
    final blob = tokens.pageBlobColor;
    if (blob != null) {
      final paint = Paint()..color = blob;
      // A few soft white cloud blobs along the top, per the candy mockup.
      canvas.drawOval(
          const Rect.fromLTWH(-40, 30, 260, 90), paint);
      canvas.drawOval(
          Rect.fromLTWH(size.width - 220, 8, 240, 80), paint);
      canvas.drawOval(
          Rect.fromLTWH(size.width * 0.4, size.height - 120, 280, 100), paint);
    }
  }

  @override
  bool shouldRepaint(SkinBackdropPainter oldDelegate) =>
      tokens != oldDelegate.tokens;
}

/// Friendly replacement for the default red error screen; resolved inside
/// the app so localizations are available.
Widget fatalErrorWidget(FlutterErrorDetails details) {
  return Builder(builder: (context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n?.fatalErrorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        ),
      ),
    );
  });
}
