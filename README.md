# Murdoku

> ⚠️ **"Murdoku" is a working title.** The name belongs to an existing commercial
> puzzle game (murdoku.com). Rename the app before any store submission to avoid
> trademark issues.

An offline mobile murder-mystery logic puzzle built with Flutter: place every
guest on the mansion map so each row, column and room holds exactly one guest,
follow the clue cards, then accuse the guest who ends up alone with the victim.

## Features

- Procedurally generated cases at three difficulties (5×5 / 6×6 / 7×7), each
  verified by an exhaustive solver to have exactly **one** valid solution.
- Six clue types (room, same floor/corridor, directions, beside, beside-object)
  with negations — every clue is a rule, always true.
- Daily case derived from the UTC date, with streak tracking.
- Two hints per case, X-mark elimination marks, undo, unlimited position checks.
- Save/resume across app restarts, statistics per difficulty, light/dark theme.
- Zero photographic assets: item graphics are bold flat-style icons from
  [game-icons.net](https://game-icons.net) (CC BY 3.0 — Lorc, Delapouite,
  caro-asercion), recolored to the game palette; the launcher icon is generated
  by `tool/gen_icon.dart`.
- Fully offline; no analytics, no ads, no permissions.

## Build & run

```bash
flutter pub get
flutter run                 # on an attached device/emulator
```

## Test

```bash
flutter analyze             # static analysis, must be clean
flutter test                # unit + widget tests
flutter test integration_test/smoke_test.dart -d macos   # full-loop smoke test
```

The exact toolchain this repo was built with is recorded in `TOOLCHAIN.md`.

## Release builds

```bash
flutter build apk --release           # Android (requires Android SDK)
flutter build ipa --no-codesign       # iOS (requires full Xcode)
```

Regenerate item sprites and the launcher icon:

```bash
bash tool/build_item_icons.sh      # downloads game-icons.net SVGs (needs rsvg-convert)
dart run tool/gen_icon.dart
dart run flutter_launcher_icons
dart run tool/preview_items.dart   # renders a labeled preview of all item sprites
```

Item icons require `rsvg-convert` (`brew install librsvg`) and network access;
the generated PNGs are committed, so builds stay fully offline.

## Project layout

- `lib/domain/` — pure Dart puzzle engine (models, clue evaluation, solver,
  seeded generator). No Flutter imports; fully unit-tested.
- `lib/state/` — Riverpod controllers (game, settings, stats, clock).
- `lib/storage/` — `shared_preferences` persistence with fail-soft JSON loads.
- `lib/ui/` — screens and widgets; all strings via `AppLocalizations`.
- `lib/l10n/` — arb source + generated localizations.
- `docs/superpowers/plans/` — the implementation plan this app was built from.

## Versioning

`1.0.0+1` — see `pubspec.yaml`. Android `applicationId` / iOS bundle id:
`com.murdoku.game` (⚠ also subject to the rename above).
