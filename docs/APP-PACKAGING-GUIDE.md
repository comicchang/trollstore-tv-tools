# App Packaging & Installation Guide (BYOIPA Workflow)

**English** | [简体中文](APP-PACKAGING-GUIDE.zh-CN.md)

This guide explains how to prepare tvOS `.ipa` packages locally from **open-source `.deb` distributions** or **your own legally obtained local apps (Bring Your Own IPA)** and install them via **[`trollstore-tv`](https://github.com/comicchang/trollstore-tv)** so they survive cold reboots in the unjailbroken state.

> **Compliance Notice**: This repository contains **only original packaging, signing, and icon-processing scripts**. It does **not** distribute third-party proprietary IPAs, copyrighted binary pages, brand assets, or DRM-decryption code. All third-party tools referenced below are linked strictly as external upstream projects.

---

## Icon Inversion Toggle (Default ON)

Both [`scripts/repack-ipa.sh`](../scripts/repack-ipa.sh) and [`scripts/build-youtube-tvos.sh`](../scripts/build-youtube-tvos.sh) **enable tvOS icon color inversion by default** on macOS (when Xcode `actool` and `Assets.car` are available) as a practical visual trick so side-by-side custom builds are immediately distinguishable from the stock App Store originals on the Apple TV Home Screen.

To keep the original icon unchanged, simply pass `--no-invert-icon`.

---

## Workflow A: Open-Source `.deb` Packages (e.g. Kodi tvOS)

Many open-source tvOS projects (such as [Kodi](https://github.com/xbmc/xbmc) / [kodi.tv](https://kodi.tv/), GPL-2.0+) publish official `.deb` builds targeting `/Applications/*.app`.

### 1. Download the official `.deb`

Download the official tvOS `.deb` package directly from the upstream project's release page (for example, `org.xbmc.kodi-tvos64` v21.3).

### 2. Convert `.deb` to `.ipa` locally

```sh
./scripts/deb2ipa.sh --store -o Kodi.ipa /path/to/kodi.deb
```

### 3. Install via TrollStore TV

Install `Kodi.ipa` with on-device `TrollStore` (`trollstorehelper install`). `trollstorehelper` automatically signs the main binary, embedded `.appex` plugins, and all addon `.dylib` files with CoreTrust bypass (`TeamIdentifier=T8ALTGMVXN`) while preserving native `no-container` and media entitlements.

### 4. Preserving Existing Kodi User Data (Migrating from a Jailbroken Install)

If you previously ran Kodi under a RootHide jailbreak, its user data (`userdata/`, `addons/`, `.smb/`) lives inside the jailbreak overlay at:

```text
/var/containers/Bundle/Application/.jbroot-<ID>/var/mobile/Library/Caches/Kodi
```

Because a native TrollStore-installed Kodi with `no-container=true` reads and writes the real system path across **both** jailbroken and unjailbroken boots:

1. Back up the existing `Kodi` folder first.
2. Copy it cleanly to `/private/var/mobile/Library/Caches/Kodi` (reachable via `/rootfs/private/var/mobile/Library/Caches/Kodi` from RootHide SSH) and set ownership to `mobile:mobile`.
3. Launch Kodi to verify your libraries, addons, and SMB sources load intact.

---

## Workflow B: YouTube tvOS with Upstream TizenTube / SponsorBlock (BYOIPA)

For YouTube on Apple TV (which runs Google's **Cobalt + Starboard + V8** HTML5 engine rather than `WKWebView`), [`scripts/build-youtube-tvos.sh`](../scripts/build-youtube-tvos.sh) combines:
- Your own locally obtained, decrypted tvOS `.ipa` (**BYOIPA**);
- Our clean-room binary userscript-loader patcher [`comicchang/tvos-cobalt-userscript`](https://github.com/comicchang/tvos-cobalt-userscript) (MIT);
- Upstream open-source userscript **[`reisxd/TizenTube`](https://github.com/reisxd/TizenTube)** (GPL-3.0, npm package `@foxreis/tizentube`; companion project [`reisxd/TizenTubeCobalt`](https://github.com/reisxd/TizenTubeCobalt), BSD-3-Clause), which provides ad-blocking plus **[`ajayyy/SponsorBlock`](https://github.com/ajayyy/SponsorBlock)** (GPL-3.0 / CC BY-NC-SA 4.0 API) and **[`ajayyy/DeArrow`](https://github.com/ajayyy/DeArrow)** (GPL-3.0) support, loaded at runtime directly from jsDelivr (works in **unjailbroken cold-reboot mode** with no local daemon required; override `--userscript-url` if you self-host on your LAN). None of these upstream scripts are vendored in this repository.

### Step 1: Download your own official IPA

Use [`majd/ipatool`](https://github.com/majd/ipatool) (MIT) with your own Apple Account:

```sh
brew install ipatool
ipatool auth login
ipatool download --bundle-identifier com.google.ios.youtube --platform appletv --purchase -o YouTube-official.ipa
```

### Step 2: Prepare an unencrypted local IPA (`cryptid == 0`)

On-device `TrollStore` requires an unencrypted Mach-O binary so `trollstorehelper` can sign it. This repository contains **no** decryption code; if you need to decrypt your own legally obtained IPA on hardware you own, refer independently to the third-party open-source project [`EthanArbuckle/fairplay-decrypt`](https://github.com/EthanArbuckle/fairplay-decrypt) (GPL-3.0).

### Step 3: Build locally with `scripts/build-youtube-tvos.sh`

```sh
# Dry-run preview first
./scripts/build-youtube-tvos.sh --dry-run /path/to/YouTube-decrypted.ipa

# Build side-by-side YouTube TV IPA (icon inversion ON by default)
./scripts/build-youtube-tvos.sh \
  -o YouTubeTV-trollstore.ipa \
  /path/to/YouTube-decrypted.ipa

# Optional: keep original YouTube icon instead of inverted icon
./scripts/build-youtube-tvos.sh \
  --no-invert-icon \
  -o YouTubeTV-trollstore.ipa \
  /path/to/YouTube-decrypted.ipa
```

What this script does:
1. Runs `cobalt-patcher` (verifies `cryptid == 0`, injects ARM64 userscript-loader & CSP hooks pointing to upstream TizenTube Cobalt, preserves 4K/VP9 HDR gates, sets side-by-side `com.google.ios.youtube.tvos`).
2. Runs [`scripts/repack-ipa.sh`](../scripts/repack-ipa.sh) with `--entitlements sandbox --allow-alt-video-decoder` (plus default icon inversion unless `--no-invert-icon` is passed) and leaves final CoreTrust signing to on-device `TrollStore TV`.

### Step 4: Install via TrollStore TV

```sh
# Example via TrollStore TV root helper (on RootHide SSH, copy into /rootfs/private/var/tmp first)
sudo /rootfs/private/var/containers/Bundle/Application/<TROLLSTORE-UUID>/TrollStore.app/trollstorehelper \
  install /private/var/tmp/YouTubeTV-trollstore.ipa
```

---

## Workflow C: Generic Local tvOS IPA Customization (`scripts/repack-ipa.sh`)

For any other locally decrypted tvOS `.ipa` or `.app`:

```sh
# Repackage with inverted icon (default ON on macOS) and clean standard sandbox entitlements
./scripts/repack-ipa.sh \
  --bundle-id com.example.myapp.custom \
  --display-name "My App Custom" \
  --entitlements sandbox \
  -o MyApp-custom.ipa \
  /path/to/MyApp-unencrypted.ipa

# Or keep the original icon with --no-invert-icon
./scripts/repack-ipa.sh \
  --no-invert-icon \
  --bundle-id com.example.myapp.custom \
  --display-name "My App Custom" \
  --entitlements sandbox \
  -o MyApp-custom.ipa \
  /path/to/MyApp-unencrypted.ipa
```

> **Important**:
> - Keep `--entitlements sandbox` for regular apps (do **not** force `platform-application` + `no-sandbox` unless the app explicitly declares required `com.apple.security.exception.iokit-user-client-class` entries, otherwise tvOS 17 may return `Failed to create surface`).
> - Do **not** pre-run `scripts/sign-coretrust.sh` on an IPA you plan to pass to on-device `trollstorehelper`; Apple's on-device Security framework rejects re-signing already CoreTrust-bypassed Mach-Os (`errSecCSInternalError / -67048`).
