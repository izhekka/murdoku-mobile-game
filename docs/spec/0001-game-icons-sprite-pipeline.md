# 0001. Item sprites come only from the game-icons.net pipeline

**Status:** accepted
**Date:** 2026-11-21

## Context
The original item art used Kenney pixel tiles. The owner rejected the
pixel style; the Kenney download pipeline also broke (wrong-slug 404s,
JS-rendered listing pages). A replacement pipeline was built from
game-icons.net SVGs (commit f9dd16a), superseding the Kenney toolchain
(tool/gen_items.dart, tool/extract_items.dart, tool/assets_src/ were
removed).

## Decision
ALL `assets/items/*.png` are built exclusively by
`tool/build_item_icons.sh` from game-icons.net SVGs (CC BY 3.0: Lorc,
Delapouite, caro-asercion). The attribution line in the Settings screen
and README MUST survive any change to the sprites or their pipeline. To
change an item graphic, edit the icon path/color in
`tool/build_item_icons.sh`, run it, and commit the PNG — never
hand-draw or substitute another art source without keeping that
attribution.

## Alternatives considered
- Keeping or regenerating Kenney tiles — rejected by the owner (style).
- Hand-drawn or AI-generated art — rejected: licensing/attribution
  unclear, and the repo requires a reproducible pipeline.
- Other free SVG sets — game-icons.net won on style, coverage of every
  blocking kind, and a clean permissive license.

## Consequences
Every future sprite change goes through the shell script; generated
PNGs are committed so builds stay offline; the CC BY 3.0 attribution
must never be dropped (it is a license condition, not a courtesy).
