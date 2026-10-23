#!/bin/bash
# Builds a universal (Intel + Apple Silicon) SuriClean.app and packs it in a pretty DMG.
# Usage: scripts/make-dmg.sh   →   dist/SuriClean.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist && mkdir -p dist

echo "🐾 Compilo per Intel…"
swift build -c release --triple x86_64-apple-macosx12.0
X86="$(swift build -c release --triple x86_64-apple-macosx12.0 --show-bin-path)/SuriClean"
echo "🐾 Compilo per Apple Silicon…"
swift build -c release --triple arm64-apple-macosx12.0
ARM="$(swift build -c release --triple arm64-apple-macosx12.0 --show-bin-path)/SuriClean"
lipo -create "$X86" "$ARM" -output dist/SuriClean
lipo -info dist/SuriClean

SURI_BIN="$PWD/dist/SuriClean" ./build.sh
mv SuriClean.app dist/

# Retina-ready background
tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png -out dist/background.tiff

# dmgbuild writes the Finder layout (.DS_Store) itself, no Finder scripting needed
python3 -m venv dist/venv
dist/venv/bin/pip install --quiet dmgbuild
cat > dist/dmg-settings.py <<'PY'
import os
root = os.environ["SURI_ROOT"]
files = [os.path.join(root, "dist/SuriClean.app")]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(root, "Resources/dmg/VolumeIcon.icns")
background = os.path.join(root, "dist/background.tiff")
format = "UDZO"
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {"SuriClean.app": (170, 205), "Applications": (490, 205)}
hide_extensions = ["SuriClean.app"]
PY
if ! SURI_ROOT="$PWD" dist/venv/bin/dmgbuild -s dist/dmg-settings.py "SuriClean" dist/SuriClean.dmg; then
  echo "⚠️ dmgbuild non è riuscito: creo un DMG semplice"
  mkdir -p dist/stage && cp -R dist/SuriClean.app dist/stage/ && ln -s /Applications dist/stage/Applications
  hdiutil create -volname SuriClean -srcfolder dist/stage -ov -format UDZO dist/SuriClean.dmg
fi
ls -la dist/SuriClean.dmg
