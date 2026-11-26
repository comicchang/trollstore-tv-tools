#!/bin/sh
# sign-coretrust.sh — Host-side batch CoreTrust bypass signing helper for tvOS apps/IPAs.
#
# Usage:
#   ./scripts/sign-coretrust.sh [--dry-run] [--entitlements full|minimal|<path>] [-o <out.ipa>] <App.app|App.ipa>
#
# Notes:
# - Runs fastPathSign strictly on the macOS host (running fastPathSign on-device yields Killed: 9).
# - Recursively discovers ALL regular Mach-O binaries (main exe, nested .appex, nested .framework,
#   *.dylib, helper Mach-Os) while skipping symlinks.
# - Applies per-bundle entitlements (matching each bundle's own CFBundleIdentifier for main .app
#   and nested .appex bundles; non-bundle frameworks/dylibs are signed without app entitlements).
# - Rejects FairPlay-encrypted main binaries (cryptid != 0) and warns on encrypted nested binaries.
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
                  (auto-searches vendor/fastPathSign, PATH, and ~/.local/share/tsltv-tools/fastPathSign)
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
	echo "Run ./scripts/fetch-fastpathsign.sh or set FASTPATH_SIGN=/path/to/fastPathSign" >&2
	exit 2
fi

case "$ENT_MODE" in
	full|minimal) ;;
	*) [ -f "$ENT_MODE" ] || { echo "Entitlements file not found: ${ENT_MODE}" >&2; exit 2; } ;;
esac

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
MAIN_EXE_PATH="$APP_DIR/$MAIN_EXE"

make_ent_for_bundle() {
	bid=$1
	idx=$2
	case "$ENT_MODE" in
		full|minimal)
			if [ "$DRY_RUN" -eq 1 ]; then
				printf '<builtin-%s:%s>\n' "$ENT_MODE" "$bid"
				return 0
			fi
			ef="$WORK/ent-$ENT_MODE-$idx.plist"
			if [ "$ENT_MODE" = "full" ]; then
				cat > "$ef" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$bid</string>
<key>get-task-allow</key><true/>
<key>platform-application</key><true/>
<key>com.apple.private.security.no-sandbox</key><true/>
<key>com.apple.private.security.no-container</key><true/>
<key>com.apple.private.security.container-required</key><false/>
</dict></plist>
EOF
			else
				cat > "$ef" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$bid</string>
<key>com.apple.private.security.container-required</key><string>$bid</string>
</dict></plist>
EOF
			fi
			plutil -lint "$ef" >/dev/null 2>&1 || { echo "Generated entitlements failed plutil lint for $bid" >&2; exit 2; }
			printf '%s\n' "$ef"
			;;
		*)
			printf '%s\n' "$ENT_MODE"
			;;
	esac
}

is_macho() {
	file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

is_encrypted_macho() {
	command -v otool >/dev/null 2>&1 || return 1
	otool -l "$1" 2>/dev/null | awk '/cryptid[[:space:]]+[1-9]/{found=1} END{exit !found}'
}

# 1. Discover all executable bundles (main .app + nested .appex / .app, skipping FMWK)
BUNDLES_TSV="$WORK/bundles.tsv"
: > "$BUNDLES_TSV"
find "$APP_DIR" -name 'Info.plist' -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r ip; do
	bdir=$(dirname "$ip")
	ptype=$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$ip" 2>/dev/null || true)
	[ "$ptype" = "FMWK" ] && continue
	bbid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ip" 2>/dev/null || true)
	bexe=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$ip" 2>/dev/null || true)
	[ -n "$bbid" ] && [ -n "$bexe" ] || continue
	bpath="$bdir/$bexe"
	[ -f "$bpath" ] && [ ! -L "$bpath" ] || continue
	if is_macho "$bpath"; then
		printf '%s\t%s\n' "$bpath" "$bbid" >> "$BUNDLES_TSV"
	fi
done

lookup_bundle_id() {
	target_path=$1
	awk -F '\t' -v p="$target_path" '$1 == p { print $2; exit }' "$BUNDLES_TSV"
}

# 2. Recursively discover ALL regular non-symlink Mach-O files (main, .appex, .framework, .dylib, helpers)
COLLECT="$WORK/targets.txt"
: > "$COLLECT"
find "$APP_DIR" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
	[ ! -L "$f" ] || continue
	if is_macho "$f"; then
		printf '%s\n' "$f" >> "$COLLECT"
	fi
done

COUNT=$(wc -l < "$COLLECT" | tr -d ' ')
[ "$COUNT" -gt 0 ] || { echo "No Mach-O binaries found under ${APP_DIR}" >&2; exit 2; }

echo "bundle=$BUNDLE_ID"
echo "app_dir=$APP_DIR"
echo "entitlements=$ENT_MODE"
echo "targets=$COUNT"
echo

FAIL=0
IDX=0
while IFS= read -r f; do
	IDX=$((IDX + 1))
	rel=${f#"$APP_DIR/"}
	bid=$(lookup_bundle_id "$f" || true)

	if is_encrypted_macho "$f"; then
		if [ "$f" = "$MAIN_EXE_PATH" ]; then
			echo "FAIL encrypted main binary (cryptid != 0): $rel" >&2
			exit 1
		else
			echo "WARN encrypted nested binary (cryptid != 0), skipping CoreTrust sign: $rel" >&2
			continue
		fi
	fi

	ent_file=""
	if [ -n "$bid" ]; then
		ent_file=$(make_ent_for_bundle "$bid" "$IDX")
	fi

	if [ "$DRY_RUN" -eq 1 ]; then
		if [ -n "$ent_file" ]; then
			printf '+ %s --entitlements %s %s\n' "$FASTPATH_SIGN" "$ent_file" "$f"
		else
			printf '+ %s %s\n' "$FASTPATH_SIGN" "$f"
		fi
		continue
	fi

	if [ -n "$ent_file" ]; then
		out=$("$FASTPATH_SIGN" --entitlements "$ent_file" "$f" 2>&1) || true
	else
		out=$("$FASTPATH_SIGN" "$f" 2>&1) || true
	fi
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
	if [ -n "$bid" ]; then
		echo "OK $rel (bundle=$bid) cdhash=$cdhash team=$team"
	else
		echo "OK $rel (lib/helper) cdhash=$cdhash team=$team"
	fi
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
