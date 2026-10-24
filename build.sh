#!/bin/bash
# Compila SuriClean e crea SuriClean.app in questa cartella.
set -euo pipefail
cd "$(dirname "$0")"

APP="SuriClean.app"
VERSION="${SURI_VERSION:-1.1}"
BUILD="${VERSION##*.}"
echo "🐾 Ciao! Compilo SuriClean… (su un Mac del 2015 ci vogliono 2-5 minuti)"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "⚠️  Servono gli Strumenti da riga di comando di Apple."
  echo "   Si apre una finestra: premi «Installa», poi rilancia ./build.sh"
  xcode-select --install || true
  exit 1
fi

# SURI_BIN lets the release script pass an already-built (universal) binary.
if [ -n "${SURI_BIN:-}" ]; then
  BIN="$SURI_BIN"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/SuriClean"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SuriClean"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SuriClean</string>
  <key>CFBundleDisplayName</key><string>SuriClean</string>
  <key>CFBundleIdentifier</key><string>com.suriclean.app</string>
  <key>CFBundleExecutable</key><string>SuriClean</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>SuriClean chiede al Finder di spostare nel Cestino le app protette (con la tua password) e di svuotare il Cestino.</string>
  <key>NSHumanReadableCopyright</key><string>Fatto con amore da una suricata 🐾</string>
</dict>
</plist>
PLIST

# A fixed designated requirement (bundle id) keeps privacy permissions such as
# Full Disk Access valid across updates, even with the free ad-hoc signature.
codesign --force --deep --sign - --requirements "=designated => identifier \"com.suriclean.app\"" "$APP" >/dev/null 2>&1 \
  || codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
codesign -d -r- "$APP" 2>&1 | grep designated || true

echo ""
echo "✅ Fatto! SuriClean.app è pronta in: $(pwd)"
echo "   • Per installarla:   mv SuriClean.app /Applications/"
echo "   • Per aprirla subito: open SuriClean.app"
echo "   • Per recuperare lo spazio usato dalla compilazione: rm -rf .build"
