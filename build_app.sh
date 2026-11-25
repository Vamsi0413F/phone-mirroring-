#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building DroidMirror with xcodebuild..."
xcodebuild -scheme DroidMirror -destination 'platform=macOS' -derivedDataPath .build/DerivedData -configuration Release build

PRODUCTS_DIR=".build/DerivedData/Build/Products/Release"
APP_DIR="build/DroidMirror.app"

echo "==> Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/bin"
mkdir -p "${APP_DIR}/Contents/Resources/licenses"

# Copy binary
cp "${PRODUCTS_DIR}/DroidMirror" "${APP_DIR}/Contents/MacOS/"

# Copy Info.plist
cp "Sources/DroidMirror/Resources/Info.plist" "${APP_DIR}/Contents/"

# Copy bundled tools and licenses
cp "Sources/DroidMirror/Resources/bin/adb" "${APP_DIR}/Contents/Resources/bin/"
cp "Sources/DroidMirror/Resources/bin/scrcpy-server-v3.1" "${APP_DIR}/Contents/Resources/bin/"
cp "Sources/DroidMirror/Resources/licenses/"* "${APP_DIR}/Contents/Resources/licenses/"

# Copy SwiftPM resource bundle if present
if [ -d "${PRODUCTS_DIR}/DroidMirror_DroidMirror.bundle" ]; then
    cp -R "${PRODUCTS_DIR}/DroidMirror_DroidMirror.bundle" "${APP_DIR}/Contents/Resources/"
fi

# Ensure executable permissions
chmod +x "${APP_DIR}/Contents/MacOS/DroidMirror"
chmod +x "${APP_DIR}/Contents/Resources/bin/adb"

echo "==> Code-signing with Hardened Runtime (ad-hoc development)..."
codesign --force --options runtime --entitlements "Sources/DroidMirror/Resources/Entitlements.plist" --sign - "${APP_DIR}/Contents/Resources/bin/adb" || true
codesign --force --options runtime --entitlements "Sources/DroidMirror/Resources/Entitlements.plist" --sign - "${APP_DIR}/Contents/MacOS/DroidMirror"
codesign --force --deep --options runtime --entitlements "Sources/DroidMirror/Resources/Entitlements.plist" --sign - "$APP_DIR"

echo "==> Verifying signature & hardened runtime flags..."
codesign -dv --verbose=4 "$APP_DIR"

echo "==> Successfully built ${APP_DIR}!"
