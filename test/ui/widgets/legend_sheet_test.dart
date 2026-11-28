import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/legend_sheet.dart';

final CaseData fixture = generateCase(difficulty: Difficulty.easy, seed: 3);

Widget wrap() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: IconButton(
          icon: const Icon(Icons.menu_book),
          onPressed: () => showLegendSheet(context, fixture),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('legend lists every room with its localized name', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    final context = tester.element(find.byType(Scaffold));
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, fixture);

    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    expect(find.text(l10n.legendTitle), findsOneWidget);
    expect(find.text(l10n.legendRooms), findsOneWidget);
    expect(find.text(l10n.legendItems), findsOneWidget);
    for (var i = 0; i < fixture.rooms.length; i++) {
      expect(
        find.text('${i + 1} — ${names.roomNom(fixture.rooms[i].id)}'),
        findsOneWidget,
        reason: 'room ${fixture.rooms[i].id} numbered in the legend',
      );
    }
  });

  testWidgets('legend lists every item kind with occupiability hint', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    final context = tester.element(find.byType(Scaffold));
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, fixture);

    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    final kinds = fixture.objects.map((o) => o.kind).toSet();
    for (final kind in kinds) {
      expect(
        find.text(names.objectNom(kind)),
        findsOneWidget,
        reason: 'item ${kind.name} named in the legend',
      );
    }
    // Occupiability hint present for both categories present in the case.
    if (fixture.objects.any((o) => o.occupiable)) {
      expect(find.text(l10n.legendOccupiable), findsWidgets);
    }
    if (fixture.objects.any((o) => !o.occupiable)) {
      expect(find.text(l10n.stateBlocked), findsWidgets);
    }
  });

  testWidgets('cartoon skin: solid swatches with mortar borders (issue 23)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Scope at the builder level, mirroring lib/app.dart: the legend is a
        // modal sheet above the navigator.
        builder: (context, child) =>
            SkinScope(tokens: comicTokens, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: IconButton(
                icon: const Icon(Icons.menu_book),
                onPressed: () => showLegendSheet(context, fixture),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    // Every room swatch paints the solid room tint with a mortar border.
    final swatches = find
        .byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.constraints?.maxWidth == 24) &&
              (w.constraints?.maxHeight == 24),
        )
        .evaluate()
        .toList();
    expect(swatches.length, fixture.rooms.length);
    for (var i = 0; i < fixture.rooms.length; i++) {
      final swatch = swatches[i].widget as Container;
      final decoration = swatch.decoration as BoxDecoration;
      expect(
        decoration.color,
        comicTokens.roomTints[i % 8],
        reason: 'swatch ${i + 1} solid tint',
      );
      expect(decoration.border?.top.color, comicTokens.mortarColor);
    }
  });

  testWidgets('compact rows in portrait: room and item rows stay <= 44 px '
      '(issue 109)', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    for (var i = 0; i < fixture.rooms.length; i++) {
      expect(
        tester.getRect(find.byKey(ValueKey('legend_room_$i'))).height,
        lessThanOrEqualTo(44),
        reason: 'room row $i must stay compact',
      );
    }
    for (final kind in fixture.objects.map((o) => o.kind).toSet()) {
      expect(
        tester.getRect(find.byKey(ValueKey('legend_item_${kind.name}'))).height,
        lessThanOrEqualTo(44),
        reason: 'item ${kind.name} row must stay compact',
      );
    }
  });

  testWidgets('landscape: the rooms column sits left of the items column '
      '(issue 109)', (tester) async {
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    final roomsRect = tester.getRect(find.byKey(const Key('legend_rooms')));
    final itemsRect = tester.getRect(find.byKey(const Key('legend_items')));
    expect(
      roomsRect.left,
      lessThan(itemsRect.left),
      reason: 'rooms column left, items column right',
    );
    expect(
      itemsRect.left,
      greaterThanOrEqualTo(roomsRect.right),
      reason: 'the two columns sit side by side, not stacked',
    );
  });
}
