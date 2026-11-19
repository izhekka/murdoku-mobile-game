import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murdoku/app.dart';
import 'package:murdoku/domain/localized_names.dart';
import 'package:murdoku/domain/models.dart';
import 'package:murdoku/l10n/generated/app_localizations.dart';
import 'package:murdoku/state/providers.dart';
import 'package:murdoku/storage/prefs_repository.dart';
import 'package:murdoku/ui/screens/home_screen.dart';
import 'package:murdoku/ui/widgets/suspect_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Pos p(int row, int col) => (row: row, col: col);

/// Fixture whose suspects/rooms carry poolIndex (the factory's new shape).
CaseData poolFixture() => CaseData(
      seed: 1,
      difficulty: Difficulty.easy,
      rooms: [
        RoomDef(
            id: 'r0', name: 'Library', cells: [p(0, 0), p(0, 1), p(0, 2)], poolIndex: 1),
        RoomDef(
            id: 'r1',
            name: 'Attic',
            cells: [p(0, 3), p(0, 4), p(1, 2)],
            poolIndex: 8),
        RoomDef(
            id: 'r2', name: 'Kitchen', cells: [p(1, 0), p(1, 1), p(1, 3)], poolIndex: 2),
      ],
      objects: const [],
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
            suspectId: 's2', targetId: 's0', direction: Direction.west, negated: false),
        const Beside(suspectId: 's0', targetId: 'V', negated: false),
        const InRoom(suspectId: 's2', roomId: 'r1', negated: true),
      ],
      solution: {'s0': p(0, 0), 's1': p(0, 3), 's2': p(1, 2)},
    );

void main() {
  test('ru arb covers exactly the en key set', () {
    final en = jsonDecode(
            File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, Object?>;
    final ru = jsonDecode(
            File('lib/l10n/app_ru.arb').readAsStringSync()) as Map<String, Object?>;
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final ruKeys = ru.keys.where((k) => !k.startsWith('@')).toSet();
    expect(ruKeys.difference(enKeys), isEmpty, reason: 'ru has extra keys');
    expect(enKeys.difference(ruKeys), isEmpty, reason: 'ru is missing keys');
  });

  testWidgets('default locale is Russian', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PrefsRepository(prefs).saveTutorialSeen(true);
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MurdokuApp(),
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    expect(l10n.localeName, 'ru');
    expect(find.text(l10n.newCase), findsOneWidget);
  });

  test('ru clue grammar: room prep phrases, genitive targets, victim forms',
      () {
    final c = poolFixture();
    final names = NameForms.forLocale('ru', c);
    final l10n = lookupAppLocalizations(const Locale('ru'));

    expect(describeClue(c.clues[0], c, l10n, names), 'Джек — в библиотеке.',
        reason: 'InRoom uses the room prep phrase');
    expect(describeClue(c.clues[1], c, l10n, names),
        'Вера — на том же этаже, что и Джек.',
        reason: 'SameRow keeps both names nominative');
    expect(describeClue(c.clues[2], c, l10n, names),
        'Эллис — в том же коридоре, что и жертва.',
        reason: 'victim nominative');
    expect(describeClue(c.clues[3], c, l10n, names), 'Эллис — западнее Джека.',
        reason: 'Direction uses genitive target');
    expect(describeClue(c.clues[4], c, l10n, names), 'Джек — около жертвы.',
        reason: 'Beside uses genitive victim');
    expect(describeClue(c.clues[5], c, l10n, names), 'Эллис — не на чердаке.',
        reason: 'negated InRoom with prep phrase');
  });

  test('en clue grammar unchanged; names resolve from case data', () {
    final c = poolFixture();
    final names = NameForms.forLocale('en', c);
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(describeClue(c.clues[0], c, l10n, names), 'Jack was in the Library.');
    expect(describeClue(c.clues[3], c, l10n, names), 'Ellis was west of Jack.');
    expect(describeClue(c.clues[4], c, l10n, names), 'Jack was beside the victim.');
  });

  test('entries without poolIndex fall back to stored names', () {
    final fallbackCase = CaseData(
      seed: 2,
      difficulty: Difficulty.easy,
      rooms: [
        RoomDef(
            id: 'r0', name: 'Зал', cells: [p(0, 0), p(0, 1), p(0, 2), p(1, 0), p(1, 1)]),
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
}
