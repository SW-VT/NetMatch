#!/bin/bash
# Baut aus dem Xcode-Projekt in diesem Ordner das Installer-Paket NetMatch.pkg.
# Ausführen:  chmod +x build_installer.sh && ./build_installer.sh
# Ergebnis:   NetMatch.pkg – dieses eine Datei an Kollegen weitergeben.
set -e

APP_NAME="NetMatch"
SCHEME="NetMatch"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

PROJECT="NetMatch.xcodeproj"
if [ ! -d "$PROJECT" ]; then
  echo "„$PROJECT“ wurde in diesem Ordner nicht gefunden:"
  ls -la
  echo "Bitte dieses Skript im selben Ordner wie $PROJECT ausführen,"
  echo "oder den Namen in PROJECT= oben in diesem Skript anpassen."
  exit 1
fi

BUILD_DIR="$HERE/build"
PKG_ROOT="$HERE/pkgroot"
OUT="$HERE/${APP_NAME}.pkg"

rm -rf "$BUILD_DIR" "$PKG_ROOT" "$OUT"
mkdir -p "$PKG_ROOT/Applications"

echo "➤ Baue $APP_NAME aus $PROJECT …"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "Build fehlgeschlagen: keine .app gefunden."
  exit 1
fi

cp -R "$APP_PATH" "$PKG_ROOT/Applications/"
INSTALLED_APP="$PKG_ROOT/Applications/$(basename "$APP_PATH")"

echo "➤ Signiere lokal (ad-hoc) …"
codesign --force --deep --sign - "$INSTALLED_APP"

if [ ! -f "$HERE/Scripts/postinstall" ]; then
  echo "„Scripts/postinstall“ fehlt. Lege einen Ordner „Scripts“ neben $PROJECT an"
  echo "und lege die Dateien „preinstall“ und „postinstall“ dort hinein."
  exit 1
fi
chmod +x "$HERE/Scripts/postinstall"
[ -f "$HERE/Scripts/preinstall" ] && chmod +x "$HERE/Scripts/preinstall"

echo "➤ Baue Installer-Paket …"
pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "de.netmatch.installer" \
  --version "1.0" \
  --install-location "/" \
  --scripts "$HERE/Scripts" \
  "$OUT"

rm -rf "$BUILD_DIR" "$PKG_ROOT"

echo ""
echo "✓ Fertig: $OUT"
echo "  Diese eine Datei kannst du an Kollegen weitergeben."
