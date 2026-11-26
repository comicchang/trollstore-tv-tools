# Cold-Reboot Safety Checklist & Unjailbroken Survival Verification

> **Device**: Apple TV 4K (`AppleTV14,1`), tvOS 17.0 (`21J354`), sealed read-only SSV  
> **Result**: **VERIFIED** — CoreTrust-bypassed (`TeamIdentifier=T8ALTGMVXN`) binaries survive a full cold reboot and launch directly in the unjailbroken state without jailbreak trustcaches.

## 1. Pre-Reboot Safety Checklist (Portless Apple TV 4K)

Because Apple TV 4K has no user-accessible USB-C DFU port, perform these read-only checks before any cold-reboot test:

1. **SSV root integrity**: confirm `/` is mounted as Apple's read-only signed snapshot (`com.apple.os.update-*`, `read-only`).
2. **Untouched system volume**: verify `/Applications` contains only stock factory apps (no PersistenceHelper injections or `*_TROLLSTORE_BACKUP` artifacts) and `/Library/LaunchDaemons` is empty.
3. **Valid system plists**: parse `com.apple.springboard.plist`, `ClientTruth.plist`, and `/var/db/com.apple.xpc.launchd/disabled.plist` with `plutil -p` to ensure valid XML/binary format and no disabled boot-critical daemons.
4. **Disk & NVRAM health**: confirm ample free space on `/private/var` and `/private/var/mobile` (`> 2 GiB`, low inode usage) and clean `nvram -p` (`auto-boot=true`, `bootdelay=0`, no stray `boot-args`).
5. **No staged tvOS OTA update**: check `/private/var/MobileAsset/AssetsV2/` for `com_apple_MobileAsset_SoftwareUpdate*` so rebooting will not trigger an unintended OS upgrade.
6. **Recovery path ready**: ensure an active, non-expired developer-signed launcher or Xcode wireless signing setup is available in case you want to re-enter the jailbroken environment afterward.

## 2. Cold-Reboot Unjailbroken Observations

After executing a clean cold reboot into stock unjailbroken tvOS 17.0:

| Target | Signing Chain | Unjailbroken Launch After Cold Reboot |
| --- | --- | --- |
| `TrollStore.app` (`com.opa334.TrollStore`) | CoreTrust bypass (`T8ALTGMVXN`, `sha1,sha256`), built from `trollstore-tv` | **PASS** — opens directly in unjailbroken state |
| Multi-binary test app (5 Mach-Os: main + embedded framework + 3 dylibs) | CoreTrust bypass (`T8ALTGMVXN`, `sha1,sha256`) | **PASS** — opens directly in unjailbroken state |

## 3. Practical Troubleshooting Lessons Discovered

### 3.1 `Failed to create surface` Under `platform-application` + `no-sandbox`

- **Observation**: A multi-binary app resigned with a generic `no-sandbox` + `no-container` + `platform-application` template opened cleanly in unjailbroken mode, but failed during `IOSurface` creation (`Failed to create surface`).
- **Root Cause**: On tvOS 17, `platform-application` tightens IOKit user-client checks unless `com.apple.security.exception.iokit-user-client-class` explicitly allows `IOSurfaceRootUserClient` / `AGXDeviceUserClient`.
- **Resolution**: Keep standard sandboxed entitlements (`application-identifier`, `get-task-allow`, `keychain-access-groups`, plus `com.apple.private.security.container-required=<bundle-id>` injected automatically by `trollstorehelper`) without forcing `platform-application` or `no-sandbox`.

### 3.2 Inverting Monochrome tvOS Layered Icons (`Assets.car`)

- **Observation**: Running CoreImage `CIColorInvert` directly on monochrome (`gray gamma 22`) tvOS layered `App Icon` assets can leave rendered pixels unchanged.
- **Resolution**: Invert raw RGBA8 pixels explicitly (`255 - R/G/B`, preserving alpha), recompile with Xcode `actool --platform appletvos --target-device tv`, verify rendered corner/center pixels directly via CoreUI, and install into a fresh app container so tvOS `IconServices` does not serve stale cached icons.

## 4. End-to-End Multi-App Installs Verified via `trollstorehelper`

After re-entering SSH to collect post-reboot diagnostics (`./scripts/stage2-verify.sh`), on-device `trollstorehelper` installed and launched three real-world multi-binary tvOS apps with zero jailbreak trustcache writes:

| App Category | Mach-Os Signed (`T8ALTGMVXN`) | Entitlement Model | Runtime Evidence |
| --- | --- | --- | --- |
| Multi-binary app w/ embedded framework & dylibs | 5 | Standard sandbox + `container-required` | Launches cleanly, `0` crashes |
| Decrypted media client | 2 | Standard sandbox + `container-required` + `allow-alternate-video-decoder-selection` | Runs stably (`RSS ~119 MB`), `0` crashes |
| Kodi v21.3 | **108** (main + `kodi-topshelf.appex` + 106 dylibs) | Native `no-container` + IOKit/media entitlements preserved | Runs Python 3.11.7 + FFmpeg H.264/HEVC + migrated `/private/var/mobile/Library/Caches/Kodi` data (`88 MB`, `2,748` files), `0` crashes |
