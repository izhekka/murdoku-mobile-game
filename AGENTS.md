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
