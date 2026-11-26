#!/bin/sh
# repack-ipa.sh — Generic Bring-Your-Own-IPA (BYOIPA) repackager for TrollStore TV.
#
# Takes a user-supplied, unencrypted local tvOS .ipa or .app and produces a clean .ipa ready for
# installation with on-device TrollStore TV (trollstorehelper).
#
# Usage:
#   ./scripts/repack-ipa.sh [options] -o <output.ipa> <input.ipa|input.app>
#
# Notes:
# - Icon inversion is enabled by default on macOS (when Xcode actool and Assets.car are present)
#   to visually distinguish repacked side-by-side apps from stock originals. Pass --no-invert-icon
#   to keep the original icon unchanged.
# - Does NOT contain or run any DRM/FairPlay decryption code.
# - Does NOT pre-apply fastPathSign (pre-bypassed binaries are rejected with -67048 by on-device
#   trollstorehelper; leave final CoreTrust signing to TrollStore TV).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DRY_RUN=0
NEW_BID=""
NEW_NAME=""
# auto = invert on macOS when Assets.car + Xcode actool are available; on = require invert; off = disable
INVERT_ICON="auto"
ENT_MODE="sandbox"
ZIP_FLAGS="-rq"
OUT_IPA=""
EXTRA_ALLOW_DECODER=0
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

usage() {
	cat <<'USAGE'
Usage: repack-ipa.sh [options] [-o <output.ipa>] <input.ipa|input.app>

  --dry-run                       Print planned steps without modifying files
  --bundle-id <id>                Override CFBundleIdentifier in Info.plist
  --display-name <name>           Override CFBundleDisplayName and CFBundleName
  --invert-icon                   Require tvOS icon inversion via scripts/invert-tvos-icon.sh (default: auto-on on macOS)
  --no-invert-icon                Disable default icon inversion and keep original Assets.car
  --entitlements sandbox|preserve|<plist>
                                  Entitlements policy for main executable [default: sandbox]
                                  - sandbox : clean standard sandbox entitlements (avoids platform-application IOKit issues)
                                  - preserve: keep existing binary entitlements as-is (do not re-sign)
                                  - <plist> : sign main executable with custom entitlements plist
  --allow-alt-video-decoder       Include com.apple.developer.coremedia.allow-alternate-video-decoder-selection
  --store                         Use zero-compression zip (-0rq)
  -o, --output <out.ipa>          Output .ipa path (default: <input-basename>-repacked.ipa)
  -h, --help                      Show this help message
USAGE
}

[ $# -gt 0 ] || { usage >&2; exit 2; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--bundle-id)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			NEW_BID=$2; shift 2 ;;
		--display-name)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			NEW_NAME=$2; shift 2 ;;
		--invert-icon) INVERT_ICON="on"; shift ;;
		--no-invert-icon) INVERT_ICON="off"; shift ;;
		--entitlements)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			ENT_MODE=$2; shift 2 ;;
		--allow-alt-video-decoder) EXTRA_ALLOW_DECODER=1; shift ;;
		--store) ZIP_FLAGS="-0rq"; shift ;;
		-o|--output)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			OUT_IPA=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) break ;;
	esac
done

INPUT=${1:-}
[ -n "$INPUT" ] || { echo "Missing <input.ipa|input.app>" >&2; usage >&2; exit 2; }
[ -e "$INPUT" ] || { echo "Input not found: $INPUT" >&2; exit 2; }

if [ -z "$OUT_IPA" ]; then
	BASE=$(basename "$INPUT")
	BASE=${BASE%.ipa}
	BASE=${BASE%.tipa}
	BASE=${BASE%.app}
	OUT_IPA="${BASE}-repacked.ipa"
fi

if [ "$DRY_RUN" -eq 1 ]; then
	echo "Input        : $INPUT"
	echo "Output .ipa  : $OUT_IPA"
	echo "Bundle ID    : ${NEW_BID:-<keep>}"
	echo "Display Name : ${NEW_NAME:-<keep>}"
	echo "Invert Icon  : $INVERT_ICON (default: auto-on on macOS; pass --no-invert-icon to disable)"
	echo "Entitlements : $ENT_MODE (allow-alt-video-decoder=$EXTRA_ALLOW_DECODER)"
	echo "+ unpack bundle, strip .jbroot / _CodeSignature / embedded.mobileprovision"
	[ -n "$NEW_BID" ] && echo "+ update CFBundleIdentifier -> $NEW_BID"
	[ -n "$NEW_NAME" ] && echo "+ update CFBundleDisplayName -> $NEW_NAME"
	if [ "$INVERT_ICON" != "off" ]; then
		echo "+ invert Assets.car via $ROOT/scripts/invert-tvos-icon.sh (mode=$INVERT_ICON)"
	fi
	echo "+ normalize ad-hoc signature (leave CoreTrust bypass to on-device TrollStore TV)"
	echo "+ zip $ZIP_FLAGS $OUT_IPA Payload"
	echo "dry-run complete, no files written"
	exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/repack-ipa.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/stage/Payload"

if [ -d "$INPUT" ]; then
	APP_NAME=$(basename "$INPUT")
	cp -R "$INPUT" "$WORK/stage/Payload/$APP_NAME"
else
	mkdir -p "$WORK/unpack"
	unzip -q "$INPUT" -d "$WORK/unpack"
	FOUND_APP=$(find "$WORK/unpack/Payload" -maxdepth 1 -type d -name '*.app' | head -1)
	[ -n "$FOUND_APP" ] || { echo "No Payload/*.app found inside $INPUT" >&2; exit 1; }
	APP_NAME=$(basename "$FOUND_APP")
	cp -R "$FOUND_APP" "$WORK/stage/Payload/$APP_NAME"
fi

APP_DIR="$WORK/stage/Payload/$APP_NAME"
INFO="$APP_DIR/Info.plist"
[ -f "$INFO" ] || { echo "Missing Info.plist in $APP_DIR" >&2; exit 1; }

# Strip jailbreak symlinks and old App Store provisioning/signatures
find "$APP_DIR" -name '.jbroot' -delete
rm -rf "$APP_DIR/_CodeSignature" "$APP_DIR/embedded.mobileprovision"

# Update Info.plist fields cleanly using python3 plistlib (portable across macOS and Linux)
python3 - "$INFO" "$NEW_BID" "$NEW_NAME" <<'PY'
import plistlib, sys
info_path, new_bid, new_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(info_path, "rb") as f:
    data = plistlib.load(f)
if new_bid:
    data["CFBundleIdentifier"] = new_bid
if new_name:
    data["CFBundleDisplayName"] = new_name
    data["CFBundleName"] = new_name
with open(info_path, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
print(data.get("CFBundleIdentifier", ""), data.get("CFBundleExecutable", ""))
PY

BUNDLE_ID=$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb")).get("CFBundleIdentifier",""))' "$INFO")
MAIN_EXE=$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb")).get("CFBundleExecutable",""))' "$INFO")
[ -n "$BUNDLE_ID" ] || { echo "Info.plist missing CFBundleIdentifier" >&2; exit 1; }
[ -n "$MAIN_EXE" ] || { echo "Info.plist missing CFBundleExecutable" >&2; exit 1; }
[ -f "$APP_DIR/$MAIN_EXE" ] || { echo "Main executable missing: $APP_DIR/$MAIN_EXE" >&2; exit 1; }

if [ "$INVERT_ICON" = "on" ]; then
	[ -f "$APP_DIR/Assets.car" ] || { echo "No Assets.car found in $APP_DIR" >&2; exit 1; }
	"$ROOT/scripts/invert-tvos-icon.sh" -o "$WORK/Assets-inverted.car" "$APP_DIR/Assets.car"
	cp "$WORK/Assets-inverted.car" "$APP_DIR/Assets.car"
elif [ "$INVERT_ICON" = "auto" ]; then
	if [ -f "$APP_DIR/Assets.car" ] && [ -x "$DEVELOPER_DIR/usr/bin/actool" ] && command -v swift >/dev/null 2>&1; then
		"$ROOT/scripts/invert-tvos-icon.sh" -o "$WORK/Assets-inverted.car" "$APP_DIR/Assets.car"
		cp "$WORK/Assets-inverted.car" "$APP_DIR/Assets.car"
	else
		echo "Note: skipping auto icon inversion (requires macOS Xcode actool and Assets.car; pass --no-invert-icon to silence)"
	fi
fi

if [ "$ENT_MODE" != "preserve" ] && command -v codesign >/dev/null 2>&1; then
	ENT_FILE="$ENT_MODE"
	if [ "$ENT_MODE" = "sandbox" ]; then
		ENT_FILE="$WORK/sandbox.ent"
		{
			cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>$BUNDLE_ID</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>$BUNDLE_ID</string>
	</array>
EOF
			if [ "$EXTRA_ALLOW_DECODER" -eq 1 ]; then
				cat <<'EOF'
	<key>com.apple.developer.coremedia.allow-alternate-video-decoder-selection</key>
	<true/>
EOF
			fi
			cat <<'EOF'
</dict>
</plist>
EOF
		} > "$ENT_FILE"
	else
		[ -f "$ENT_FILE" ] || { echo "Custom entitlements plist not found: $ENT_FILE" >&2; exit 2; }
	fi

	# Ad-hoc sign embedded dylibs/frameworks first, then main executable with entitlements
	find "$APP_DIR" -type f \( -name '*.dylib' -o -path '*/Frameworks/*.framework/*' \) | while IFS= read -r bin; do
		if file "$bin" | grep -q 'Mach-O'; then
			codesign -f -s - "$bin" >/dev/null 2>&1
		fi
	done
	codesign -f -s - --entitlements "$ENT_FILE" "$APP_DIR/$MAIN_EXE" >/dev/null 2>&1
fi

OUT_DIR=$(dirname "$OUT_IPA")
mkdir -p "$OUT_DIR"
ABS_OUT=$(cd "$OUT_DIR" && pwd)/$(basename "$OUT_IPA")
rm -f "$ABS_OUT"

(cd "$WORK/stage" && zip "$ZIP_FLAGS" "$ABS_OUT" Payload)
echo "Created repacked IPA: $ABS_OUT (bundle_id=$BUNDLE_ID, exe=$MAIN_EXE)"
