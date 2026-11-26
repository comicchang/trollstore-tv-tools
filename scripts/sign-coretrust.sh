#!/bin/sh
# sign-coretrust.sh — Host-side batch CoreTrust bypass signing helper for tvOS apps/IPAs.
#
# Usage:
#   ./scripts/sign-coretrust.sh [--dry-run] [--entitlements full|minimal|<path>] [-o <out.ipa>] <App.app|App.ipa>
#
# Notes:
# - Runs fastPathSign strictly on the macOS host (running fastPathSign on-device yields Killed: 9).
# - Automatically discovers main executable + Frameworks/*.framework executables + all *.dylib Mach-Os.
# - Verifies CDHash and TeamIdentifier=T8ALTGMVXN on every signed Mach-O.
# - Never touches any device, never runs uiopen, never reboots.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

resolve_fastpath() {
	if [ -n "${FASTPATH_SIGN:-}" ]; then
		printf '%s\n' "$FASTPATH_SIGN"
		return 0
	fi
	if [ -x "$ROOT/vendor/fastPathSign" ]; then
		printf '%s\n' "$ROOT/vendor/fastPathSign"
		return 0
	fi
	if command -v fastPathSign >/dev/null 2>&1; then
		command -v fastPathSign
		return 0
	fi
	printf '%s\n' "${HOME:-/tmp}/.local/share/tsltv-tools/fastPathSign"
}

FASTPATH_SIGN=$(resolve_fastpath)
TMPDIR_WORK=${TMPDIR:-/tmp}

ENT_MODE=full
DRY_RUN=0
OUT_IPA=""

usage() {
	cat <<'USAGE'
Usage: sign-coretrust.sh [--dry-run] [--entitlements full|minimal|<path>] [-o <out.ipa>] <App.app|App.ipa>

  --dry-run               Print signing actions without modifying files
  --entitlements full     Built-in full template (platform-application/no-sandbox/no-container) [default]
  --entitlements minimal  Minimal sandboxed template (application-identifier + container-required)
  --entitlements <path>   Custom entitlements plist path
  -o, --output <out.ipa>  Repackage signed IPA to <out.ipa> (when input is .ipa)

Environment:
  FASTPATH_SIGN   Path to host fastPathSign binary
                  (auto-searches PATH and ~/.local/share/tsltv-tools/fastPathSign)
USAGE
}

[ $# -gt 0 ] || { usage >&2; exit 2; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--entitlements)
			[ $# -ge 2 ] || { echo "Missing value for --entitlements" >&2; exit 2; }
			ENT_MODE=$2; shift 2 ;;
		-o|--output)
			[ $# -ge 2 ] || { echo "Missing value for --output" >&2; exit 2; }
			OUT_IPA=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) break ;;
	esac
done

TARGET=${1:-}
[ -n "$TARGET" ] || { echo "Missing target .app or .ipa" >&2; usage >&2; exit 2; }
[ -e "$TARGET" ] || { echo "Target not found: ${TARGET}" >&2; exit 2; }

if [ "$DRY_RUN" -eq 0 ] && [ ! -x "$FASTPATH_SIGN" ]; then
	echo "fastPathSign not found or not executable: ${FASTPATH_SIGN}" >&2
	echo "Set FASTPATH_SIGN=/path/to/fastPathSign or place it in ~/.local/share/tsltv-tools/fastPathSign" >&2
	exit 2
fi

WORK=$(mktemp -d "$TMPDIR_WORK/tsltv-sign.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

IS_IPA=0
if [ -d "$TARGET" ]; then
	APP_DIR="$TARGET"
else
	case "$TARGET" in
		*.ipa|*.tipa) IS_IPA=1 ;;
		*) echo "Target must be .app, .ipa, or .tipa: ${TARGET}" >&2; exit 2 ;;
	esac
	mkdir -p "$WORK/unpack"
	unzip -q "$TARGET" -d "$WORK/unpack"
	APP_DIR=$(find "$WORK/unpack/Payload" -maxdepth 1 -name '*.app' -type d | head -1)
	[ -n "$APP_DIR" ] || { echo "No Payload/*.app found inside IPA" >&2; exit 2; }
fi

INFO="$APP_DIR/Info.plist"
[ -f "$INFO" ] || { echo "Missing Info.plist: ${INFO}" >&2; exit 2; }

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null || true)
[ -n "$BUNDLE_ID" ] || { echo "Info.plist missing CFBundleIdentifier" >&2; exit 2; }
MAIN_EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO" 2>/dev/null || true)
[ -n "$MAIN_EXE" ] || { echo "Info.plist missing CFBundleExecutable" >&2; exit 2; }

ENT_FILE=""
case "$ENT_MODE" in
	full|minimal)
		if [ "$DRY_RUN" -eq 1 ]; then
			ENT_FILE="<builtin-$ENT_MODE:$BUNDLE_ID>"
		else
			ENT_FILE="$WORK/ent-$ENT_MODE.plist"
			if [ "$ENT_MODE" = "full" ]; then
				cat > "$ENT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$BUNDLE_ID</string>
<key>get-task-allow</key><true/>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.no-container</key><true/>
<key>com.apple.private.security.container-required</key><false/>
</dict></plist>
EOF
			else
				cat > "$ENT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$BUNDLE_ID</string>
<key>com.apple.private.security.container-required</key><string>$BUNDLE_ID</string>
</dict></plist>
EOF
			fi
			plutil -lint "$ENT_FILE" >/dev/null 2>&1 || { echo "Generated entitlements failed plutil lint" >&2; exit 2; }
		fi
		;;
	*)
		ENT_FILE=$ENT_MODE
		[ -f "$ENT_FILE" ] || { echo "Entitlements file not found: ${ENT_FILE}" >&2; exit 2; }
		;;
esac

is_macho() {
	file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

RAW_COLLECT="$WORK/targets.raw"
COLLECT="$WORK/targets.txt"
: > "$RAW_COLLECT"

add_target() {
	p=$1
	[ -f "$p" ] || return 0
	if is_macho "$p"; then
		printf '%s\n' "$p" >> "$RAW_COLLECT"
	fi
}

add_target "$APP_DIR/$MAIN_EXE"

for fw in "$APP_DIR"/Frameworks/*.framework; do
	[ -d "$fw" ] || continue
	fw_exe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$fw/Info.plist" 2>/dev/null || true)
	if [ -n "$fw_exe" ] && [ -f "$fw/$fw_exe" ]; then
		add_target "$fw/$fw_exe"
	else
		add_target "$fw/$(basename "$fw" .framework)"
	fi
done

find "$APP_DIR" -name '*.dylib' -type f 2>/dev/null | while IFS= read -r d; do
	if is_macho "$d"; then printf '%s\n' "$d" >> "$RAW_COLLECT"; fi
done

sort -u "$RAW_COLLECT" > "$COLLECT"
COUNT=$(wc -l < "$COLLECT" | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "No Mach-O binaries found under ${APP_DIR}" >&2; exit 2; }

echo "bundle=$BUNDLE_ID"
echo "app_dir=$APP_DIR"
echo "entitlements=$ENT_MODE ($ENT_FILE)"
echo "targets=$COUNT"
echo

FAIL=0
while IFS= read -r f; do
	rel=${f#"$APP_DIR/"}
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '+ %s --entitlements %s %s\n' "$FASTPATH_SIGN" "$ENT_FILE" "$f"
		continue
	fi
	out=$("$FASTPATH_SIGN" --entitlements "$ENT_FILE" "$f" 2>&1) || true
	case "$out" in
		*"Applied CoreTrust Bypass"*) ;;
		*) echo "FAIL sign: $rel"; printf '%s\n' "$out" | tail -3; FAIL=1; continue ;;
	esac
	cdhash=$(codesign -dvvv "$f" 2>&1 | sed -n 's/^CDHash=//p' | head -1)
	team=$(codesign -dvvv "$f" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
	if [ -z "$cdhash" ]; then
		echo "FAIL cdhash missing: $rel"; FAIL=1; continue
	fi
	if [ "$team" != "T8ALTGMVXN" ]; then
		echo "FAIL team=$team (expected T8ALTGMVXN): $rel"; FAIL=1; continue
	fi
	echo "OK $rel cdhash=$cdhash team=$team"
done < "$COLLECT"

echo
if [ "$FAIL" -ne 0 ]; then
	echo "Result: FAILED (one or more Mach-O targets failed signing/verification)" >&2
	exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
	if [ "$IS_IPA" -eq 1 ] && [ -n "$OUT_IPA" ]; then
		printf '+ (cd %s/unpack && zip -qr %s Payload)\n' "$WORK" "$OUT_IPA"
	fi
	echo "dry-run complete, no files modified"
	exit 0
fi

echo "Result: signed and verified $COUNT Mach-O target(s)"
if [ "$IS_IPA" -eq 0 ]; then
	echo "Output: ${APP_DIR} (signed in-place)"
elif [ -n "$OUT_IPA" ]; then
	mkdir -p "$(dirname "$OUT_IPA")"
	OUT_ABS=$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")
	rm -f "$OUT_ABS"
	(cd "$WORK/unpack" && zip -qr "$OUT_ABS" Payload)
	echo "Output IPA: ${OUT_ABS}"
else
	echo "Note: input was an IPA signed in a temporary directory; pass -o <out.ipa> to write a repackaged IPA."
fi
