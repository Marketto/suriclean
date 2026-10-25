#!/usr/bin/env bash
# Copies Schiaccia's compression engine (github.com/Marketto/pdf-tiny-tools) into ./schiaccia/,
# the folder every platform bundles: motore.js + engine.js + config.js + the two vendor libraries,
# plus the press mascot drawn from Schiaccia's single source (tools/mascot.mjs). See docs/SCHIACCIA.md.
set -euo pipefail
cd "$(dirname "$0")/.."
REF="${SCHIACCIA_REF:-main}"
SRC="${SCHIACCIA_SRC:-}"
TMP=""
if [ -z "$SRC" ]; then
  # inside the repo (relative path), so node finds it on Windows too
  TMP=".schiaccia-src"
  rm -rf "$TMP"
  git clone -q --depth 1 --branch "$REF" https://github.com/Marketto/pdf-tiny-tools "$TMP"
  SRC="$TMP"
fi
rm -rf schiaccia && mkdir -p schiaccia/vendor
cp "$SRC/motore.js" "$SRC/engine.js" "$SRC/config.js" "$SRC/VERSION" schiaccia/
cp "$SRC/vendor/pdf-lib.min.js" "$SRC/vendor/mediabunny.min.mjs" "$SRC/vendor/mediabunny-LICENSE.txt" schiaccia/vendor/
V="$(tr -d '[:space:]' < "$SRC/VERSION")"
# the published site writes the version into motore.js; do the same here
sed -i.bak "s/\"dev\"/\"$V\"/" schiaccia/motore.js 2>/dev/null && rm -f schiaccia/motore.js.bak || true
# copied next to us and imported with a relative path: works with Windows paths too
cp "$SRC/tools/mascot.mjs" schiaccia/.mascot.mjs
node --input-type=module -e "
import { workPressSvg } from './schiaccia/.mascot.mjs';
import fs from 'fs';
fs.writeFileSync('schiaccia/press.svg', workPressSvg());
"
rm -f schiaccia/.mascot.mjs
echo "Schiaccia $V → ./schiaccia/"
if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
