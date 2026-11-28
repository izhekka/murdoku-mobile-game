import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/domain/deducer.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/domain/solver.dart';

/// Unit tests for the deduction engine (issue #106).
///
/// Fixed 3×3 fixture: rooms r0 = {(0,0),(0,1),(1,0)}, r1 = {(0,2),(1,1),
/// (1,2)}, r2 = {(2,0),(2,1),(2,2)}; suspects s0..s2; victim at (2,2).
/// `filter()` exposes the init + clue-filter fixpoint, so every filter rule
/// (six kinds × two polarities, victim-target unary vs suspect-target
/// relational) is asserted against hand-computed surviving cell sets.
void main() {
  Pos p(int row, int col) => (row: row, col: col);

  final rooms = [
    RoomDef(id: 'r0', name: 'R0', cells: [p(0, 0), p(0, 1), p(1, 0)]),
    RoomDef(id: 'r1', name: 'R1', cells: [p(0, 2), p(1, 1), p(1, 2)]),
    RoomDef(id: 'r2', name: 'R2', cells: [p(2, 0), p(2, 1), p(2, 2)]),
  ];

  /// Every cell minus the victim cell — the no-objects init candidate set.
  final all8 = {
    p(0, 0),
    p(0, 1),
    p(0, 2),
    p(1, 0),
    p(1, 1),
    p(1, 2),
    p(2, 0),
    p(2, 1),
  };

  Deducer deducer(List<Clue> clues, {List<ObjectDef> objects = const []}) =>
      Deducer(
        gridSize: 3,
        rooms: rooms,
        clues: clues,
        suspectIds: const ['s0', 's1', 's2'],
        victimPos: p(2, 2),
        objects: objects,
        tier: DeduceTier.probes,
      );

  Set<Pos> surviving(Map<String, Set<Pos>> f, String id) => f[id]!;

  group('unary clue filters (victim/room/object anchored)', () {
    test('InRoom positive keeps the room cells', () {
      final f = deducer([InRoom(suspectId: 's0', roomId: 'r1', negated: false)])
          .filter();
      expect(surviving(f, 's0'), {p(0, 2), p(1, 1), p(1, 2)});
    });

    test('InRoom negated removes the room cells', () {
      final f = deducer([InRoom(suspectId: 's0', roomId: 'r1', negated: true)])
          .filter();
      expect(surviving(f, 's0'), all8.difference({p(0, 2), p(1, 1), p(1, 2)}));
    });

    test('BesideObject positive keeps the item-room cells (ADR 0004)', () {
      final obj = ObjectDef(id: 'o0', kind: ObjectKind.table, pos: p(1, 0));
      final f = deducer(
        [BesideObject(suspectId: 's0', objectId: 'o0', negated: false)],
        objects: [obj],
      ).filter();
      // The room's blocking cell itself is gone from the init candidates.
      expect(surviving(f, 's0'), {p(0, 0), p(0, 1)});
    });

    test('BesideObject negated removes the item-room cells', () {
      final obj = ObjectDef(id: 'o0', kind: ObjectKind.table, pos: p(1, 0));
      final f = deducer(
        [BesideObject(suspectId: 's0', objectId: 'o0', negated: true)],
        objects: [obj],
      ).filter();
      expect(surviving(f, 's0'), all8.difference({p(0, 0), p(0, 1), p(1, 0)}));
    });

    test(
      'SameRow(victim) positive keeps the victim row minus the victim cell',
      () {
        final f = deducer([
          SameRow(suspectId: 's0', targetId: victimId, negated: false),
        ]).filter();
        expect(surviving(f, 's0'), {p(2, 0), p(2, 1)});
      },
    );

    test('SameRow(victim) negated removes the victim row', () {
      final f = deducer([
        SameRow(suspectId: 's0', targetId: victimId, negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(0, 2),
        p(1, 0),
        p(1, 1),
        p(1, 2),
      });
    });

    test(
      'SameCol(victim) positive keeps the victim column minus the victim',
      () {
        final f = deducer([
          SameCol(suspectId: 's0', targetId: victimId, negated: false),
        ]).filter();
        expect(surviving(f, 's0'), {p(0, 2), p(1, 2)});
      },
    );

    test('SameCol(victim) negated removes the victim column', () {
      final f = deducer([
        SameCol(suspectId: 's0', targetId: victimId, negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(1, 0),
        p(1, 1),
        p(2, 0),
        p(2, 1),
      });
    });

    test('Direction north(victim) positive keeps the rows above', () {
      final f = deducer([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.north,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(0, 2),
        p(1, 0),
        p(1, 1),
        p(1, 2),
      });
    });

    test('Direction north(victim) negated keeps row ≥ victim row', () {
      final f = deducer([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.north,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(2, 0), p(2, 1)});
    });

    test('Beside(victim) positive keeps Manhattan-1 neighbors', () {
      final f = deducer([
        Beside(suspectId: 's0', targetId: victimId, negated: false),
      ]).filter();
      expect(surviving(f, 's0'), {p(1, 2), p(2, 1)});
    });

    test('Beside(victim) negated removes the Manhattan-1 neighbors', () {
      final f = deducer([
        Beside(suspectId: 's0', targetId: victimId, negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(0, 2),
        p(1, 0),
        p(1, 1),
        p(2, 0),
      });
    });
  });

  group('relational clue filters (suspect target, arc-consistent)', () {
    /// s1 pinned to the single cell (2,1): west-of-victim ∩ beside-victim.
    List<Clue> pinS1To21() => [
      DirectionClue(
        suspectId: 's1',
        targetId: victimId,
        direction: Direction.west,
        negated: false,
      ),
      Beside(suspectId: 's1', targetId: victimId, negated: false),
    ];

    test('SameRow positive intersects both guests into the shared row', () {
      final f = deducer([
        ...pinS1To21(),
        SameRow(suspectId: 's0', targetId: 's1', negated: false),
      ]).filter();
      expect(surviving(f, 's0'), {p(2, 0), p(2, 1)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('SameRow negated removes a single-row target row', () {
      final f = deducer([
        ...pinS1To21(),
        SameRow(suspectId: 's0', targetId: 's1', negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(0, 2),
        p(1, 0),
        p(1, 1),
        p(1, 2),
      });
      // Target keeps its candidates: s0 spans ≥ 2 rows, so nothing to remove.
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('SameRow negated is a no-op when the target spans several rows', () {
      // s1 restricted to r1 (rows 0 and 1): no single row to subtract, so
      // arc-consistent filtering removes nothing anywhere.
      final f = deducer([
        InRoom(suspectId: 's1', roomId: 'r1', negated: false),
        SameRow(suspectId: 's0', targetId: 's1', negated: true),
      ]).filter();
      expect(surviving(f, 's0'), all8);
      expect(surviving(f, 's1'), {p(0, 2), p(1, 1), p(1, 2)});
    });

    test('SameCol positive intersects both guests into the shared column', () {
      final f = deducer([
        ...pinS1To21(),
        SameCol(suspectId: 's0', targetId: 's1', negated: false),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 1), p(1, 1), p(2, 1)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('SameCol negated removes a single-column target column', () {
      final f = deducer([
        ...pinS1To21(),
        SameCol(suspectId: 's0', targetId: 's1', negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 0), p(0, 2), p(1, 0), p(1, 2), p(2, 0)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test(
      'Direction north positive keeps rows strictly above the target span',
      () {
        final f = deducer([
          ...pinS1To21(),
          DirectionClue(
            suspectId: 's0',
            targetId: 's1',
            direction: Direction.north,
            negated: false,
          ),
        ]).filter();
        expect(surviving(f, 's0'), {
          p(0, 0),
          p(0, 1),
          p(0, 2),
          p(1, 0),
          p(1, 1),
          p(1, 2),
        });
        expect(surviving(f, 's1'), {p(2, 1)});
      },
    );

    test('Direction north negated keeps rows at or below the target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.north,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(2, 0), p(2, 1)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('Direction west positive keeps columns left of the target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.west,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 0), p(1, 0), p(2, 0)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('Direction west negated keeps columns at or right of the target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.west,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 1), p(0, 2), p(1, 1), p(1, 2), p(2, 1)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('Direction east positive keeps columns right of the target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.east,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 2), p(1, 2)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('Direction east negated keeps columns at or left of the target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.east,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 0),
        p(0, 1),
        p(1, 0),
        p(1, 1),
        p(2, 0),
        p(2, 1),
      });
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test(
      'Direction positive cascades over a multi-row target span (arc fixpoint)',
      () {
        // s1 spans rows {0,1} in column 2; s0 must sit strictly above row 1,
        // which in turn drops s1's row-0 support.
        final f = deducer([
          SameCol(suspectId: 's1', targetId: victimId, negated: false),
          InRoom(suspectId: 's1', roomId: 'r1', negated: false),
          DirectionClue(
            suspectId: 's0',
            targetId: 's1',
            direction: Direction.north,
            negated: false,
          ),
        ]).filter();
        expect(surviving(f, 's0'), {p(0, 0), p(0, 1), p(0, 2)});
        expect(surviving(f, 's1'), {p(1, 2)});
      },
    );

    test('Beside positive keeps only cells adjacent to the pinned target', () {
      final f = deducer([
        ...pinS1To21(),
        Beside(suspectId: 's0', targetId: 's1', negated: false),
      ]).filter();
      expect(surviving(f, 's0'), {p(1, 1), p(2, 0)});
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test(
      'Beside negated removes only cells adjacent to every target candidate',
      () {
        final f = deducer([
          ...pinS1To21(),
          Beside(suspectId: 's0', targetId: 's1', negated: true),
        ]).filter();
        // Neighbors of (2,1) are {(1,1),(2,0),(2,2)} — the victim cell is
        // already gone at init, so exactly {(1,1),(2,0)} lose support.
        expect(surviving(f, 's0'), {
          p(0, 0),
          p(0, 1),
          p(0, 2),
          p(1, 0),
          p(1, 2),
          p(2, 1),
        });
        expect(surviving(f, 's1'), {p(2, 1)});
      },
    );

    test('Direction south positive over a pinned target kills the case', () {
      // s0 must sit strictly below row 2 — nothing left.
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.south,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), isEmpty);
      expect(surviving(f, 's1'), isEmpty);
    });

    test('Direction south negated is a no-op over the bottom target', () {
      final f = deducer([
        ...pinS1To21(),
        DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.south,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), all8);
      expect(surviving(f, 's1'), {p(2, 1)});
    });

    test('SameRow negated also removes the suspect-side single row', () {
      // s0 pinned to (2,1) on the SUSPECT side: the negated SameRow(s1, s0)
      // removes row 2 from s1 — the symmetric half of the negated rule.
      final f = deducer([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.west,
          negated: false,
        ),
        Beside(suspectId: 's0', targetId: victimId, negated: false),
        SameRow(suspectId: 's1', targetId: 's0', negated: true),
      ]).filter();
      expect(surviving(f, 's0'), {p(2, 1)});
      expect(surviving(f, 's1'), {
        p(0, 0),
        p(0, 1),
        p(0, 2),
        p(1, 0),
        p(1, 1),
        p(1, 2),
      });
    });

    test('a relational clue on an emptied mask is a no-op (guard path)', () {
      // Contradictory room pins empty s0 mid-pass; the following direction
      // clue then runs against an empty mask and must not crash.
      final f = deducer([
        const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
        const InRoom(suspectId: 's0', roomId: 'r1', negated: false),
        const DirectionClue(
          suspectId: 's0',
          targetId: 's1',
          direction: Direction.north,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), isEmpty);
      expect(surviving(f, 's1'), all8);
    });
  });

  group('unary victim strips from the top-left victim', () {
    // Victim at (0,0): south/east strips are the populated halves here.
    Deducer deducerTopLeft(List<Clue> clues) => Deducer(
      gridSize: 3,
      rooms: rooms,
      clues: clues,
      suspectIds: const ['s0', 's1', 's2'],
      victimPos: p(0, 0),
      objects: const [],
      tier: DeduceTier.probes,
    );

    test('Direction south(victim) positive keeps the rows below', () {
      final f = deducerTopLeft([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.south,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(1, 0),
        p(1, 1),
        p(1, 2),
        p(2, 0),
        p(2, 1),
        p(2, 2),
      });
    });

    test('Direction south(victim) negated keeps the victim row', () {
      final f = deducerTopLeft([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.south,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(0, 1), p(0, 2)});
    });

    test('Direction east(victim) positive keeps the columns right', () {
      final f = deducerTopLeft([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.east,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {
        p(0, 1),
        p(0, 2),
        p(1, 1),
        p(1, 2),
        p(2, 1),
        p(2, 2),
      });
    });

    test('Direction east(victim) negated keeps the victim column', () {
      final f = deducerTopLeft([
        DirectionClue(
          suspectId: 's0',
          targetId: victimId,
          direction: Direction.east,
          negated: true,
        ),
      ]).filter();
      expect(surviving(f, 's0'), {p(1, 0), p(2, 0)});
    });
  });

  group('9×9 board (high word of the candidate bitmask)', () {
    // Cells 63..80 live in the mask's high word — only a 9×9 board reaches
    // them (the #98 sizing). Row rooms make row 7 exactly cells 63..71.
    Pos p9(int row, int col) => (row: row, col: col);
    final rooms9 = [
      for (var row = 0; row < 9; row++)
        RoomDef(
          id: 'r$row',
          name: 'R$row',
          cells: [for (var col = 0; col < 9; col++) p9(row, col)],
        ),
    ];
    final allButVictim = {
      for (var row = 0; row < 9; row++)
        for (var col = 0; col < 9; col++) p9(row, col),
    }..remove(p9(0, 0));
    final row7 = {for (var col = 0; col < 9; col++) p9(7, col)};

    Deducer deducer9(List<Clue> clues) => Deducer(
      gridSize: 9,
      rooms: rooms9,
      clues: clues,
      suspectIds: [for (var i = 0; i < 9; i++) 's$i'],
      victimPos: p9(0, 0),
      objects: const [],
      tier: DeduceTier.probes,
    );

    test('InRoom into row 7 keeps only high-word cells', () {
      final f = deducer9([
        InRoom(suspectId: 's1', roomId: 'r7', negated: false),
      ]).filter();
      expect(surviving(f, 's1'), row7);
    });

    test('InRoom negated out of row 7 clears high-word cells', () {
      final f = deducer9([InRoom(suspectId: 's2', roomId: 'r7', negated: true)])
          .filter();
      expect(surviving(f, 's2'), allButVictim.difference(row7));
    });

    test('Direction south of the top-left victim spans both words', () {
      final f = deducer9([
        DirectionClue(
          suspectId: 's3',
          targetId: victimId,
          direction: Direction.south,
          negated: false,
        ),
      ]).filter();
      expect(surviving(f, 's3'), allButVictim.where((c) => c.row >= 1).toSet());
    });
  });

  group('tier selection', () {
    test('easy maps to tier 1 (singles), standard/hard to tier 3 (probes)', () {
      expect(deduceTierFor(Difficulty.easy), DeduceTier.singles);
      expect(deduceTierFor(Difficulty.standard), DeduceTier.probes);
      expect(deduceTierFor(Difficulty.hard), DeduceTier.probes);
    });
  });

  group('init candidates', () {
    test(
      'blocking cells and the victim cell are removed; occupiable cells stay',
      () {
        final objects = [
          ObjectDef(
            id: 'oChair',
            kind: ObjectKind.chair,
            pos: p(2, 0),
            occupiable: true,
          ),
          ObjectDef(id: 'oTable', kind: ObjectKind.table, pos: p(2, 1)),
        ];
        final f = deducer(const [], objects: objects).filter();
        expect(surviving(f, 's0'), all8.difference({p(2, 1)}));
      },
    );
  });

  group('tier-1 solve (propagation + naked/hidden singles)', () {
    // Hand-checked tier-1 chain, solution {s0:(0,0), s1:(1,2), s2:(2,1)}:
    // s2's room∩beside pin places it naked; the south direction then holds
    // s1 to row ≥ s0's span and column 0 / column 2 leave only s0 / s1
    // (hidden singles) — both placed as hidden singles.
    final chain = deducer([
      const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
      const InRoom(suspectId: 's1', roomId: 'r1', negated: false),
      const InRoom(suspectId: 's2', roomId: 'r2', negated: false),
      const Beside(suspectId: 's2', targetId: victimId, negated: false),
      const DirectionClue(
        suspectId: 's1',
        targetId: 's0',
        direction: Direction.south,
        negated: false,
      ),
    ]);

    test('returns the ordered placement trace with the right rules', () {
      expect(chain.solve(), [
        DeduceStep(guestId: 's2', cell: p(2, 1), rule: DeduceRule.nakedSingle),
        DeduceStep(guestId: 's0', cell: p(0, 0), rule: DeduceRule.hiddenSingle),
        DeduceStep(guestId: 's1', cell: p(1, 2), rule: DeduceRule.hiddenSingle),
      ]);
    });

    test(
      'structural propagation pins a guest only after others are placed',
      () {
        // Solution {s0:(2,1), s1:(0,0), s2:(1,2)}: s0 and s2 are room∩beside
        // pins (naked); s1's (0,0) falls out ONLY after both placements
        // structurally remove column 1 (kills (0,1)) and row 1 (kills (1,0)).
        final structural = deducer([
          const InRoom(suspectId: 's0', roomId: 'r2', negated: false),
          const InRoom(suspectId: 's1', roomId: 'r0', negated: false),
          const InRoom(suspectId: 's2', roomId: 'r1', negated: false),
          const Beside(suspectId: 's0', targetId: victimId, negated: false),
          const Beside(suspectId: 's2', targetId: victimId, negated: false),
        ]);
        final trace = structural.solve();
        expect(
          [
            for (final step in trace ?? <DeduceStep>[])
              (step.guestId, step.cell),
          ],
          [('s0', p(2, 1)), ('s2', p(1, 2)), ('s1', p(0, 0))],
        );
      },
    );

    test('a stalled case returns null (tier 1)', () {
      final stalled = deducer([
        const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
      ]);
      expect(stalled.solve(), isNull);
    });
  });

  group('tier-3 uniqueness probes', () {
    // Unique-but-propagation-stalled fixture (searched 2026-11-28): the
    // shipped clue cards pin every guest only via contradiction probes —
    // tier 1 stalls, tier 3 must solve. Solution {s0:(0,0), s1:(1,1),
    // s2:(2,2)}, victim (0,1).
    final clues = [
      const DirectionClue(
        suspectId: 's1',
        targetId: 's2',
        direction: Direction.north,
        negated: false,
      ),
      const SameRow(suspectId: 's2', targetId: 's0', negated: true),
      const DirectionClue(
        suspectId: 's1',
        targetId: 's0',
        direction: Direction.west,
        negated: true,
      ),
      const DirectionClue(
        suspectId: 's2',
        targetId: 's1',
        direction: Direction.west,
        negated: true,
      ),
      const Beside(suspectId: 's1', targetId: 's2', negated: true),
      const Beside(suspectId: 's2', targetId: 's0', negated: true),
      const InRoom(suspectId: 's0', roomId: 'r2', negated: true),
      const DirectionClue(
        suspectId: 's1',
        targetId: victimId,
        direction: Direction.south,
        negated: false,
      ),
      const DirectionClue(
        suspectId: 's2',
        targetId: 's0',
        direction: Direction.south,
        negated: false,
      ),
      const DirectionClue(
        suspectId: 's0',
        targetId: victimId,
        direction: Direction.east,
        negated: true,
      ),
      const InRoom(suspectId: 's1', roomId: 'r1', negated: false),
    ];
    Deducer fixture(DeduceTier tier) => Deducer(
      gridSize: 3,
      rooms: rooms,
      clues: clues,
      suspectIds: const ['s0', 's1', 's2'],
      victimPos: p(0, 1),
      objects: const [],
      tier: tier,
    );

    test('tier 1 stalls on the fixture', () {
      expect(fixture(DeduceTier.singles).solve(), isNull);
    });

    test('tier 3 solves it, placements equal the brute-force solution', () {
      final trace = fixture(DeduceTier.probes).solve();
      expect(trace, isNotNull);
      final placed = {for (final s in trace!) s.guestId: s.cell};
      expect(placed, {'s0': p(0, 0), 's1': p(1, 1), 's2': p(2, 2)});
    });

    test('solve() is deterministic (same input → same trace)', () {
      final a = fixture(DeduceTier.probes).solve();
      final b = fixture(DeduceTier.probes).solve();
      expect(a, b);
    });

    test('fixture is unique — countSolutions cross-check', () {
      expect(
        countSolutions(
          gridSize: 3,
          rooms: rooms,
          clues: clues,
          suspectIds: const ['s0', 's1', 's2'],
          victimPos: p(0, 1),
          objects: const [],
        ),
        1,
      );
    });

    test('an empty candidate mask kills the case (contradiction form 1)', () {
      // Two exclusive room pins empty s0 outright.
      final dead = deducer([
        const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
        const InRoom(suspectId: 's0', roomId: 'r1', negated: false),
      ]);
      expect(dead.solve(), isNull);
    });

    test('an unfilled room no guest can take kills the case (form 2)', () {
      // s0 and s1 are both pinned to r0, and row 2 pins s2 — room r1 is
      // left with no possible guest, which the dead-check must catch.
      final dead = deducer([
        const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
        const InRoom(suspectId: 's1', roomId: 'r0', negated: false),
      ]);
      expect(dead.solve(), isNull);
    });
  });

  group('object-cell clue filters (issue 111)', () {
    final chair = ObjectDef(
      id: 'o0',
      kind: ObjectKind.chair,
      pos: p(0, 1),
      occupiable: true,
    );

    test('OnObject positive keeps only the item cell; negated removes it', () {
      final f = deducer(
        [OnObject(suspectId: 's0', objectId: 'o0', negated: false)],
        objects: [chair],
      ).filter();
      expect(surviving(f, 's0'), {p(0, 1)});
      final g = deducer(
        [OnObject(suspectId: 's0', objectId: 'o0', negated: true)],
        objects: [chair],
      ).filter();
      // No room clue here, so the negated mask applies to the full init set.
      expect(surviving(g, 's0'), all8.difference({p(0, 1)}));
    });

    test('NearObject positive keeps the item cell and its orthogonal '
        'neighbours; negated removes them', () {
      // The near mask of (0,1) is {(0,0),(0,1),(0,2),(1,1)}; filter() has no
      // room restriction, so the mask applies to the full init set.
      final f = deducer(
        [NearObject(suspectId: 's1', objectId: 'o0', negated: false)],
        objects: [chair],
      ).filter();
      expect(surviving(f, 's1'), {p(0, 0), p(0, 1), p(0, 2), p(1, 1)});
      final g = deducer(
        [NearObject(suspectId: 's1', objectId: 'o0', negated: true)],
        objects: [chair],
      ).filter();
      expect(
        surviving(g, 's1'),
        all8.difference({p(0, 0), p(0, 1), p(0, 2), p(1, 1)}),
      );
    });

    test('SoleNearObject keeps the near cells for its guest and removes them '
        'from every other guest', () {
      final f = deducer(
        [SoleNearObject(suspectId: 's0', objectId: 'o0', negated: false)],
        objects: [chair],
      ).filter();
      expect(surviving(f, 's0'), {p(0, 0), p(0, 1), p(0, 2), p(1, 1)});
      expect(
        surviving(f, 's1'),
        all8.difference({p(0, 0), p(0, 1), p(0, 2), p(1, 1)}),
      );
      expect(
        surviving(f, 's2'),
        all8.difference({p(0, 0), p(0, 1), p(0, 2), p(1, 1)}),
      );
    });

    test('negated SoleNearObject throws ArgumentError (never ships)', () {
      expect(
        () => deducer(
          [SoleNearObject(suspectId: 's0', objectId: 'o0', negated: true)],
          objects: [chair],
        ).filter(),
        throwsArgumentError,
      );
    });
  });
}
