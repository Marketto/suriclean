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
[ -f shared/audio/remix.mp3 ] && cp shared/audio/remix.mp3 "$APP/Contents/Resources/remix.mp3"
# translations (i18n/README.md): the JSON files, plus an .lproj per language so macOS
# shows its own menus and permission texts in the user's language
mkdir -p "$APP/Contents/Resources/i18n"
cp i18n/*.json "$APP/Contents/Resources/i18n/" 2>/dev/null || true
if command -v python3 >/dev/null 2>&1; then
  python3 - "$APP/Contents/Resources" <<'PY'
import json, os, sys
res = sys.argv[1]
src = os.path.join(res, "i18n")
for lang in json.load(open(os.path.join(src, "languages.json"), encoding="utf-8")):
    code = lang["code"]
    d = os.path.join(res, code + ".lproj")
    os.makedirs(d, exist_ok=True)
    text = ""
    for c in (code, "en", "it"):
        p = os.path.join(src, c + ".json")
        if os.path.exists(p):
            v = json.load(open(p, encoding="utf-8")).get("mac.plist.appleevents")
            if v:
                text = v
                break
    if text:
        text = text.replace("\\", "\\\\").replace('"', '\\"')
        open(os.path.join(d, "InfoPlist.strings"), "w", encoding="utf-8").write('"NSAppleEventsUsageDescription" = "%s";\n' % text)
PY
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SuriClean</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleAllowMixedLocalizations</key><true/>
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
