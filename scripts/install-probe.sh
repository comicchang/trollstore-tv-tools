#!/bin/sh
# Install and launch the independent probe app on a jailbroken Apple TV (Stage 1 recipe).
# Device-side root elevation uses interactive sudo only; no passwords are stored.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_DIR="$ROOT/build/Demo.app"
resolve_tsverify() {
    if [ -n "${TSVERIFY:-}" ]; then
        printf '%s\n' "$TSVERIFY"
        return 0
    fi
    if command -v tsverify >/dev/null 2>&1; then
        command -v tsverify
        return 0
    fi
    printf '%s\n' "${HOME:-/tmp}/.local/share/tsltv-tools/tsverify"
}
TSVERIFY=$(resolve_tsverify)
DEVICE=${DEVICE:-}
SSH_USER=${SSH_USER:-mobile}
BUNDLE_ID=${BUNDLE_ID:-com.tsltv.verify.demo}
REMOTE_DIR=/rootfs/private/var/tmp/tsltv-verify-demo

DRY_RUN=0
case ${1:-} in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
        echo "Usage: DEVICE=<apple-tv-ip> $0 [--dry-run]"
        exit 0
        ;;
    "") ;;
    *)
        echo "Usage: DEVICE=<apple-tv-ip> $0 [--dry-run]" >&2
        exit 2
        ;;
esac
[ "$#" -le 1 ] || { echo "Usage: DEVICE=<apple-tv-ip> $0 [--dry-run]" >&2; exit 2; }

if [ -z "$DEVICE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        DEVICE="192.0.2.10"
    else
        echo "Missing Apple TV address: set DEVICE=<apple-tv-ip>" >&2
        exit 2
    fi
fi

TARGET="$SSH_USER@$DEVICE"

case "$BUNDLE_ID" in
    ''|*[!A-Za-z0-9.-]*)
        echo "Invalid BUNDLE_ID: $BUNDLE_ID" >&2
        exit 2
        ;;
esac

shell_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

print_command() {
    printf '+ %s\n' "$1"
}

REMOTE_SCRIPT=$(cat <<'REMOTE_SCRIPT_EOF'
set -eu

BUNDLE_ID=$1
REMOTE_DIR=/rootfs/private/var/tmp/tsltv-verify-demo
APP_DIR="$REMOTE_DIR/Demo.app"
ENTITLEMENTS="$REMOTE_DIR/entitlements.plist"
MAIN_BINARY="$APP_DIR/Demo"
FRAMEWORK_BINARY="$APP_DIR/Frameworks/ProbeKit.framework/ProbeKit"
TSVERIFY="$REMOTE_DIR/tsverify"

cat > "$ENTITLEMENTS" <<ENTITLEMENTS_EOF
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
ENTITLEMENTS_EOF

JB=$(ls -d /var/containers/Bundle/Application/.jbroot-* 2>/dev/null | head -n 1)
[ -n "$JB" ] || { echo "Jailbreak .jbroot-* directory not found" >&2; exit 1; }
JBCTL=""
for cand in "$JB/basebin/jbctl" "$JB/usr/bin/jbctl"; do
    if [ -x "$cand" ]; then JBCTL=$cand; break; fi
done
LDID="$JB/usr/bin/ldid"
if [ ! -x "$LDID" ]; then
    LDID=$(command -v ldid 2>/dev/null || true)
fi
[ -n "$LDID" ] && [ -x "$LDID" ] || { echo "ldid not found" >&2; exit 1; }
[ -n "$JBCTL" ] || { echo "jbctl not found under $JB" >&2; exit 1; }

"$LDID" -S"$ENTITLEMENTS" -Cadhoc -Hsha1 -Hsha256 "$MAIN_BINARY"
"$LDID" -S"$ENTITLEMENTS" -Cadhoc -Hsha1 -Hsha256 "$FRAMEWORK_BINARY"

trust_one() {
    original_path=$1
    temporary_name=$2
    if "$JBCTL" trustcache add "$original_path" >/dev/null 2>&1; then
        chmod 755 "$original_path"
        return 0
    fi
    temporary_path="/rootfs/var/tmp/$temporary_name"
    rm -f "$temporary_path"
    cp "$original_path" "$temporary_path" || return 1
    if "$JBCTL" trustcache add "/var/tmp/$temporary_name" >/dev/null 2>&1; then
        rm -f "$original_path"
        cp "$temporary_path" "$original_path" || return 1
        chmod 755 "$original_path"
        rm -f "$temporary_path"
        return 0
    fi
    rm -f "$temporary_path"
    return 1
}

trust_one "$MAIN_BINARY" tsltv-ts.main || { echo "Failed to trust main binary" >&2; exit 1; }
trust_one "$FRAMEWORK_BINARY" tsltv-ts.ProbeKit || { echo "Failed to trust ProbeKit" >&2; exit 1; }

chmod 755 "$TSVERIFY"
DEPLOY_OUTPUT=$("$TSVERIFY" deploy /var/tmp/tsltv-verify-demo/Demo.app "$BUNDLE_ID")
printf '%s\n' "$DEPLOY_OUTPUT"
APP_PATH=$(printf '%s\n' "$DEPLOY_OUTPUT" | sed -n 's/.*app_bundle=\([^[:space:]]*\).*/\1/p' | tail -n 1)
[ -n "$APP_PATH" ] || { echo "deploy did not return app_bundle path" >&2; exit 1; }

uicache -p "$APP_PATH"
uiopen --bundleid "$BUNDLE_ID"

sleep 3
printf '\n===== %s =====\n' /rootfs/private/var/tmp/tsltv-probe-boot.log
if [ -f /rootfs/private/var/tmp/tsltv-probe-boot.log ]; then
    tail -n 80 /rootfs/private/var/tmp/tsltv-probe-boot.log
else
    echo "(log absent)"
fi
printf '\n===== %s =====\n' /rootfs/private/var/tmp/tsltv-probe.log
if [ -f /rootfs/private/var/tmp/tsltv-probe.log ]; then
    tail -n 120 /rootfs/private/var/tmp/tsltv-probe.log
else
    echo "(log absent)"
fi
REMOTE_SCRIPT_EOF
)

REMOTE_COMMAND="sudo sh -c $(shell_quote "$REMOTE_SCRIPT") tsltv-install-probe $(shell_quote "$BUNDLE_ID")"

if [ "$DRY_RUN" -eq 1 ]; then
    print_command "ssh -t $TARGET 'sudo rm -rf $REMOTE_DIR && sudo mkdir -p $REMOTE_DIR && sudo chown $SSH_USER $REMOTE_DIR && chmod 700 $REMOTE_DIR'"
    print_command "scp -r $APP_DIR $TSVERIFY $TARGET:$REMOTE_DIR/"
    print_command "ssh -t $TARGET $REMOTE_COMMAND"
    exit 0
fi

[ -d "$APP_DIR" ] || { echo "Probe app not built: $APP_DIR" >&2; exit 1; }
[ -f "$APP_DIR/Demo" ] || { echo "Main binary missing: $APP_DIR/Demo" >&2; exit 1; }
[ -f "$APP_DIR/Frameworks/ProbeKit.framework/ProbeKit" ] || {
    echo "ProbeKit missing: $APP_DIR/Frameworks/ProbeKit.framework/ProbeKit" >&2
    exit 1
}
[ -f "$TSVERIFY" ] || { echo "tsverify not found: $TSVERIFY (set TSVERIFY=...)" >&2; exit 1; }

command -v ssh >/dev/null 2>&1 || { echo "ssh not found" >&2; exit 1; }
command -v scp >/dev/null 2>&1 || { echo "scp not found" >&2; exit 1; }

ssh -t "$TARGET" "sudo rm -rf '$REMOTE_DIR' && sudo mkdir -p '$REMOTE_DIR' && sudo chown '$SSH_USER' '$REMOTE_DIR' && chmod 700 '$REMOTE_DIR'"
scp -r "$APP_DIR" "$TSVERIFY" "$TARGET:$REMOTE_DIR/"
ssh -t "$TARGET" "$REMOTE_COMMAND"
