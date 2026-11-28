import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/seeded_overrides.dart';

Pos p(int row, int col) => (row: row, col: col);

const List<ObjectKind> allKinds = ObjectKind.values;

/// Fixture with one object of every kind so sentence rendering is exercised
/// for all 14 kinds at once.
CaseData allKindsFixture() => CaseData(
  seed: 3,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(
      id: 'r0',
      name: 'Library',
      cells: [for (var i = 0; i < 14; i++) p(0, i)],
      poolIndex: 1,
    ),
  ],
  objects: [
    for (var i = 0; i < allKinds.length; i++)
      ObjectDef(id: 'o$i', kind: allKinds[i], pos: p(0, i)),
  ],
  suspects: const [Suspect(id: 's0', name: 'Jack', poolIndex: 9)],
  victimPos: p(1, 0),
  murdererId: 's0',
  clues: const [],
  solution: {'s0': p(0, 0)},
);

/// Fixture whose suspects/rooms carry poolIndex (the factory's new shape).
CaseData poolFixture() => CaseData(
  seed: 1,
  difficulty: Difficulty.easy,
  rooms: [
    RoomDef(
      id: 'r0',
      name: 'Library',
      cells: [p(0, 0), p(0, 1), p(0, 2)],
      poolIndex: 1,
    ),
    RoomDef(
      id: 'r1',
      name: 'Attic',
      cells: [p(0, 3), p(0, 4), p(1, 2)],
      poolIndex: 8,
    ),
    RoomDef(
      id: 'r2',
      name: 'Kitchen',
      cells: [p(1, 0), p(1, 1), p(1, 3)],
      poolIndex: 2,
    ),
  ],
  objects: [
    // In r0 with s0's solution cell: a truthful same-room item clue.
    const ObjectDef(id: 'o0', kind: ObjectKind.table, pos: (row: 0, col: 2)),
  ],
  suspects: const [
    Suspect(id: 's0', name: 'Jack', poolIndex: 9),
    Suspect(id: 's1', name: 'Vera', poolIndex: 15),
    Suspect(id: 's2', name: 'Ellis', poolIndex: 4),
  ],
  victimPos: p(1, 1),
  murdererId: 's1',
  clues: [
    const InRoom(suspectId: 's0', roomId: 'r0', negated: false),
    const SameRow(suspectId: 's1', targetId: 's0', negated: false),
    const SameCol(suspectId: 's2', targetId: 'V', negated: false),
    const DirectionClue(
      suspectId: 's2',
      targetId: 's0',
      direction: Direction.west,
      negated: false,
    ),
    const Beside(suspectId: 's0', targetId: 'V', negated: false),
    const InRoom(suspectId: 's2', roomId: 'r1', negated: true),
    const BesideObject(suspectId: 's0', objectId: 'o0', negated: false),
  ],
  solution: {'s0': p(0, 0), 's1': p(0, 3), 's2': p(1, 2)},
);

/// Instrumental forms pinned via `objectGen` before #14 removed the dead
/// field; each ru prep phrase must still embed the same form (lowercased
/// inside the phrase).
const Map<ObjectKind, String> instrumentalForms = {
  ObjectKind.piano: 'пианино',
  ObjectKind.plant: 'растением',
  ObjectKind.armor: 'доспехами',
  ObjectKind.chest: 'сундуком',
  ObjectKind.clock: 'часами',
  ObjectKind.globe: 'глобусом',
  ObjectKind.portrait: 'портретом',
  ObjectKind.fireplace: 'камином',
  ObjectKind.table: 'столом',
  ObjectKind.chair: 'стулом',
  ObjectKind.flowers: 'цветами',
  ObjectKind.sofa: 'диваном',
  ObjectKind.bookshelf: 'стеллажом',
  ObjectKind.lamp: 'лампой',
};

void main() {
  test('the deleted Erase/Undo/Check strings are gone from both arbs '
      '(issue 107)', () {
    const removedKeys = [
      'toolErase',
      'toolUndo',
      'toolCheck',
      'toolCheckTooltip',
      'checkResult',
    ];
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
      final arb =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      for (final key in removedKeys) {
        expect(
          arb.keys.any((k) => k == key || k == '@$key'),
          isFalse,
          reason: '$path must no longer carry $key',
        );
      }
    }
  });

  test('no clue template ends with a trailing period (issue 107)', () {
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
      final arb =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final clueKeys = arb.keys
          .where((k) => k.startsWith('clue') && !k.startsWith('@'))
          .toList();
      expect(clueKeys.length, 15, reason: path);
      for (final key in clueKeys) {
        final template = arb[key]! as String;
        expect(
          template.endsWith('.'),
          isFalse,
          reason: '$path $key = "$template" must not end with a period',
        );
      }
    }
  });

  test('issue 111: row/col cards name the row and column; no floor or '
      'corridor wording remains', () {
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
      final arb =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      expect(arb.containsKey('glossaryObjects'), isTrue, reason: path);
      expect(arb.containsKey('glossaryRowCol'), isFalse, reason: path);
      arb.forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        for (final word in const ['floor', 'corridor', 'этаж', 'коридор']) {
          expect(
            value.contains(word),
            isFalse,
            reason: '$path $key = "$value" must not contain "$word"',
          );
        }
      });
    }
  });

  test('ru arb covers exactly the en key set', () {
    final en = jsonDecode(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    ) as Map<String, Object?>;
    final ru = jsonDecode(
      File('lib/l10n/app_ru.arb').readAsStringSync(),
    ) as Map<String, Object?>;
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final ruKeys = ru.keys.where((k) => !k.startsWith('@')).toSet();
    expect(ruKeys.difference(enKeys), isEmpty, reason: 'ru has extra keys');
    expect(enKeys.difference(ruKeys), isEmpty, reason: 'ru is missing keys');
  });

  testWidgets('default locale is Russian', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PrefsRepository(prefs).saveTutorialSeen(true);
    final container = ProviderContainer(overrides: seededOverrides(prefs));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MurdokuApp(),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    expect(l10n.localeName, 'ru');
    expect(find.text(l10n.newCase), findsOneWidget);
  });

  test(
    'ru clue grammar: room prep phrases, genitive targets, victim forms',
    () {
      final c = poolFixture();
      final names = NameForms.forLocale('ru', c);
      final l10n = lookupAppLocalizations(const Locale('ru'));

      expect(
        describeClue(c.clues[0], c, l10n, names),
        '— в библиотеке',
        reason: 'InRoom uses the room prep phrase',
      );
      expect(
        describeClue(c.clues[1], c, l10n, names),
        '— в той же строке, что и Джек',
        reason: 'SameRow keeps both names nominative (issue 111 wording)',
      );
      expect(
        describeClue(c.clues[2], c, l10n, names),
        '— в той же колонке, что и жертва',
        reason: 'victim nominative (issue 111 wording)',
      );
      expect(
        describeClue(c.clues[3], c, l10n, names),
        '— западнее Джека',
        reason: 'Direction uses genitive target',
      );
      expect(
        describeClue(c.clues[4], c, l10n, names),
        '— около жертвы',
        reason: 'Beside uses genitive victim',
      );
      expect(
        describeClue(c.clues[5], c, l10n, names),
        '— не на чердаке',
        reason: 'negated InRoom with prep phrase',
      );
      expect(
        describeClue(c.clues[6], c, l10n, names),
        '— в комнате со столом',
        reason: 'BesideObject uses the euphonic prep + lowercase instrumental',
      );
      expect(
        describeClue(
          const BesideObject(suspectId: 's0', objectId: 'o0', negated: true),
          c,
          l10n,
          names,
        ),
        '— не в комнате со столом',
        reason: 'negated BesideObject',
      );

      // Issue 111 object-cell kinds: the on-form filler for sits-on, the
      // prep filler for the near kinds. allKindsFixture: o9 is the chair,
      // o2 the armor.
      final k = allKindsFixture();
      final kn = NameForms.forLocale('ru', k);
      expect(
        describeClue(
          OnObject(suspectId: 's0', objectId: 'o9', negated: false),
          k,
          l10n,
          kn,
        ),
        '— сидит на стуле',
        reason: 'OnObject uses the on form',
      );
      expect(
        describeClue(
          NearObject(suspectId: 's0', objectId: 'o9', negated: false),
          k,
          l10n,
          kn,
        ),
        '— рядом со стулом',
        reason: 'NearObject uses the prep form',
      );
      expect(
        describeClue(
          SoleNearObject(suspectId: 's0', objectId: 'o2', negated: false),
          k,
          l10n,
          kn,
        ),
        '— единственный гость рядом с доспехами',
        reason: 'SoleNearObject uses the prep form',
      );
    },
  );

  test('ru item prep phrases: euphonic «со» and lowercase for every kind', () {
    final names = NameForms.forLocale('ru', poolFixture());
    const prep = {
      ObjectKind.piano: 'с пианино',
      ObjectKind.plant: 'с растением',
      ObjectKind.armor: 'с доспехами',
      ObjectKind.chest: 'с сундуком',
      ObjectKind.clock: 'с часами',
      ObjectKind.globe: 'с глобусом',
      ObjectKind.portrait: 'с портретом',
      ObjectKind.fireplace: 'с камином',
      ObjectKind.table: 'со столом',
      ObjectKind.chair: 'со стулом',
      ObjectKind.flowers: 'с цветами',
      ObjectKind.sofa: 'с диваном',
      ObjectKind.bookshelf: 'со стеллажом',
      ObjectKind.lamp: 'с лампой',
    };
    expect(
      prep.keys.toSet(),
      equals(ObjectKind.values.toSet()),
      reason: 'the prep pool must cover every object kind',
    );
    for (final entry in prep.entries) {
      expect(
        names.objectPrep(entry.key),
        entry.value,
        reason: '${entry.key.name} prep phrase',
      );
      // #14: instrumental-case coverage formerly pinned via the removed
      // `gen` field — each prep phrase embeds the same instrumental form.
      expect(
        entry.value.endsWith(instrumentalForms[entry.key]!),
        isTrue,
        reason: '${entry.key.name} instrumental form inside prep phrase',
      );
    }
  });

  test('ru object form records carry exactly (nom, prep, on) — no dead gen (#14, #111)', () {
    // Structural record equality: a leftover `gen` field changes the record
    // shape, and records of different shapes are never equal.
    expect(ruObjectForms.keys.toSet(), equals(ObjectKind.values.toSet()));
    for (final kind in ObjectKind.values) {
      final form = ruObjectForms[kind]!;
      expect(form, (
        nom: form.nom,
        prep: form.prep,
        on: form.on,
      ), reason: '${kind.name} form has exactly the fields nom, prep and on');
    }
  });

  test(
    'ru item clue: exact «с/со» sentences for every object kind (UX-8 polish)',
    () {
      final c = allKindsFixture();
      final names = NameForms.forLocale('ru', c);
      final l10n = lookupAppLocalizations(const Locale('ru'));
      const expected = <ObjectKind, (String, String)>{
        ObjectKind.piano: ('— в комнате с пианино', '— не в комнате с пианино'),
        ObjectKind.plant: (
          '— в комнате с растением',
          '— не в комнате с растением',
        ),
        ObjectKind.armor: (
          '— в комнате с доспехами',
          '— не в комнате с доспехами',
        ),
        ObjectKind.chest: (
          '— в комнате с сундуком',
          '— не в комнате с сундуком',
        ),
        ObjectKind.clock: ('— в комнате с часами', '— не в комнате с часами'),
        ObjectKind.globe: (
          '— в комнате с глобусом',
          '— не в комнате с глобусом',
        ),
        ObjectKind.portrait: (
          '— в комнате с портретом',
          '— не в комнате с портретом',
        ),
        ObjectKind.fireplace: (
          '— в комнате с камином',
          '— не в комнате с камином',
        ),
        ObjectKind.table: ('— в комнате со столом', '— не в комнате со столом'),
        ObjectKind.chair: ('— в комнате со стулом', '— не в комнате со стулом'),
        ObjectKind.flowers: (
          '— в комнате с цветами',
          '— не в комнате с цветами',
        ),
        ObjectKind.sofa: ('— в комнате с диваном', '— не в комнате с диваном'),
        ObjectKind.bookshelf: (
          '— в комнате со стеллажом',
          '— не в комнате со стеллажом',
        ),
        ObjectKind.lamp: ('— в комнате с лампой', '— не в комнате с лампой'),
      };
      expect(
        expected.keys.toSet(),
        equals(ObjectKind.values.toSet()),
        reason: 'sentence literals must cover every object kind',
      );
      for (final entry in expected.entries) {
        final objectId = c.objects.firstWhere((o) => o.kind == entry.key).id;
        expect(
          describeClue(
            BesideObject(suspectId: 's0', objectId: objectId, negated: false),
            c,
            l10n,
            names,
          ),
          entry.value.$1,
          reason: '${entry.key.name} positive ru sentence',
        );
        expect(
          describeClue(
            BesideObject(suspectId: 's0', objectId: objectId, negated: true),
            c,
            l10n,
            names,
          ),
          entry.value.$2,
          reason: '${entry.key.name} negated ru sentence',
        );
      }
    },
  );

  test('en clue grammar stays dash-prefixed; names resolve from case data', () {
    final c = poolFixture();
    final names = NameForms.forLocale('en', c);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(describeClue(c.clues[0], c, l10n, names), '— in the Library');
    expect(describeClue(c.clues[3], c, l10n, names), '— west of Jack');
    expect(describeClue(c.clues[4], c, l10n, names), '— beside the victim');
    expect(
      describeClue(c.clues[6], c, l10n, names),
      '— in the same room as the Table',
    );
    expect(
      describeClue(
        const BesideObject(suspectId: 's0', objectId: 'o0', negated: true),
        c,
        l10n,
        names,
      ),
      '— not in the same room as the Table',
    );
  });

  test('entries without poolIndex fall back to stored names', () {
    final fallbackCase = CaseData(
      seed: 2,
      difficulty: Difficulty.easy,
      rooms: [
        RoomDef(
          id: 'r0',
          name: 'Зал',
          cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)],
        ),
      ],
      objects: const [],
      suspects: const [Suspect(id: 's0', name: 'Тест')],
      victimPos: p(0, 2),
      murdererId: 's0',
      clues: const [],
      solution: {'s0': p(0, 0)},
    );
    final names = NameForms.forLocale('ru', fallbackCase);
    expect(names.nom('s0'), 'Тест');
    expect(names.gen('s0'), 'Тест');
    expect(names.roomPrep('r0'), 'в Зал');
  });

  test('pause menu strings exist and are non-empty in ru and en', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ru = lookupAppLocalizations(const Locale('ru'));
    expect(en.pauseMenuTitle, isNotEmpty);
    expect(en.abandonCase, isNotEmpty);
    expect(ru.pauseMenuTitle, isNotEmpty);
    expect(ru.abandonCase, isNotEmpty);
  });
}
