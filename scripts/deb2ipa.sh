#!/bin/sh
# deb2ipa.sh — Convert an open-source tvOS .deb package (containing Applications/*.app) into a clean .ipa.
#
# Usage:
#   ./scripts/deb2ipa.sh [--dry-run] [--store] -o <output.ipa> <input.deb>
#
# Notes:
# - Works on macOS (using native ar + tar + zip) and Linux (dpkg-deb or ar + tar + zip).
# - Strips any jailbreak .jbroot symlinks if present and preserves original permissions.
# - Never touches any device and never includes third-party binaries.
set -eu

DRY_RUN=0
ZIP_FLAGS="-rq"
OUT_IPA=""

usage() {
	cat <<'USAGE'
Usage: deb2ipa.sh [--dry-run] [--store] [-o <output.ipa>] <input.deb>

  --dry-run               Print planned extraction and packaging steps without modifying files
  --store                 Use zero-compression zip (-0rq) for faster packaging of large apps (e.g. Kodi)
  -o, --output <out.ipa>  Output .ipa path (default: <input-basename>.ipa in current directory)
  -h, --help              Show this help message
USAGE
}

[ $# -gt 0 ] || { usage >&2; exit 2; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--store) ZIP_FLAGS="-0rq"; shift ;;
		-o|--output)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			OUT_IPA=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) break ;;
	esac
done

DEB_PATH=${1:-}
[ -n "$DEB_PATH" ] || { echo "Missing <input.deb>" >&2; usage >&2; exit 2; }
[ -f "$DEB_PATH" ] || { echo "Input .deb not found: $DEB_PATH" >&2; exit 2; }

if [ -z "$OUT_IPA" ]; then
	OUT_IPA="$(basename "$DEB_PATH" .deb).ipa"
fi

if [ "$DRY_RUN" -eq 1 ]; then
	echo "Input .deb : $DEB_PATH"
	echo "Output .ipa: $OUT_IPA"
	echo "Zip flags  : $ZIP_FLAGS"
	echo "+ extract Applications/*.app from $DEB_PATH into Payload/"
	echo "+ remove any .jbroot symlinks"
	echo "+ zip $ZIP_FLAGS $OUT_IPA Payload"
	echo "dry-run complete, no files written"
	exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/deb2ipa.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/deb" "$WORK/extract" "$WORK/stage/Payload"

if command -v dpkg-deb >/dev/null 2>&1; then
	dpkg-deb -x "$DEB_PATH" "$WORK/extract"
else
	ABS_DEB=$(cd "$(dirname "$DEB_PATH")" && pwd)/$(basename "$DEB_PATH")
	(cd "$WORK/deb" && ar x "$ABS_DEB")
	DATA_TAR=$(find "$WORK/deb" -maxdepth 1 -name 'data.tar*' | head -1)
	[ -n "$DATA_TAR" ] || { echo "No data.tar.* member found in $DEB_PATH" >&2; exit 1; }
	case "$DATA_TAR" in
		*.zst)
			command -v zstd >/dev/null 2>&1 || { echo "zstd required to extract $DATA_TAR" >&2; exit 1; }
			zstd -dc "$DATA_TAR" | tar -xf - -C "$WORK/extract"
			;;
		*)
			tar -xf "$DATA_TAR" -C "$WORK/extract"
			;;
	esac
fi

APP_PATH=$(find "$WORK/extract" -maxdepth 4 -type d -name '*.app' | head -1)
[ -n "$APP_PATH" ] || { echo "No *.app bundle found inside $DEB_PATH" >&2; exit 1; }

APP_NAME=$(basename "$APP_PATH")
cp -R "$APP_PATH" "$WORK/stage/Payload/$APP_NAME"
find "$WORK/stage/Payload/$APP_NAME" -name '.jbroot' -delete

OUT_DIR=$(dirname "$OUT_IPA")
mkdir -p "$OUT_DIR"
ABS_OUT=$(cd "$OUT_DIR" && pwd)/$(basename "$OUT_IPA")
rm -f "$ABS_OUT"

(cd "$WORK/stage" && zip "$ZIP_FLAGS" "$ABS_OUT" Payload)
echo "Created IPA: $ABS_OUT (bundle: $APP_NAME)"
