#!/bin/sh
# Local open-source hygiene, syntax, dry-run, link, and build verification suite.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    printf 'PASS: %s\n' "$1"
}

ng() {
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

echo "== 1. Shell syntax (sh -n) =="
for s in scripts/*.sh tests/*.sh; do
    if sh -n "$s"; then
        ok "sh -n $s"
    else
        ng "sh -n $s"
    fi
done

echo "== 2. shellcheck -S warning =="
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -S warning scripts/*.sh tests/*.sh; then
        ok "shellcheck -S warning"
    else
        ng "shellcheck -S warning"
    fi
else
    echo "SKIP: shellcheck not installed"
fi

echo "== 3. plist lint =="
for p in src/probe/Demo.app/Info.plist src/probe/Demo.app/Frameworks/ProbeKit.framework/Info.plist src/probe/demo.ent; do
    if command -v plutil >/dev/null 2>&1; then
        if plutil -lint "$p" >/dev/null 2>&1; then
            ok "plutil -lint $p"
        else
            ng "plutil -lint $p"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -c "import plistlib, sys; plistlib.load(open(sys.argv[1], 'rb'))" "$p" >/dev/null 2>&1; then
            ok "plistlib lint $p"
        else
            ng "plistlib lint $p"
        fi
    else
        echo "SKIP: neither plutil nor python3 available for $p"
    fi
done

echo "== 4. CLI --help and --dry-run smoke =="
if ./scripts/sign-coretrust.sh --help >/dev/null &&
   ./scripts/stage2-verify.sh --help >/dev/null &&
   ./scripts/install-probe.sh --help >/dev/null &&
   ./scripts/deb2ipa.sh --help >/dev/null &&
   ./scripts/invert-tvos-icon.sh --help >/dev/null &&
   ./scripts/repack-ipa.sh --help >/dev/null &&
   ./scripts/build-youtube-tvos.sh --help >/dev/null; then
    ok "all scripts --help"
else
    ng "scripts --help"
fi

if ./scripts/stage2-verify.sh --dry-run | grep -q '<none>' &&
   ./scripts/install-probe.sh --dry-run >/dev/null &&
   ./scripts/invert-tvos-icon.sh --dry-run -o /tmp/dummy-out.car /tmp/dummy-in.car >/dev/null &&
   ./scripts/build-youtube-tvos.sh --dry-run /tmp/dummy.ipa | grep -q 'Invert Icon    : 1' &&
   ./scripts/build-youtube-tvos.sh --dry-run --no-invert-icon /tmp/dummy.ipa | grep -q 'Invert Icon    : 0'; then
    ok "stage2-verify, install-probe, invert-tvos-icon & build-youtube-tvos --dry-run"
else
    ng "stage2-verify / install-probe / invert-tvos-icon / build-youtube-tvos --dry-run"
fi

echo "== 4b. deb2ipa.sh & repack-ipa.sh end-to-end synthetic tests =="
TMP_SYN=$(mktemp -d "${TMPDIR:-/tmp}/tsltv-syn-test.XXXXXX")
mkdir -p "$TMP_SYN/debroot/Applications/SynTest.app" "$TMP_SYN/ctrlroot" "$TMP_SYN/debbuild"
cat > "$TMP_SYN/debroot/Applications/SynTest.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.syntest</string>
<key>CFBundleDisplayName</key><string>SynTest</string>
<key>CFBundleName</key><string>SynTest</string>
<key>CFBundleExecutable</key><string>SynTest</string>
</dict></plist>
PLIST
printf '#!/bin/sh\nexit 0\n' > "$TMP_SYN/debroot/Applications/SynTest.app/SynTest"
chmod 755 "$TMP_SYN/debroot/Applications/SynTest.app/SynTest"
ln -s / "$TMP_SYN/debroot/Applications/SynTest.app/.jbroot"
cat > "$TMP_SYN/ctrlroot/control" <<'CTRL'
Package: com.example.syntest
Version: 1.0.0
Architecture: appletvos-arm64
Maintainer: Test <test@example.com>
Description: Synthetic test deb
CTRL
if command -v dpkg-deb >/dev/null 2>&1; then
    mkdir -p "$TMP_SYN/debroot/DEBIAN"
    cp "$TMP_SYN/ctrlroot/control" "$TMP_SYN/debroot/DEBIAN/control"
    dpkg-deb -b "$TMP_SYN/debroot" "$TMP_SYN/syntest.deb" >/dev/null
else
    (cd "$TMP_SYN/ctrlroot" && tar -czf "$TMP_SYN/debbuild/control.tar.gz" control)
    (cd "$TMP_SYN/debroot" && tar -czf "$TMP_SYN/debbuild/data.tar.gz" Applications)
    printf '2.0\n' > "$TMP_SYN/debbuild/debian-binary"
    (cd "$TMP_SYN/debbuild" && ar rcS "$TMP_SYN/syntest.deb" debian-binary control.tar.gz data.tar.gz)
fi

if ./scripts/deb2ipa.sh --dry-run "$TMP_SYN/syntest.deb" >/dev/null &&
   ./scripts/deb2ipa.sh --store -o "$TMP_SYN/syntest.ipa" "$TMP_SYN/syntest.deb" >/dev/null &&
   unzip -l "$TMP_SYN/syntest.ipa" | grep -q 'Payload/SynTest.app/Info.plist' &&
   ! unzip -l "$TMP_SYN/syntest.ipa" | grep -q '\.jbroot'; then
    ok "deb2ipa.sh synthetic .deb -> .ipa (strips .jbroot)"
else
    ng "deb2ipa.sh synthetic .deb -> .ipa"
fi

if ./scripts/repack-ipa.sh --dry-run "$TMP_SYN/syntest.ipa" | grep -q 'Invert Icon  : auto' &&
   ./scripts/repack-ipa.sh --dry-run --no-invert-icon "$TMP_SYN/syntest.ipa" | grep -q 'Invert Icon  : off' &&
   ./scripts/repack-ipa.sh --no-invert-icon --bundle-id com.example.repacked --display-name "Repacked App" --entitlements preserve -o "$TMP_SYN/repacked.ipa" "$TMP_SYN/syntest.ipa" >/dev/null &&
   unzip -p "$TMP_SYN/repacked.ipa" Payload/SynTest.app/Info.plist | grep -q 'com.example.repacked' &&
   unzip -p "$TMP_SYN/repacked.ipa" Payload/SynTest.app/Info.plist | grep -q 'Repacked App'; then
    ok "repack-ipa.sh synthetic .ipa repack (default auto-invert, --no-invert-icon, bundle-id + display-name)"
else
    ng "repack-ipa.sh synthetic .ipa repack"
fi
rm -rf "$TMP_SYN"

echo "== 5. Probe build & sign-coretrust --dry-run =="
SDK=${SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk}
if [ -d "$SDK" ]; then
    TMP_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tsltv-test-build.XXXXXX")
    trap 'rm -rf "$TMP_BUILD"' EXIT INT TERM
    if OUT="$TMP_BUILD/Demo.app" ./scripts/build-probe.sh >/dev/null &&
       ./scripts/sign-coretrust.sh --dry-run --entitlements minimal "$TMP_BUILD/Demo.app" >/dev/null; then
        ok "build-probe + sign-coretrust --dry-run (.app)"
    else
        ng "build-probe / sign-coretrust --dry-run"
    fi
    if (cd "$TMP_BUILD" && mkdir -p Payload && cp -R Demo.app Payload/ && zip -qr Demo.ipa Payload) &&
       ./scripts/sign-coretrust.sh --dry-run --entitlements minimal -o "$TMP_BUILD/nested/out.ipa" "$TMP_BUILD/Demo.ipa" >/dev/null; then
        ok "sign-coretrust --dry-run (.ipa + nested -o)"
    else
        ng "sign-coretrust --dry-run (.ipa)"
    fi
else
    echo "SKIP: tvOS SDK not found at $SDK"
fi

echo "== 6. Open-source privacy & hygiene checks =="
LEAK_RE='192\.168\.|10\.8\.|10\.222\.|/Users/[A-Za-z0-9._-]+|ooxx|peng0324|chinazp|WV4ADEUMV4|51f98000|<tsltv-nonlite-repo>|<trollstore-lite-tv-repo>|\.jbroot-[0-9A-Fa-f]{16}|(^|[^/a-zA-Z0-9_])/tmp/tsltv-(nonlite|full-work|probe)'
if grep -rnE "$LEAK_RE" \
    README.md README.zh-CN.md CHANGELOG.md LICENSE NOTICE CONTRIBUTING.md SECURITY.md vendor/README.md .github scripts src docs --exclude-dir=.git >/dev/null 2>&1; then
    grep -rnE "$LEAK_RE" \
        README.md README.zh-CN.md CHANGELOG.md LICENSE NOTICE CONTRIBUTING.md SECURITY.md vendor/README.md .github scripts src docs --exclude-dir=.git >&2
    ng "privacy/local-path leak scan"
else
    ok "privacy/local-path leak scan (0 hits)"
fi

if [ -e src/probe/Demo.app/Assets.car ]; then
    ng "third-party Assets.car must not be tracked in src/probe"
else
    ok "no third-party Assets.car in src/probe"
fi


if git ls-files | grep -qE '(Assets\.car|fastPathSign|tsverify|\.ipa|\.tipa)$'; then
    git ls-files | grep -E '(Assets\.car|fastPathSign|tsverify|\.ipa|\.tipa)$' >&2
    ng "tracked binary check"
else
    ok "no tracked third-party/compiled binaries"
fi

echo "== 7. Markdown relative link integrity =="
if python3 - <<'PY'
import pathlib, re, sys
root = pathlib.Path(".")
broken = []
for md in list(root.glob("*.md")) + list((root / "docs").rglob("*.md")) + list((root / "vendor").rglob("*.md")):
    txt = md.read_text(encoding="utf-8")
    for m in re.finditer(r'\[[^\]]+\]\(([^)#]+)\)', txt):
        target = m.group(1).strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        resolved = (md.parent / target).resolve()
        if not resolved.exists():
            broken.append(f"{md}: broken link -> {target}")
if broken:
    for b in broken:
        print(b, file=sys.stderr)
    sys.exit(1)
PY
then
    ok "markdown relative links (0 broken)"
else
    ng "markdown relative links"
fi

echo "----------------------------------------"
printf 'PASS %d / FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
