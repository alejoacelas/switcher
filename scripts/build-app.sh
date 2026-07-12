#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."
swift build -c release

identity=${SWITCHER_SIGNING_IDENTITY:-Switcher Local Code Signing}
if ! security find-identity -v -p codesigning | grep -Fq '"'$identity'"'; then
  echo "Missing code-signing identity: $identity" >&2
  echo "Recreate the local identity before rebuilding; ad-hoc signing breaks macOS privacy grants." >&2
  exit 1
fi

app=.build/Switcher.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Switcher "$app/Contents/MacOS/Switcher"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign "$identity" --options runtime --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"
echo "$PWD/$app"
