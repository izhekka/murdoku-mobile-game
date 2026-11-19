import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/avatar.dart';
import 'package:murdoku/ui/widgets/board_view.dart';

final CaseData fixture = generateCase(difficulty: Difficulty.easy, seed: 3);

Widget wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(child: child),
        ),
      ),
    );

Future<void> pumpBoard(
  WidgetTester tester, {
  required Map<String, Pos> placed,
  required Set<Pos> xMarks,
  String? selected,
  double textScale = 1.0,
  void Function(Pos)? onCellTap,
  void Function(Pos)? onCellDrag,
}) async {
  tester.view.physicalSize = const Size(320, 569);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(wrap(
    BoardView(
      caseData: fixture,
      placed: placed,
      xMarks: xMarks,
      selectedSuspectId: selected,
      onCellTap: onCellTap ?? (_) {},
      onCellDrag: onCellDrag ?? (_) {},
    ),
    textScale: textScale,
  ));
  await tester.pumpAndSettle();
}

/// Center of cell (row, col) in global coordinates.
Offset cellCenter(WidgetTester tester, int row, int col) {
  final boardRect = tester.getRect(find.byKey(const Key('board_view')));
  final cell = boardRect.width / fixture.gridSize;
  return Offset(
    boardRect.left + (col + 0.5) * cell,
    boardRect.top + (row + 0.5) * cell,
  );
}

void main() {
  testWidgets('taps report the correct cell position', (tester) async {
    Pos? tapped;
    await pumpBoard(tester,
        placed: {}, xMarks: {}, onCellTap: (p) => tapped = p);

    await tester.tapAt(cellCenter(tester, 2, 3));
    expect(tapped, (row: 2, col: 3));

    await tester.tapAt(cellCenter(tester, 0, 0));
    expect(tapped, (row: 0, col: 0));
  });

  testWidgets('drag reports cells along the way', (tester) async {
    final dragged = <Pos>[];
    await pumpBoard(tester,
        placed: {}, xMarks: {}, onCellDrag: (p) => dragged.add(p));

    // Stepped drag: two half-steps so the middle cell is crossed.
    final from = cellCenter(tester, 1, 1);
    final mid = cellCenter(tester, 1, 2);
    final to = cellCenter(tester, 1, 3);
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(mid - from);
    await gesture.moveBy(to - mid);
    await gesture.up();
    await tester.pump();

    expect(dragged, contains((row: 1, col: 2)));
    expect(dragged, contains((row: 1, col: 3)));
  });

  testWidgets('renders avatars for placed suspects and X marks', (tester) async {
    final placed = {
      's0': fixture.solution['s0']!,
      's2': fixture.solution['s2']!,
    };
    final xMarks = {fixture.solution['s4']!, fixture.solution['s3']!};
    await pumpBoard(tester, placed: placed, xMarks: xMarks);

    expect(find.byType(Avatar), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('victim cell is rendered distinctly with its own label',
      (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    expect(find.byKey(const Key('victim_cell')), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
  });

  testWidgets('selected suspect gets a highlight ring', (tester) async {
    final placed = {'s0': fixture.solution['s0']!};
    await pumpBoard(tester,
        placed: placed, xMarks: {}, selected: 's0');
    final selectedAvatars =
        find.byWidgetPredicate((w) => w is Avatar && w.selected);
    expect(selectedAvatars, findsOneWidget);
  });

  testWidgets('objects render with icons', (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    // Every object kind of the generated case is visible as an icon (kinds
    // may repeat across cells, so match at-least-one).
    expect(find.byIcon(objectIcon(fixture.objects.first.kind)), findsWidgets);
    expect(find.byIcon(objectIcon(fixture.objects.last.kind)), findsWidgets);
  });

  testWidgets('occupiable furniture renders under its guest', (tester) async {
    final occupiable = fixture.objects.firstWhere((o) => o.occupiable);
    final guest = fixture.suspects.first.id;
    await pumpBoard(
        tester, placed: {guest: occupiable.pos}, xMarks: {});

    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byIcon(objectIcon(occupiable.kind)), findsWidgets);
  });

  testWidgets('blocking furniture appears in semantics as unoccupiable',
      (tester) async {
    final blocking = fixture.objects.firstWhere((o) => !o.occupiable);
    await pumpBoard(tester, placed: {}, xMarks: {});
    final cellKey = 'cell_${blocking.pos.row}_${blocking.pos.col}';
    final semantics = tester.getSemantics(find.byKey(Key(cellKey)));
    expect(semantics.label, contains('cannot hold a guest'));
  });

  testWidgets('cells expose semantics labels', (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    final semantics = tester.getSemantics(find.byKey(const Key('cell_0_0')));
    expect(semantics.label, contains('Row 0'));
    expect(semantics.label, contains('column 0'));
  });

  testWidgets('no overflow at 2x text scale on a small screen', (tester) async {
    await pumpBoard(tester,
        placed: fixture.solution, xMarks: {}, textScale: 2.0);
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    expect(boardRect.width, lessThanOrEqualTo(320));
    expect(boardRect.height, lessThanOrEqualTo(569));
    expect(tester.takeException(), isNull);
  });
}
