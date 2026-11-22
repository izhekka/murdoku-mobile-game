# 0005 — Skin system: token layer over ThemeData

## Status
Accepted

## Date
2026-11-22

## Context
The app's look was a single Material palette (AppTheme, amber seed) plus a room-tint list. Three cartoon skins (light-only, visually distinct in borders/radii/shadows beyond what ColorScheme expresses) must be user-selectable at runtime and persist.

## Decision
A `SkinScope` InheritedWidget exposes immutable `SkinTokens` (palettes, radii, borders, shadows, per-action button styles) chosen by `SkinSetting` from Settings; `AppTheme.forSkin()` maps skin→ThemeData (classic keeps system/light/dark; cartoon skins pin light). Custom widgets read tokens from context; stock Material theming continues via ThemeData. No new dependencies.

## Consequences
New visual surfaces must add tokens to SkinTokens and consume them (not hardcode colors) — enforced by review, not the type system. Adding a skin = one token set + one ThemeData mapping + arb labels. Dark variants of cartoon skins would extend tokens per brightness later without re-architecture.
