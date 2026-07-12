#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release

app=.build/Switcher.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Switcher "$app/Contents/MacOS/Switcher"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$PWD/$app"
