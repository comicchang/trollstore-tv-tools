#!/bin/sh
# stage2-verify.sh — Post-reboot Stage 2 verification (read-only by default, never reboots)
#
# Usage:
#   ./scripts/stage2-verify.sh [--dry-run] [--launch] --device <ip> [--user <user>]
#
# Default (read-only) checks:
#   1. Detect whether jailbreak (.jbroot-* / jbctl) is active
#   2. Read trustcache entry count vs Stage 1 baseline
#   3. Inspect primary (and optional) test app path + Mach-O CDHash / TeamIdentifier
#   4. Check CrashReporter for new .ips logs in the last 30 minutes
#   5. Print probe logs if present
#
# Pass --launch to explicitly trigger uiopen (off by default; avoid when TV display is off).
# Never reboots, never installs or uninstalls any app.
set -eu

DEVICE=${DEVICE:-}
SSH_USER=${SSH_USER:-mobile}
BASELINE_TRUSTCACHE=${BASELINE_TRUSTCACHE:-634}
PRIMARY_BID=${PRIMARY_BID:-com.aapl.relaxin.test}
OPTIONAL_BID=${OPTIONAL_BID:-}

DRY_RUN=0
DO_LAUNCH=0

usage() {
	cat <<'USAGE'
Usage: stage2-verify.sh [--dry-run] [--launch] --device <ip> [--user <user>]

  --dry-run       Print the remote verification command without connecting
  --launch        Explicitly run uiopen launch check (off by default)
  --device <ip>   Apple TV IP/hostname (or set DEVICE env var; dry-run defaults to 192.0.2.10)
  --user <user>   SSH user (default: mobile)

Environment:
  DEVICE, SSH_USER, BASELINE_TRUSTCACHE (default 634),
  PRIMARY_BID (default com.aapl.relaxin.test), OPTIONAL_BID (optional second bundle ID)
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--launch) DO_LAUNCH=1; shift ;;
		--device)
			[ $# -ge 2 ] || { echo "Missing value for --device" >&2; exit 2; }
			DEVICE=$2; shift 2 ;;
		--user)
			[ $# -ge 2 ] || { echo "Missing value for --user" >&2; exit 2; }
			SSH_USER=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

if [ -z "$DEVICE" ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		DEVICE="192.0.2.10"
	else
		echo "Missing Apple TV address: pass --device <ip> or set DEVICE=<ip>" >&2
		usage >&2
		exit 2
	fi
fi

REMOTE_SCRIPT=$(cat <<'REMOTE_SCRIPT_EOF'
set +e

BASELINE_TRUSTCACHE=$1
PRIMARY_BID=$2
OPTIONAL_BID=$3
DO_LAUNCH=$4
[ "$OPTIONAL_BID" = "__NONE__" ] && OPTIONAL_BID=""

echo "===== 1. Jailbreak State ====="
JBROOT=$(ls -d /var/containers/Bundle/Application/.jbroot-* 2>/dev/null | head -1)
if [ -n "$JBROOT" ]; then
	echo "jailbroken=yes jbroot=$JBROOT"
else
	echo "jailbroken=no (.jbroot-* not found)"
fi

JBCTL=""
for cand in "$JBROOT/basebin/jbctl" "$JBROOT/usr/bin/jbctl" /usr/bin/jbctl; do
	if [ -n "$cand" ] && [ -x "$cand" ]; then
		JBCTL=$cand
		break
	fi
done
if [ -n "$JBCTL" ]; then
	echo "jbctl=$JBCTL"
else
	echo "jbctl=absent"
fi

echo
echo "===== 2. Trustcache ====="
if [ -n "$JBCTL" ]; then
	"$JBCTL" trustcache info 2>/dev/null | grep -E 'Entries|Managed' || echo "trustcache=unavailable"
	ENTRIES=$("$JBCTL" trustcache info 2>/dev/null | sed -n 's/.*Entries: \([0-9]*\).*/\1/p' | head -1)
else
	ENTRIES=""
fi
echo "entries=${ENTRIES:-unknown} baseline=$BASELINE_TRUSTCACHE"

echo
echo "===== 3. Target App & CDHashes ====="
for bid in "$PRIMARY_BID" "$OPTIONAL_BID"; do
	[ -n "$bid" ] || continue
	APP=$(uicache -i "$bid" 2>/dev/null | awk -F': ' '/^Path:/{print $2; exit}')
	if [ -z "$APP" ] || [ ! -d "$APP" ]; then
		echo "$bid: NOT_INSTALLED"
		continue
	fi
	echo "$bid: $APP"
	EXE=$(uicache -i "$bid" 2>/dev/null | awk -F': ' '/^Executable Name:/{print $2; exit}')
	[ -n "$EXE" ] || EXE=$(basename "$APP" .app)
	[ -f "$APP/$EXE" ] && echo "  main cdhash=$(ldid -h "$APP/$EXE" 2>/dev/null | sed -n 's/^CDHash=//p' | head -1) team=$(ldid -h "$APP/$EXE" 2>/dev/null | sed -n 's/^TeamIdentifier=//p' | head -1)"
	for f in "$APP"/Frameworks/*.framework; do
		[ -d "$f" ] || continue
		fexe=$(basename "$f" .framework)
		[ -f "$f/$fexe" ] && echo "  $(basename "$f"): $(ldid -h "$f/$fexe" 2>/dev/null | sed -n 's/^CDHash=//p' | head -1)"
	done
	for d in "$APP"/*.dylib; do
		[ -f "$d" ] || continue
		echo "  $(basename "$d"): $(ldid -h "$d" 2>/dev/null | sed -n 's/^CDHash=//p' | head -1)"
	done
done

echo
echo "===== 4. CrashReporter (last 30m) ====="
find /private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -type f -mmin -30 2>/dev/null | head -20
echo "(empty means no new crashes)"

echo
echo "===== 5. Probe Logs (if present) ====="
for p in \
	/var/containers/Bundle/Application/.jbroot-*/var/mobile/Containers/Data/Application/*/tmp/probe.log \
	/var/containers/Bundle/Application/.jbroot-*/var/mobile/Documents/probe.log \
	/private/var/tmp/tsltv-probe.log \
	/var/tmp/tsltv-probe.log ; do
	for f in $p; do
		[ -f "$f" ] || continue
		echo "--- $f"
		tail -20 "$f"
	done
done

echo
echo "===== 6. Launch Check ====="
if [ "$DO_LAUNCH" = "1" ]; then
	for bid in "$PRIMARY_BID" "$OPTIONAL_BID"; do
		[ -n "$bid" ] || continue
		uicache -i "$bid" >/dev/null 2>&1 || continue
		echo "uiopen $bid"
		uiopen --bundleid "$bid" 2>&1
	done
	sleep 6
	ps ax -o pid,user,command 2>/dev/null | grep -E 'RelaxinTest.app/RelaxinTV|Demo.app/Demo' | grep -v grep | head -5
	echo "--- CrashReporter (last 5m) ---"
	find /private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -type f -mmin -5 2>/dev/null | head -10
else
	echo "skipped (pass --launch explicitly when display is active)"
fi

echo
echo "===== 7. Production Baseline ====="
uptime
ps ax -o pid,user,command 2>/dev/null | grep -E 'RelaxinTV.app/RelaxinTV|TrollStoreLiteTV' | grep -v grep | head -5
if [ -n "$JBROOT" ] && [ -f "$JBROOT/usr/libexec/tsltv/installed.tsv" ]; then
	sha256sum "$JBROOT/usr/libexec/tsltv/installed.tsv" 2>/dev/null
fi
REMOTE_SCRIPT_EOF
)

if [ "$DRY_RUN" -eq 1 ]; then
	printf '+ ssh %s@%s <remote readonly script> %s %s %s %s\n' "$SSH_USER" "$DEVICE" "$BASELINE_TRUSTCACHE" "$PRIMARY_BID" "${OPTIONAL_BID:-<none>}" "$DO_LAUNCH"
	printf '%s\n' "$REMOTE_SCRIPT" | sed 's/^/    /' | head -40
	printf '    ... (remote script omitted)\n'
	echo "dry-run complete, did not connect to device"
	exit 0
fi

printf '%s' "$REMOTE_SCRIPT" | ssh -T -o ConnectTimeout=8 "$SSH_USER@$DEVICE" sh -s -- "$BASELINE_TRUSTCACHE" "$PRIMARY_BID" "${OPTIONAL_BID:-__NONE__}" "$DO_LAUNCH"
