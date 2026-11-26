#!/bin/sh
# fetch-fastpathsign.sh — 复现宿主机 fastPathSign（CoreTrust bypass 签名器）
#
# 依赖: clang、pkg-config、OpenSSL(libcrypto)、git、Xcode CLT
# 产物: vendor/fastPathSign；如已存在可执行文件则跳过（--force 强制重建）
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM=https://github.com/straight-tamago/TrollStore-tvOS.git
COMMIT=f1ebe52
OUT="$ROOT/vendor/fastPathSign"
FORCE=0

usage() {
	cat <<'USAGE'
Usage: fetch-fastpathsign.sh [--force] [-h|--help]

Reproducibly build host macOS fastPathSign from straight-tamago/TrollStore-tvOS (f1ebe52)
into gitignored vendor/fastPathSign.

  --force     Rebuild even if vendor/fastPathSign already exists
  -h, --help  Show this help message
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		--force) FORCE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

if [ -x "$OUT" ] && [ "$FORCE" -eq 0 ]; then
	echo "Already exists: ${OUT} (pass --force to rebuild)"
	shasum -a 256 "$OUT"
	exit 0
fi

command -v clang >/dev/null || { echo "缺少 clang" >&2; exit 2; }
command -v pkg-config >/dev/null || { echo "缺少 pkg-config" >&2; exit 2; }
pkg-config --exists libcrypto || { echo "缺少 libcrypto（brew install openssl@3 后导出 PKG_CONFIG_PATH）" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fastpathsign.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

git clone -q "$UPSTREAM" "$WORK/up"
git -C "$WORK/up" checkout -q "$COMMIT"
make -C "$WORK/up/Exploits/fastPathSign" clean >/dev/null 2>&1 || true
make -C "$WORK/up/Exploits/fastPathSign"

mkdir -p "$ROOT/vendor"
cp "$WORK/up/Exploits/fastPathSign/fastPathSign" "$OUT"
chmod +x "$OUT"
echo "构建完成: $OUT"
shasum -a 256 "$OUT"
