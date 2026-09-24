#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "==> Building MKVAirPlay (Release mode)..."
swift build -c release

APP_BUNDLE="MKVAirPlay.app"
echo "==> Packaging into ${APP_BUNDLE}..."

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp .build/out/Products/Release/MKVAirPlay "${APP_BUNDLE}/Contents/MacOS/MKVAirPlay"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

chmod +x "${APP_BUNDLE}/Contents/MacOS/MKVAirPlay"

# Ad-hoc sign the bundle
if which codesign >/dev/null 2>&1; then
    echo "==> Signing ${APP_BUNDLE}..."
    codesign --force --deep --sign - "${APP_BUNDLE}"
fi

echo "==> Successfully created ${APP_BUNDLE}!"
echo "    You can run it directly: open ${APP_BUNDLE}"
