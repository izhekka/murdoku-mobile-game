import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';

Pos p(int row, int col) => (row: row, col: col);

/// 5x5 fixture with one clue per suspect (varied types, incl. negations).
final CaseData fixture = CaseData(
  seed: 1,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(id: 'r0', name: 'Hall', cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)]),
    RoomDef(id: 'r1', name: 'Library', cells: [p(0, 3), p(0, 4), p(1, 2), p(1, 3), p(1, 4)]),
    RoomDef(id: 'r2', name: 'Kitchen', cells: [p(2, 0), p(2, 1), p(2, 2), p(3, 0), p(3, 1)]),
    RoomDef(id: 'r3', name: 'Cellar', cells: [p(2, 3), p(2, 4), p(3, 2), p(3, 3), p(3, 4)]),
    RoomDef(id: 'r4', name: 'Study', cells: [p(4, 0), p(4, 1), p(4, 2), p(4, 3), p(4, 4)]),
  ],
  objects: [
    ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: p(0, 1)),
    ObjectDef(id: 'o1', kind: ObjectKind.clock, pos: p(4, 4)),
  ],
  suspects: [
    Suspect(id: 's0', name: 'Ash'),
    Suspect(id: 's1', name: 'Blair'),
    Suspect(id: 's2', name: 'Casey'),
    Suspect(id: 's3', name: 'Drew'),
    Suspect(id: 's4', name: 'Ellis'),
  ],
  victimPos: p(2, 2),
  murdererId: 's2',
  clues: [
    InRoom(suspectId: 's0', roomId: 'r0', negated: false),
    SameRow(suspectId: 's1', targetId: 'V', negated: true),
    SameCol(suspectId: 's2', targetId: 's4', negated: false),
    DirectionClue(
        suspectId: 's3', targetId: 'V', direction: Direction.south, negated: true),
    BesideObject(suspectId: 's4', objectId: 'o1', negated: false),
  ],
  solution: {
    's0': p(0, 0),
    's1': p(1, 4),
    's2': p(2, 1),
    's3': p(3, 3),
    's4': p(4, 2),
  },
);

/// Stateful harness so taps move the selection like the real game does.
class Harness extends StatefulWidget {
  const Harness({super.key, this.onSuspectTap});

  final void Function(String)? onSuspectTap;

  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  String? _selected = 's0';

  @override
  Widget build(BuildContext context) => MaterialApp(
        // The panel test pins English: it asserts exact en clue wording with
        // declension forms (see localization_test.dart for the ru grammar).
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SuspectPanel(
              caseData: fixture,
              placed: {'s2': fixture.solution['s2']!},
              selectedSuspectId: _selected,
              onSuspectTap: (id) {
                widget.onSuspectTap?.call(id);
                setState(() => _selected = _selected == id ? null : id);
              },
            ),
          ),
        ),
      );
}

Widget generatedWrap(
  CaseData c, {
  String? selectedSuspectId,
  void Function(String)? onSuspectTap,
}) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: SuspectPanel(
            caseData: c,
            placed: const {},
            selectedSuspectId: selectedSuspectId,
            onSuspectTap: onSuspectTap ?? (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('every suspect card shows its name and its clue sentences',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(Harness(onSuspectTap: (id) => tapped = id));
    await tester.pump();

    // The grid shows all cards at once; assert each name and exact en wording.
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Ash was in the Hall.'), findsOneWidget);
    expect(find.text('Blair'), findsOneWidget);
    expect(find.text('Blair was not on the same floor as the victim.'),
        findsOneWidget);
    expect(find.text('Casey'), findsOneWidget);
    expect(find.text('Casey was in the same corridor as Ellis.'),
        findsOneWidget);
    expect(find.text('Drew'), findsOneWidget);
    expect(find.text('Drew was not south of the victim.'), findsOneWidget);
    expect(find.text('Ellis'), findsOneWidget);
    expect(find.text('Ellis was in the same room as the Clock.'), findsOneWidget);

    // Placed suspect is marked.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tapping a card selects that suspect.
    await tester.tap(find.text('Drew'));
    expect(tapped, 's3');
  });

  testWidgets('suspects render as a 3x2 grid; no horizontal strip (UX-2)',
      (tester) async {
    final c = generateCase(difficulty: Difficulty.easy, seed: 3);
    await tester.pumpWidget(generatedWrap(c));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.physics, isA<NeverScrollableScrollPhysics>(),
        reason: '5 suspects fit the grid; no scrolling needed');
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3, reason: '3 columns');
    final childrenDelegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(childrenDelegate.children.length, 6,
        reason: '5 cards + 1 empty decorative slot = 6 slots (2 rows)');
    for (final s in c.suspects) {
      expect(find.text(s.name), findsOneWidget,
          reason: 'all 5 cards visible at once');
    }
    expect(find.byType(ListView), findsNothing,
        reason: 'the horizontally scrolling strip is gone');
  });

  testWidgets('clue text is uncapped on selected and unselected cards (UX-9)',
      (tester) async {
    await tester.pumpWidget(const Harness());
    await tester.pump();

    // Initially Ash (s0) is selected: uncapped clue text.
    final ashSelected =
        tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ashSelected.maxLines, isNull);

    // Unselected cards are uncapped too: the (taller) card height bounds
    // the text instead of a 2-line ellipsis (UX-9).
    final blair = tester
        .widget<Text>(find.text('Blair was not on the same floor as the victim.'));
    expect(blair.maxLines, isNull);
    expect(blair.overflow, isNull);

    // Tap Blair -> selection moves; Blair expands, Ash stays uncapped.
    await tester.tap(find.text('Blair'));
    await tester.pump();

    final blairSelected = tester
        .widget<Text>(find.text('Blair was not on the same floor as the victim.'));
    expect(blairSelected.maxLines, isNull);
    final ash = tester.widget<Text>(find.text('Ash was in the Hall.'));
    expect(ash.maxLines, isNull);
  });

  testWidgets('grid fills a pinned height; cards stretch taller (UX-9)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 412,
            height: 400,
            child: SuspectPanel(
              caseData: fixture,
              placed: const {},
              selectedSuspectId: null,
              onSuspectTap: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final gridRect = tester.getRect(find.byType(GridView));
    expect(gridRect.height, 400, reason: 'the grid fills the pinned slot');
    // Two rows split the 400px slot minus 8px padding and one 4px gutter;
    // each card's InkWell fills its tile minus the 4px card padding.
    final cardRect = tester.getRect(find.byType(InkWell).first);
    expect(cardRect.height, closeTo((400 - 2 * 4 - 4) / 2 - 2 * 4, 0.5),
        reason: 'cards stretch to fill the slot height');
  });

  testWidgets('each card is a semantic button labelled name + first clue (UX-2)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const Harness());
    await tester.pump();

    final node = tester.getSemantics(find.text('Ash'));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains('Ash was in the Hall.'));
    semantics.dispose();
  });
}
