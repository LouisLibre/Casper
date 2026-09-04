#!/bin/sh
# Renders AppIcon.appiconset from AppIcon.svg and copies the menu bar glyph
# into its image set. Run after editing either SVG. Needs librsvg:
#   brew install librsvg
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ASSETS="$HERE/../casper/Assets.xcassets"
OUT="$ASSETS/AppIcon.appiconset"
for spec in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
  size=${spec%:*}; scale=${spec#*:}; px=$((size * scale))
  suffix=""; [ "$scale" = 2 ] && suffix="@2x"
  rsvg-convert -w "$px" -h "$px" "$HERE/AppIcon.svg" -o "$OUT/icon_${size}x${size}${suffix}.png"
done
cp "$HERE/MenuBarIcon.svg" "$ASSETS/MenuBarIcon.imageset/MenuBarIcon.svg"
