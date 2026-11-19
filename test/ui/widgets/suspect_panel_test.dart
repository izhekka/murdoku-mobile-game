import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

Widget wrap({required void Function(String) onSuspectTap}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: SuspectPanel(
            caseData: fixture,
            placed: {'s2': fixture.solution['s2']!},
            selectedSuspectId: 's0',
            onSuspectTap: onSuspectTap,
          ),
        ),
      ),
    );

void main() {
  testWidgets('every suspect card shows its name and its clue sentences',
      (tester) async {
    String? tapped;
    await tester.pumpWidget(wrap(onSuspectTap: (id) => tapped = id));
    await tester.pump();

    // The strip is a lazy horizontal ListView: scroll card by card and
    // assert each card's name and exact clue wording as it appears.
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('Ash was in the Hall.'), findsOneWidget);
    expect(find.text('Blair'), findsOneWidget);
    expect(find.text('Blair was not on the same floor as the victim.'),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Casey'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Casey was in the same corridor as Ellis.'),
        findsOneWidget);

    await tester.scrollUntilVisible(find.text('Drew'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Drew was not south of the victim.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Ellis'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Ellis was beside the Clock.'), findsOneWidget);

    // Placed suspect is marked.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Tapping a card selects that suspect.
    await tester.tap(find.text('Drew'));
    expect(tapped, 's3');
  });
}
