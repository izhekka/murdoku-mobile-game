import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/legend_sheet.dart';
import 'package:murdoku/domain/localized_names.dart';

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
  testWidgets('legend lists every room with its localized name', (tester) async {
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
      expect(find.text('${i + 1} — ${names.roomNom(fixture.rooms[i].id)}'),
          findsOneWidget,
          reason: 'room ${fixture.rooms[i].id} numbered in the legend');
    }
  });

  testWidgets('legend lists every item kind with occupiability hint',
      (tester) async {
    await tester.pumpWidget(wrap());
    final context = tester.element(find.byType(Scaffold));
    final l10n = AppLocalizations.of(context)!;
    final names = NameForms.forLocale(l10n.localeName, fixture);

    await tester.tap(find.byIcon(Icons.menu_book));
    await tester.pumpAndSettle();

    final kinds = fixture.objects.map((o) => o.kind).toSet();
    for (final kind in kinds) {
      expect(find.text(names.objectNom(kind)), findsOneWidget,
          reason: 'item ${kind.name} named in the legend');
    }
    // Occupiability hint present for both categories present in the case.
    if (fixture.objects.any((o) => o.occupiable)) {
      expect(find.text(l10n.legendOccupiable), findsWidgets);
    }
    if (fixture.objects.any((o) => !o.occupiable)) {
      expect(find.text(l10n.stateBlocked), findsWidgets);
    }
  });
}
