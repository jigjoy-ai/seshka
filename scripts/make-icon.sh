#!/bin/bash
# Regenerates everything that comes from the logo drawing:
#   design/color/*.svg           the logo in color
#   Resources/AppIcon.icns       the app icon
#   Sources/Seshka/Icon.swift    the drawings embedded in the app
set -euo pipefail
cd "$(dirname "$0")/.."

/usr/bin/python3 design/make-color-icons.py >/dev/null

SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
swift design/rasterize.swift design/color/closed.svg "$SET"
iconutil -c icns "$SET" -o Resources/AppIcon.icns

/usr/bin/python3 design/embed-icons.py
echo "Wrote Resources/AppIcon.icns and Sources/Seshka/Icon.swift"
