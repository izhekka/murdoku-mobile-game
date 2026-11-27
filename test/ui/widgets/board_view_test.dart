import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/core/skins.dart';
import 'package:murdoku/domain/generator/case_factory.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/ui/widgets/avatar.dart';
import 'package:murdoku/ui/widgets/board_view.dart';
import 'package:murdoku/ui/widgets/item_sprite.dart';

final CaseData fixture = generateCase(difficulty: Difficulty.easy, seed: 3);

Widget wrap(Widget child, {double textScale = 1.0, SkinTokens? tokens}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: tokens == null
                ? child
                : SkinScope(tokens: tokens, child: child),
          ),
        ),
      ),
    );

Future<void> pumpBoard(
  WidgetTester tester, {
  CaseData? boardCase,
  required Map<String, Pos> placed,
  required Set<Pos> xMarks,
  String? selected,
  double textScale = 1.0,
  SkinTokens? tokens,
  void Function(Pos)? onCellTap,
  void Function(Pos)? onCellDrag,
  Size? view,
}) async {
  tester.view.physicalSize = view ?? const Size(320, 569);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    wrap(
      BoardView(
        caseData: boardCase ?? fixture,
        placed: placed,
        xMarks: xMarks,
        selectedSuspectId: selected,
        onCellTap: onCellTap ?? (_) {},
        onCellDrag: onCellDrag ?? (_) {},
      ),
      textScale: textScale,
      tokens: tokens,
    ),
  );
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

/// Grid position shorthand for the tracer fixtures.
Pos _p(int row, int col) => (row: row, col: col);

/// The badge anchor cell of the [i]-th fixture room: the board's own rule
/// (top-left-most cell that is not the victim).
Pos roomAnchor(int i) {
  final cells = [...fixture.rooms[i].cells]
    ..sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
  return cells.firstWhere((c) => c != fixture.victimPos);
}

/// A minimal classic case: a real-shaped partition with an unoccupiable item
/// sitting on room r0's badge anchor cell, so the badge-vs-item stacking is
/// exercised.
CaseData _badgeAnchorCase() {
  const g = 5;
  final rooms = _roomsFor(g, {
    'r0': [_p(0, 0), _p(0, 1), _p(0, 2), _p(1, 0), _p(1, 1)],
    'r1': [_p(0, 3), _p(0, 4), _p(1, 2), _p(1, 3), _p(1, 4)],
    'r2': [_p(2, 0), _p(2, 1), _p(2, 2), _p(2, 3), _p(2, 4)],
    'r3': [_p(3, 0), _p(3, 1), _p(3, 2)],
    // The victim's room always keeps a non-victim cell for the badge anchors.
    'rv': [
      _p(3, 3),
      _p(3, 4),
      _p(4, 0),
      _p(4, 1),
      _p(4, 2),
      _p(4, 3),
      _p(4, 4),
    ],
  });
  return CaseData(
    seed: 90,
    difficulty: Difficulty.easy,
    rooms: rooms,
    objects: [ObjectDef(id: 'o0', kind: ObjectKind.piano, pos: _p(0, 0))],
    suspects: [for (var i = 0; i < g; i++) Suspect(id: 's$i', name: 'S$i')],
    victimPos: _p(4, 4),
    murdererId: 's0',
    clues: const [],
    solution: {'s0': _p(1, 0)},
  );
}

/// Board room tiling: [layout]'s rooms plus filler rooms covering every
/// other cell of the G×G board, split into scan-order chunks so the list
/// carries EXACTLY [g] rooms — `CaseData.gridSize` derives from
/// `rooms.length` (issue 93), so a rendered case must be tiled with
/// exactly g rooms. Same-room/boundary logic only needs a fully tiled
/// board; which filler room a boundary cell belongs to is irrelevant
/// (every non-[id] neighbor is a boundary either way).
List<RoomDef> _roomsFor(int g, Map<String, List<Pos>> layout) {
  final named = layout.values.expand((cells) => cells).toSet();
  final rooms = [
    for (final entry in layout.entries)
      RoomDef(id: entry.key, name: entry.key, cells: entry.value),
  ];
  final rest = [
    for (var row = 0; row < g; row++)
      for (var col = 0; col < g; col++)
        if (!named.contains(_p(row, col))) _p(row, col),
  ];
  final fillerRooms = g - rooms.length;
  // Layouts that already fill every cell, or that tile with g+ named rooms
  // (the badge-anchor fixture), need no filler room at all; the tracer
  // battery passes g explicitly and may leave fewer filler cells than
  // filler-room slots — one combined filler room covers those. The render
  // path (g-rooms-or-fewer is never pumped) always hits the chunked case.
  if (rest.isEmpty || fillerRooms <= 0) return rooms;
  if (rest.length <= fillerRooms) {
    rooms.add(RoomDef(id: 'f0', name: 'filler', cells: rest));
    return rooms;
  }
  final perChunk = rest.length ~/ fillerRooms;
  var taken = 0;
  for (var i = 0; i < fillerRooms; i++) {
    final size = i == fillerRooms - 1 ? rest.length - taken : perChunk;
    rooms.add(
      RoomDef(
        id: 'f$i',
        name: 'filler',
        cells: rest.sublist(taken, taken + size),
      ),
    );
    taken += size;
  }
  return rooms;
}

/// The room's boundary edges, recomputed independently from the definition:
/// an edge exists per cell side whose neighbor is off-board or another
/// room. Each edge is (startVertex, direction) in grid vertex space:
/// north starts at (r,c) going E, east at (r,c+1) going S, south at
/// (r+1,c+1) going W, west at (r+1,c) going N.
Set<(Pos, Pos)> _expectedBoundary(List<RoomDef> rooms, int g, String id) {
  final room = rooms.firstWhere((r) => r.id == id);
  String? roomAt(Pos p) => p.row < 0 || p.col < 0 || p.row >= g || p.col >= g
      ? null
      : roomOf(rooms, p);
  final edges = <(Pos, Pos)>{};
  for (final cell in room.cells) {
    const sides = [
      (
        start: (row: 0, col: 0),
        dir: (row: 0, col: 1),
        across: (row: -1, col: 0),
      ),
      (
        start: (row: 0, col: 1),
        dir: (row: 1, col: 0),
        across: (row: 0, col: 1),
      ),
      (
        start: (row: 1, col: 1),
        dir: (row: 0, col: -1),
        across: (row: 1, col: 0),
      ),
      (
        start: (row: 1, col: 0),
        dir: (row: -1, col: 0),
        across: (row: 0, col: -1),
      ),
    ];
    for (final (start: s, dir: d, across: a) in sides) {
      final across = roomAt(_p(cell.row + a.row, cell.col + a.col));
      if (across != room.id) {
        edges.add((_p(cell.row + s.row, cell.col + s.col), d));
      }
    }
  }
  return edges;
}

/// The traced loop's (vertex, direction) edge sequence derived stepwise.
Set<(Pos, Pos)> _loopEdges(List<Pos> loop) => {
  for (var i = 0; i < loop.length; i++)
    (
      loop[i],
      _p(
        loop[(i + 1) % loop.length].row - loop[i].row,
        loop[(i + 1) % loop.length].col - loop[i].col,
      ),
    ),
};

/// Asserts [traceRoomOutline] produces exactly one closed loop that uses
/// every boundary edge exactly once for [id] — the wall-completeness shape
/// of the tracer battery (issue 82).
void _expectTrace(List<RoomDef> rooms, int g, String id) {
  final expected = _expectedBoundary(rooms, g, id);
  final loop = traceRoomOutline(rooms, g, id);
  expect(loop, isNotNull, reason: 'room $id must trace');
  final edges = _loopEdges(loop!);
  expect(
    edges.length,
    expected.length,
    reason: 'room $id: no reuse, nothing orphaned',
  );
  expect(edges, expected, reason: 'room $id: walls exactly on the boundary');
}

/// True when [small] sits inside [outer] (edges may touch).
bool _rectHolds(Rect outer, Rect small) =>
    outer.left <= small.left &&
    outer.top <= small.top &&
    outer.right >= small.right &&
    outer.bottom >= small.bottom;

/// Asserts every board sprite sits inside its cell minus the mortar band
/// (issue 82); [clamped] additionally expects the tiny-board shrink path.
void _expectSpritesInsideInner(WidgetTester tester, {required bool clamped}) {
  final boardRect = tester.getRect(find.byKey(const Key('board_view')));
  final cell = boardRect.width / fixture.gridSize;
  final band = stickerTokens.roomLineWidth / 2;

  final victimRect = tester.getRect(
    find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/items/victim.png',
    ),
  );
  final victimCell = Rect.fromLTWH(
    boardRect.left + fixture.victimPos.col * cell,
    boardRect.top + fixture.victimPos.row * cell,
    cell,
    cell,
  );
  expect(
    _rectHolds(victimCell.deflate(band), victimRect),
    isTrue,
    reason: 'victim sprite inside its cell minus the mortar band',
  );
  if (clamped) {
    expect(
      victimRect.width,
      lessThan(40),
      reason: 'the victim sprite shrinks below its 40px cap on a tiny board',
    );
  }

  for (final sprite in tester.widgetList<ItemSprite>(find.byType(ItemSprite))) {
    final rect = tester.getRect(find.byWidget(sprite));
    final center = rect.center;
    final cellRect = Rect.fromLTWH(
      boardRect.left +
          ((center.dx - boardRect.left) / cell).floorToDouble() * cell,
      boardRect.top +
          ((center.dy - boardRect.top) / cell).floorToDouble() * cell,
      cell,
      cell,
    );
    expect(
      _rectHolds(cellRect.deflate(band), rect),
      isTrue,
      reason: 'furniture sprite inside its cell minus the mortar band',
    );
  }
}

/// True when [child] is the wall pass over the cells: the board-scoped
/// Positioned wrapping the ClipRect around the (tap-transparent) wall
/// CustomPaint.
bool _wallPassChild(Widget child) {
  if (child is! Positioned) return false;
  final clip = child.child;
  if (clip is! ClipRect) return false;
  final paint = clip.child;
  return paint is IgnorePointer &&
      paint.child is CustomPaint &&
      (paint.child as CustomPaint).painter is SkinRoomWallPainter;
}

void main() {
  test('tracer battery: every room shape closes with exact boundary coverage '
      '(issue 82)', () {
    final cases = <String, (int, Map<String, List<Pos>>)>{
      'single cell': (
        4,
        {
          'r0': [_p(1, 1)],
        },
      ),
      'straight run': (
        4,
        {
          'r0': [_p(1, 0), _p(1, 1), _p(1, 2)],
        },
      ),
      'L': (
        3,
        {
          'r0': [_p(0, 0), _p(1, 0), _p(1, 1)],
        },
      ),
      'T': (
        3,
        {
          'r0': [_p(0, 0), _p(0, 1), _p(0, 2), _p(1, 1)],
        },
      ),
      'plus': (
        3,
        {
          'r0': [_p(0, 1), _p(1, 0), _p(1, 1), _p(1, 2), _p(2, 1)],
        },
      ),
      'S': (
        3,
        {
          'r0': [_p(0, 1), _p(0, 2), _p(1, 0), _p(1, 1)],
        },
      ),
      'full board': (
        4,
        {
          'r0': [
            for (var row = 0; row < 4; row++)
              for (var col = 0; col < 4; col++) _p(row, col),
          ],
        },
      ),
      // Diagonal pinch: the room touches itself at vertex (2,2) while
      // staying orthogonally connected — the right-turn priority must keep
      // the walk on one clean loop (the tracer's reason for that rule).
      'pinch': (
        5,
        {
          'r0': [
            _p(1, 1), _p(1, 0), _p(2, 0), //
            _p(3, 0), _p(3, 1), _p(3, 2), _p(2, 2),
          ],
        },
      ),
    };
    cases.forEach((name, shape) {
      final (g, layout) = shape;
      _expectTrace(_roomsFor(g, layout), g, 'r0');
    });
  });

  test('tracer fallback: donut ring and diagonal-only pieces return null '
      '(issue 82)', () {
    // Donut: 3×3 ring in a 5×5 board — the ring is one room but cannot be
    // traced as one clean loop (hole at (1,1) is a filler room).
    final donut = _roomsFor(5, {
      'r0': [
        _p(0, 0), _p(0, 1), _p(0, 2), //
        _p(1, 0), _p(1, 2), //
        _p(2, 0), _p(2, 1), _p(2, 2),
      ],
    });
    expect(
      traceRoomOutline(donut, 5, 'r0'),
      isNull,
      reason: 'a holed room falls back to the legacy path',
    );

    // Two pieces sharing only a corner: never one clean closure.
    final diagonal = _roomsFor(3, {
      'r0': [_p(0, 0), _p(1, 1)],
    });
    expect(traceRoomOutline(diagonal, 3, 'r0'), isNull);
  });

  test('tracer: every generated fixture room traces with exact coverage '
      '(issue 82)', () {
    for (final room in fixture.rooms) {
      _expectTrace(fixture.rooms, fixture.gridSize, room.id);
    }
  });

  testWidgets('taps report the correct cell position', (tester) async {
    Pos? tapped;
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      onCellTap: (p) => tapped = p,
    );

    await tester.tapAt(cellCenter(tester, 2, 3));
    expect(tapped, (row: 2, col: 3));

    await tester.tapAt(cellCenter(tester, 0, 0));
    expect(tapped, (row: 0, col: 0));
  });

  testWidgets('drag reports cells along the way', (tester) async {
    final dragged = <Pos>[];
    await pumpBoard(tester, placed: {}, xMarks: {}, onCellDrag: dragged.add);

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

  testWidgets('renders avatars for placed suspects and X marks', (
    tester,
  ) async {
    final placed = {
      's0': fixture.solution['s0']!,
      's2': fixture.solution['s2']!,
    };
    final xMarks = {fixture.solution['s4']!, fixture.solution['s3']!};
    await pumpBoard(tester, placed: placed, xMarks: xMarks);

    expect(find.byType(Avatar), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('victim cell is rendered with a chalk-outline sprite', (
    tester,
  ) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    expect(find.byKey(const Key('victim_cell')), findsOneWidget);
    final victimImage = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/items/victim.png',
    );
    expect(
      victimImage,
      findsOneWidget,
      reason: 'the victim is a graphic, not a letter',
    );
    expect(find.text('V'), findsNothing);
  });

  testWidgets('selected suspect gets a highlight ring', (tester) async {
    final placed = {'s0': fixture.solution['s0']!};
    await pumpBoard(tester, placed: placed, xMarks: {}, selected: 's0');
    final selectedAvatars = find.byWidgetPredicate(
      (w) => w is Avatar && w.selected,
    );
    expect(selectedAvatars, findsOneWidget);
  });

  testWidgets('objects render with icons', (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    // Every furniture cell renders its sprite (kinds may repeat across
    // cells, so match counts exactly against the furniture list).
    expect(find.byType(ItemSprite), findsNWidgets(fixture.objects.length));
  });

  testWidgets('occupiable furniture renders under its guest', (tester) async {
    final occupiable = fixture.objects.firstWhere((o) => o.occupiable);
    final guest = fixture.suspects.first.id;
    await pumpBoard(tester, placed: {guest: occupiable.pos}, xMarks: {});

    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byType(ItemSprite), findsWidgets);
  });

  testWidgets('room number badges render on each room anchor cell', (
    tester,
  ) async {
    await pumpBoard(tester, placed: {}, xMarks: {});
    for (var i = 0; i < fixture.rooms.length; i++) {
      // Issue 90: the badge layer renders at board level, one positioned
      // slot per anchor cell, no longer inside the cell's own stack.
      final anchor = roomAnchor(i);
      expect(
        find.descendant(
          of: find.byKey(Key('room_badge_${anchor.row}_${anchor.col}')),
          matching: find.text('${i + 1}'),
        ),
        findsOneWidget,
        reason: 'room ${fixture.rooms[i].id} badge ${i + 1} on its anchor cell',
      );
      expect(
        find.descendant(
          of: find.byKey(Key('cell_${anchor.row}_${anchor.col}')),
          matching: find.text('${i + 1}'),
        ),
        findsNothing,
        reason: 'the badge no longer hides inside the guest content stack',
      );
    }
  });

  testWidgets('an item in a badge anchor cell leaves the number visible on '
      'classic (issue 90)', (tester) async {
    await pumpBoard(
      tester,
      boardCase: _badgeAnchorCase(),
      placed: {},
      xMarks: {},
    );

    // The number is rendered at board level, above the cell that carries the
    // item sprite (the badge layer is a later child of the board Stack).
    expect(
      find.byKey(const Key('room_badge_0_0')),
      findsOneWidget,
      reason: 'room r0 badge slot on its anchor cell (0, 0)',
    );
    expect(find.text('1'), findsOneWidget);
    final stack = tester.widget<Stack>(
      find.byWidgetPredicate(
        (w) =>
            w is Stack &&
            w.children.any((c) => c is Positioned && c.child.key != null),
      ),
    );
    final cellIndex = stack.children.indexWhere(
      (c) => c is Positioned && c.child.key != null,
    );
    final badgeIndex = stack.children.indexWhere(
      (c) => c is Positioned && c.key == const Key('room_badge_0_0'),
    );
    expect(badgeIndex, greaterThanOrEqualTo(0));
    expect(
      badgeIndex,
      greaterThan(cellIndex),
      reason: 'the badge paints OVER the cell and its item sprite',
    );
  });

  testWidgets('classic room number badge paints the theme scheme colors '
      '(issue 90)', (tester) async {
    await pumpBoard(
      tester,
      boardCase: _badgeAnchorCase(),
      placed: {},
      xMarks: {},
    );

    // The classic badge resolves its colors through the app's own theme
    // (scheme param of the badge widget), never a hardcoded fill: probe the
    // scheme from the badge layer's own context and compare.
    final badgeContext = tester.element(
      find.byKey(const Key('room_badge_0_0')),
    );
    final scheme = Theme.of(badgeContext).colorScheme;
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('room_badge_0_0')),
        matching: find.byType(Container),
      ),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      scheme.primaryContainer,
      reason: 'the badge circle is the scheme primary container color',
    );
    final number = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('room_badge_0_0')),
        matching: find.text('1'),
      ),
    );
    expect(
      number.style!.color,
      scheme.onPrimaryContainer,
      reason: 'the badge number ink is the scheme onPrimaryContainer color',
    );
  });

  testWidgets('blocking furniture appears in semantics as unoccupiable', (
    tester,
  ) async {
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
    await pumpBoard(
      tester,
      placed: fixture.solution,
      xMarks: {},
      textScale: 2.0,
    );
    final boardRect = tester.getRect(find.byKey(const Key('board_view')));
    expect(boardRect.width, lessThanOrEqualTo(320));
    expect(boardRect.height, lessThanOrEqualTo(569));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cartoon skin paints solid rooms with boundary-only mortar '
      '(issue 23)', (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {}, tokens: stickerTokens);

    final painter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is SkinRoomPainter,
                  ),
                )
                .painter
            as SkinRoomPainter;
    expect(painter.mortarColor, stickerTokens.mortarColor);
    expect(painter.lineWidth, stickerTokens.roomLineWidth);
    expect(painter.radius, stickerTokens.roomRadius);
    expect(painter.roomCount, fixture.rooms.length);
    expect(painter.tints.first, stickerTokens.roomTints.first);
    expect(painter.tints[1], stickerTokens.roomTints[1]);

    // Cells carry no per-side borders any more: rooms paint beneath them.
    final cell = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('cell_0_0')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(cell.decoration, isNull);
  });

  testWidgets('cartoon skin renders the victim cell with stripes (issue 23)', (
    tester,
  ) async {
    await pumpBoard(tester, placed: {}, xMarks: {}, tokens: stickerTokens);
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SkinVictimStripePainter,
      ),
      findsOneWidget,
      reason: 'the victim cell is striped, matching the mockups',
    );
  });

  testWidgets('cartoon skin keeps taps working on every cell (issue 23)', (
    tester,
  ) async {
    Pos? tapped;
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
      onCellTap: (p) => tapped = p,
    );
    await tester.tapAt(cellCenter(tester, 2, 3));
    expect(tapped, (row: 2, col: 3));
  });

  testWidgets('walls trace exactly the room boundaries and render above cells '
      '(issue 82)', (tester) async {
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
      view: const Size(402, 874),
    );

    // Structural completeness: the fixture's rooms trace into loops whose
    // edges are exactly the room boundaries — no same-room interior strokes
    // and no orphan caps can exist on top of that structure.
    for (final room in fixture.rooms) {
      _expectTrace(fixture.rooms, fixture.gridSize, room.id);
    }

    // The wall pass is a painter above the cell layer, inside the board
    // clip, so strokes always read over sprites.
    final stack = tester.widget<Stack>(
      find.byWidgetPredicate(
        (w) => w is Stack && w.children.any(_wallPassChild),
      ),
    );
    final cellIndex = stack.children.indexWhere(
      (c) => c is Positioned && c.child.key != null,
    );
    final wallIndex = stack.children.indexWhere(_wallPassChild);
    expect(cellIndex, greaterThanOrEqualTo(0));
    expect(
      wallIndex,
      greaterThan(cellIndex),
      reason: 'walls stroke OVER cell content (sprites under the wall)',
    );

    // Issue 90: the badge layer is the board's topmost layer — a badge that
    // overlaps a wall stroke renders on top of it, on every skin.
    final anchor = roomAnchor(0);
    final badgeIndex = stack.children.indexWhere(
      (c) =>
          c is Positioned &&
          c.key == Key('room_badge_${anchor.row}_${anchor.col}'),
    );
    expect(badgeIndex, greaterThanOrEqualTo(0));
    expect(
      badgeIndex,
      greaterThan(wallIndex),
      reason: 'room number badges render above the wall pass',
    );
  });

  testWidgets('victim and furniture sprites stay inside the cell inner area '
      'at 402x874 (issue 82)', (tester) async {
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
      view: const Size(402, 874),
    );
    expect(tester.takeException(), isNull);
    _expectSpritesInsideInner(tester, clamped: false);
  });

  testWidgets('victim and furniture sprites stay inside at legacy 320x569 '
      '(issue 82)', (tester) async {
    await pumpBoard(tester, placed: {}, xMarks: {}, tokens: stickerTokens);
    expect(tester.takeException(), isNull);
    _expectSpritesInsideInner(tester, clamped: false);
  });

  testWidgets('sprites shrink below 40px on a tiny board (issue 82)', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
      view: const Size(200, 400),
    );
    expect(tester.takeException(), isNull);
    _expectSpritesInsideInner(tester, clamped: true);
  });

  testWidgets('a placed guest shrinks into the inner box on a tiny cartoon '
      'board (issue 82)', (tester) async {
    final guest = fixture.suspects.first.id;
    await pumpBoard(
      tester,
      placed: {guest: fixture.solution[guest]!},
      xMarks: {},
      tokens: stickerTokens,
      view: const Size(200, 400),
    );
    // cell 40: inner box = 40 - 2*(3.5+2) = 29, below the fixed 30px avatar.
    final avatarRect = tester.getRect(find.byType(Avatar).first);
    expect(
      avatarRect.width,
      closeTo(29, 0.01),
      reason:
          'the avatar shrinks like the sprites instead of rendering '
          'cropped by the inset clip',
    );
  });

  testWidgets('furniture shrinks into the inner box at 220x400 (issue 82)', (
    tester,
  ) async {
    await pumpBoard(
      tester,
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
      view: const Size(220, 400),
    );
    // cell 44: the 1.35x furniture image shrinks below its 37.8 cap to the
    // inner box (33), so the containment assertion discriminates the old
    // fixed-size painter too.
    expect(tester.takeException(), isNull);
    _expectSpritesInsideInner(tester, clamped: true);
    final spriteRect = tester.getRect(find.byType(ItemSprite).first);
    expect(
      spriteRect.width,
      closeTo(33, 0.01),
      reason: 'furniture image = 1.35 * (cell - 2*(lineWidth+2))/1.35 here',
    );
  });

  testWidgets('a holed room falls back to the legacy per-cell render without '
      'crashing (issue 82)', (tester) async {
    const g = 5;
    final rooms = _roomsFor(g, {
      // Ring pinned to the board's bottom-right corner so the legacy pass
      // also strokes its outer south/east edges; the hole at (3,3) stays a
      // filler cell.
      'r0': <Pos>[
        _p(2, 2), _p(2, 3), _p(2, 4), //
        _p(3, 2), _p(3, 4), //
        _p(4, 2), _p(4, 3), _p(4, 4),
      ],
      // The victim shares a two-cell room so the badge anchor resolves.
      'rv': <Pos>[_p(0, 0), _p(0, 1)],
    });
    await pumpBoard(
      tester,
      boardCase: CaseData(
        seed: 1,
        difficulty: Difficulty.easy,
        rooms: rooms,
        objects: const [],
        suspects: [for (var i = 0; i < g; i++) Suspect(id: 's$i', name: 'S$i')],
        victimPos: _p(0, 0),
        murdererId: 's0',
        clues: const [],
        solution: {'s0': _p(1, 0)},
      ),
      placed: {},
      xMarks: {},
      tokens: stickerTokens,
    );
    expect(tester.takeException(), isNull);
  });
}
