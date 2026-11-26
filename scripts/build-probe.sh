#!/bin/sh
# Build the independent probe app and embedded ProbeKit framework.
# This script does not install, sign implicitly, reboot, or write to
# production device paths.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SDK=${SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk}
OUT=${OUT:-"$ROOT/build/Demo.app"}
FASTPATH_SIGN=${FASTPATH_SIGN:-}

[ -d "$SDK" ] || { echo "tvOS SDK not found: $SDK" >&2; exit 1; }
[ -d "$ROOT/src/probe/Demo.app/Frameworks/ProbeKit.framework" ] || {
    echo "ProbeKit.framework template missing" >&2; exit 1;
}

rm -rf "$OUT"
mkdir -p "$OUT/Frameworks"
cp -p "$ROOT/src/probe/Demo.app/Info.plist" "$OUT/Info.plist"
if [ -f "$ROOT/src/probe/Demo.app/Assets.car" ]; then
    cp -p "$ROOT/src/probe/Demo.app/Assets.car" "$OUT/Assets.car"
fi
cp -R "$ROOT/src/probe/Demo.app/Frameworks/ProbeKit.framework" "$OUT/Frameworks/"

clang -target arm64-apple-tvos17.0 -isysroot "$SDK" -fobjc-arc \
    -dynamiclib -install_name @rpath/ProbeKit.framework/ProbeKit \
    -framework Foundation \
    -I"$ROOT/src/probe" \
    "$ROOT/src/probe/ProbeKit.m" \
    -o "$OUT/Frameworks/ProbeKit.framework/ProbeKit"

clang -target arm64-apple-tvos17.0 -isysroot "$SDK" -fobjc-arc \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -F"$OUT/Frameworks" -framework ProbeKit \
    -Wl,-rpath,@executable_path/Frameworks \
    -I"$ROOT/src/probe" \
    "$ROOT/src/probe/main.m" \
    -o "$OUT/Demo"

if [ -n "$FASTPATH_SIGN" ]; then
    "$FASTPATH_SIGN" --entitlements "$ROOT/src/probe/demo.ent" \
        "$OUT/Frameworks/ProbeKit.framework/ProbeKit"
    "$FASTPATH_SIGN" --entitlements "$ROOT/src/probe/demo.ent" "$OUT/Demo"
fi

echo "built: $OUT"
