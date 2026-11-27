import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/board_view.dart';

import '../../support/legacy_case_fixture.dart';

/// Issue #93 board rendering pins: a legacy in-progress save must render on
/// its OWN stored grid (6×6 despite the new 7×7 standard knob), and the
/// interim 7×7 hard board must lay out every cell without overflow.
Widget wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

Future<void> pumpCase(
  WidgetTester tester,
  CaseData caseData, {
  Size view = const Size(320, 569),
}) async {
  tester.view.physicalSize = view;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    wrap(
      BoardView(
        caseData: caseData,
        placed: const {},
        xMarks: const {},
        selectedSuspectId: null,
        onCellTap: (_) {},
        onCellDrag: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legacy 6x6 save renders a 6x6 board (issue #93)', (
    tester,
  ) async {
    await pumpCase(tester, legacyStandardCase);
    for (var edge = 0; edge < 6; edge++) {
      expect(
        find.byKey(Key('cell_0_$edge')),
        findsOneWidget,
        reason: 'legacy board row 0 cell $edge must exist',
      );
      expect(
        find.byKey(Key('cell_${edge}_5')),
        findsOneWidget,
        reason: 'legacy board column 5 cell $edge must exist',
      );
    }
    // And nothing of the 7th row leaks in.
    expect(find.byKey(const Key('cell_0_6')), findsNothing);
    expect(find.byKey(const Key('cell_6_0')), findsNothing);
  });

  testWidgets('interim 7x7 hard board lays out every cell without overflow', (
    tester,
  ) async {
    // Hard stays 7x7 in the interim configuration (owner split decision,
    // issue #93; the 9x9 leg is deferred to #98).
    final c = generateCase(difficulty: Difficulty.hard, seed: 3);
    expect(c.gridSize, 7);
    await pumpCase(tester, c);
    expect(find.byKey(const Key('cell_6_6')), findsOneWidget);
    expect(find.byKey(const Key('cell_0_0')), findsOneWidget);
    expect(find.byKey(const Key('cell_0_7')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
