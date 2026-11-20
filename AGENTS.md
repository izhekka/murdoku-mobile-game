# AGENTS.md — Murdoku

This repository is built by executing the plan at
`docs/superpowers/plans/2026-11-19-murdoku-flutter-app.md` in strict task order
(Task 0 … Task 17). The plan's §2 Game Design Spec is binding; its *Interfaces*
blocks pin public APIs across tasks — never rename them.

## Guardrails (summary of plan §1)

- Work task-by-task, TDD: failing test first, then minimal implementation, then green.
- Gate after every task: `flutter analyze` (0 issues) && `flutter test` (all pass), then commit.
- Runtime dependencies are exactly: flutter_riverpod, go_router, shared_preferences
  (plus Flutter-template defaults). Dev-only extras: image, flutter_launcher_icons (Task 17).
- No code generation / build_runner / freezed. Hand-written toJson/fromJson.
- Fully offline; no networking, analytics, ads, or permissions.
- All user-facing strings go through AppLocalizations (arb files).
- Never edit generated output: `lib/l10n/generated/**`, `**/.dart_tool/**`, `*.g.dart`.
- "Murdoku" is a working title — trademark risk; rename before store submission (Task 17).

## Item sprites (ownership)

- ALL `assets/items/*.png` (15 files: 14 item kinds + victim) are built by
  `tool/build_item_icons.sh` from game-icons.net SVGs (CC BY 3.0 — attribution
  line is in the Settings screen and README). Do NOT hand-draw or replace them
  with other sources without keeping that attribution.
- `tool/preview_items.dart` renders a labeled preview of the whole set.
- To change an item graphic: edit the icon path/color in
  `tool/build_item_icons.sh`, run it, commit the PNG.
