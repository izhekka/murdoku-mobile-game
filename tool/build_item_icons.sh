#!/usr/bin/env bash
# Builds assets/items/<kind>.png from game-icons.net SVGs (CC BY 3.0):
# downloads the icon, strips its black background path, recolors it, and
# rasterizes to 256px transparent PNGs via rsvg-convert (brew install librsvg).
#
# Run: bash tool/build_item_icons.sh
set -euo pipefail

SRC="https://raw.githubusercontent.com/game-icons/icons/master"
WORK="$(mktemp -d)"

# kind|icon path|color
ITEMS=(
  "table|delapouite/table.svg|#E8A33D"
  "chair|delapouite/wooden-chair.svg|#E26D5C"
  "flowers|lorc/rose.svg|#D66BA0"
  "sofa|delapouite/sofa.svg|#3FB8AF"
  "bookshelf|delapouite/bookshelf.svg|#C98A4B"
  "lamp|delapouite/bed-lamp.svg|#F0C64A"
  "piano|caro-asercion/grand-piano.svg|#8B7BC4"
  "plant|delapouite/cactus-pot.svg|#6FBF5A"
  "chest|delapouite/chest.svg|#A9713D"
  "clock|delapouite/cuckoo-clock.svg|#58A6DC"
  "portrait|delapouite/wood-frame.svg|#5FAE6E"
  "fireplace|delapouite/fireplace.svg|#E05A5A"
  "globe|lorc/globe.svg|#5E94C1"
  "armor|delapouite/abdominal-armor.svg|#9BA3B5"
  "victim|delapouite/chalk-outline-murder.svg|#F2EEE3"
)

mkdir -p assets/items
for item in "${ITEMS[@]}"; do
  kind="${item%%|*}"
  rest="${item#*|}"
  icon="${rest%%|*}"
  color="${rest##*|}"
  svg="$WORK/$kind.svg"
  curl -sSf -o "$svg" "$SRC/$icon"
  # Strip the black 512x512 background path, recolor the icon path.
  sed -e 's|<path d="M0 0h512v512H0z"/>||' \
      -e "s|fill=\"#fff\"|fill=\"$color\"|" "$svg" \
    | rsvg-convert -w 256 -h 256 > "assets/items/$kind.png"
  echo "built assets/items/$kind.png"
done
rm -rf "$WORK"
echo "done: ${#ITEMS[@]} item sprites"
