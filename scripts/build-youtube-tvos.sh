#!/bin/sh
# build-youtube-tvos.sh — Bring-Your-Own-IPA (BYOIPA) builder for YouTube tvOS with upstream
# TizenTube Cobalt userscript support, ready for non-Lite TrollStore TV installation.
#
# Usage:
#   ./scripts/build-youtube-tvos.sh [options] -o <output.ipa> <decrypted-youtube.ipa>
#
# Compliance & Third-Party Credits:
# - Contains ZERO copyrighted binaries, IPA files, artwork, or FairPlay decryption code.
# - Operates strictly on a user-supplied, locally decrypted .ipa (cryptid == 0).
# - Delegates binary userscript-loader patching to clean-room MIT comicchang/tvos-cobalt-userscript.
# - Default runtime userscript URL loads upstream TizenTube (@foxreis/tizentube,
#   https://github.com/reisxd/TizenTube, GPL-3.0; companion: https://github.com/reisxd/TizenTubeCobalt,
#   BSD-3-Clause), which integrates SponsorBlock (https://github.com/ajayyy/SponsorBlock) and
#   DeArrow (https://github.com/ajayyy/DeArrow) at runtime — none are vendored in this repository.
# - Icon inversion is ON by default (visual distinction from stock App Store YouTube); pass
#   --no-invert-icon to keep the original icon.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DRY_RUN=0
BUNDLE_ID="com.google.ios.youtube.tvos"
DISPLAY_NAME="YouTube TV"
APP_NAME="YouTubeTV.app"
PROFILE="youtube-tvos-4.54.01"
USERSCRIPT_URL="https://cdn.jsdelivr.net/npm/@foxreis/tizentube/dist/userScript.js"
FALLBACK_URL=""
EXTRA_CSP=""
INVERT_ICON=1
NO_4K_PATCH=0
NO_HDR_PATCHES=0
STORE_FLAG=""
OUT_IPA=""
COBALT_PATCHER_DIR=${COBALT_PATCHER_DIR:-}
COBALT_PATCHER_REPO=${COBALT_PATCHER_REPO:-https://github.com/comicchang/tvos-cobalt-userscript.git}

usage() {
	cat <<'USAGE'
Usage: build-youtube-tvos.sh [options] [-o <output.ipa>] <decrypted-youtube.ipa>

  --dry-run                  Print planned build steps without modifying files
  --bundle-id <id>           Side-by-side CFBundleIdentifier [default: com.google.ios.youtube.tvos]
  --display-name <name>      Home Screen display name [default: YouTube TV]
  --app-name <Name.app>      Payload bundle folder name [default: YouTubeTV.app]
  --profile <name|path>      cobalt-patcher profile [default: youtube-tvos-4.54.01]
  --userscript-url <url>     Userscript URL loaded by Cobalt at runtime
                             [default: https://cdn.jsdelivr.net/npm/@foxreis/tizentube/dist/userScript.js]
  --fallback-url <url>       Optional fallback userscript URL [default: none]
  --extra-csp <origin>       Extra CSP origin to whitelist (optional)
  --invert-icon              Invert tvOS icon Assets.car to distinguish from stock app [default: ON]
  --no-invert-icon           Disable default icon inversion and keep original icon
  --no-4k-patch              Skip MediaSource 4K JS shim
  --no-hdr-patches           Skip Cobalt VP9/HDR binary gate patches
  --store                    Use zero-compression zip (-0rq) for faster packaging
  -o, --output <out.ipa>     Output .ipa path [default: YouTubeTV-trollstore.ipa]
  -h, --help                 Show this help message

Environment:
  COBALT_PATCHER_DIR         Path to local tvos-cobalt-userscript checkout
                             (auto-detects ../tvos-cobalt-userscript or clones on demand)
USAGE
}

[ $# -gt 0 ] || { usage >&2; exit 2; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--bundle-id)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			BUNDLE_ID=$2; shift 2 ;;
		--display-name)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			DISPLAY_NAME=$2; shift 2 ;;
		--app-name)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			APP_NAME=$2; shift 2 ;;
		--profile)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			PROFILE=$2; shift 2 ;;
		--userscript-url)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			USERSCRIPT_URL=$2; shift 2 ;;
		--fallback-url)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			FALLBACK_URL=$2; shift 2 ;;
		--extra-csp)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			EXTRA_CSP=$2; shift 2 ;;
		--invert-icon) INVERT_ICON=1; shift ;;
		--no-invert-icon) INVERT_ICON=0; shift ;;
		--no-4k-patch) NO_4K_PATCH=1; shift ;;
		--no-hdr-patches) NO_HDR_PATCHES=1; shift ;;
		--store) STORE_FLAG="--store"; shift ;;
		-o|--output)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			OUT_IPA=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) break ;;
	esac
done

INPUT_IPA=${1:-}
[ -n "$INPUT_IPA" ] || { echo "Missing <decrypted-youtube.ipa>" >&2; usage >&2; exit 2; }
[ -n "$OUT_IPA" ] || OUT_IPA="YouTubeTV-trollstore.ipa"

resolve_patcher_dir() {
	if [ -n "$COBALT_PATCHER_DIR" ] && [ -d "$COBALT_PATCHER_DIR" ]; then
		printf '%s\n' "$COBALT_PATCHER_DIR"
		return 0
	fi
	if [ -d "$ROOT/../tvos-cobalt-userscript" ]; then
		(cd "$ROOT/../tvos-cobalt-userscript" && pwd)
		return 0
	fi
	printf '%s\n' ""
}

PATCHER_DIR=$(resolve_patcher_dir)

if [ "$DRY_RUN" -eq 1 ]; then
	echo "Input IPA      : $INPUT_IPA"
	echo "Output IPA     : $OUT_IPA"
	echo "Bundle ID      : $BUNDLE_ID"
	echo "Display Name   : $DISPLAY_NAME ($APP_NAME)"
	echo "Profile        : $PROFILE"
	echo "Userscript URL : $USERSCRIPT_URL"
	echo "Fallback URL   : ${FALLBACK_URL:-<none>}"
	echo "Invert Icon    : $INVERT_ICON (pass --no-invert-icon to disable)"
	echo "Patcher Dir    : ${PATCHER_DIR:-<will clone $COBALT_PATCHER_REPO into temp dir>}"
	echo "+ step 1: run cobalt-patcher (verifies cryptid==0, injects ARM64 userscript + CSP hooks)"
	if [ "$INVERT_ICON" -eq 1 ]; then
		echo "+ step 2: run $ROOT/scripts/repack-ipa.sh --entitlements sandbox --allow-alt-video-decoder (icon invert ON)"
	else
		echo "+ step 2: run $ROOT/scripts/repack-ipa.sh --no-invert-icon --entitlements sandbox --allow-alt-video-decoder"
	fi
	echo "dry-run complete, no files written"
	exit 0
fi

[ -f "$INPUT_IPA" ] || { echo "Decrypted input IPA not found: $INPUT_IPA" >&2; exit 2; }
command -v uv >/dev/null 2>&1 || { echo "uv is required to run tvos-cobalt-userscript (https://docs.astral.sh/uv/)" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/build-yt-tvos.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -z "$PATCHER_DIR" ]; then
	echo "== Fetching tvos-cobalt-userscript from $COBALT_PATCHER_REPO =="
	git clone --depth 1 "$COBALT_PATCHER_REPO" "$WORK/tvos-cobalt-userscript"
	PATCHER_DIR="$WORK/tvos-cobalt-userscript"
fi

ABS_IN=$(cd "$(dirname "$INPUT_IPA")" && pwd)/$(basename "$INPUT_IPA")
PATCHED_IPA="$WORK/youtube-patched.ipa"

echo "== 1. Patching decrypted YouTube IPA with cobalt-patcher =="
set -- uv run --directory "$PATCHER_DIR" cobalt-patcher \
	--in "$ABS_IN" \
	--out "$PATCHED_IPA" \
	--profile "$PROFILE" \
	--userscript-url "$USERSCRIPT_URL" \
	--fallback-url "$FALLBACK_URL" \
	--bundle-id "$BUNDLE_ID" \
	--display-name "$DISPLAY_NAME" \
	--app-name "$APP_NAME"
[ -n "$EXTRA_CSP" ] && set -- "$@" --extra-csp "$EXTRA_CSP"
[ "$NO_4K_PATCH" -eq 1 ] && set -- "$@" --no-4k-patch
[ "$NO_HDR_PATCHES" -eq 1 ] && set -- "$@" --no-hdr-patches
"$@"

echo "== 2. Repackaging for TrollStore TV (sandbox entitlements + icon policy) =="
set -- "$ROOT/scripts/repack-ipa.sh" \
	--bundle-id "$BUNDLE_ID" \
	--display-name "$DISPLAY_NAME" \
	--entitlements sandbox \
	--allow-alt-video-decoder \
	-o "$OUT_IPA"
if [ "$INVERT_ICON" -eq 1 ]; then
	set -- "$@" --invert-icon
else
	set -- "$@" --no-invert-icon
fi
[ -n "$STORE_FLAG" ] && set -- "$@" "$STORE_FLAG"
set -- "$@" "$PATCHED_IPA"
"$@"

echo "Ready for TrollStore TV installation: $OUT_IPA"
