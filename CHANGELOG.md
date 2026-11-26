# Changelog

All notable changes to **TrollStore TV Tools** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Generic tvOS app packaging utilities: `scripts/deb2ipa.sh` (open-source `.deb` → `.ipa`), `scripts/invert-tvos-icon.sh` (pixel-exact tvOS `Assets.car` inverter), `scripts/repack-ipa.sh` (BYOIPA repackager with default-ON icon inversion & `--no-invert-icon` toggle), and `scripts/build-youtube-tvos.sh` (BYOIPA YouTube tvOS + upstream TizenTube Cobalt builder), plus end-to-end packaging guide (`docs/APP-PACKAGING-GUIDE.md`) and automated tests.
- Host-side batch CoreTrust bypass signer (`scripts/sign-coretrust.sh`) with automatic Mach-O discovery, `CDHash`/`TeamIdentifier=T8ALTGMVXN` verification, and `-o <out.ipa>` repackaging.
- Reproducible host `fastPathSign` build script (`scripts/fetch-fastpathsign.sh`) pinned to `f1ebe52` without vendoring compiled binaries.
- Read-only-by-default post-reboot verifier (`scripts/stage2-verify.sh`) and clean-room tvOS probe (`src/probe/`, `scripts/build-probe.sh`, `scripts/install-probe.sh`).
- Cold-reboot survival verification report and troubleshooting notes (`docs/REBOOT-VERIFICATION.md`).
- Local & GitHub Actions verification suite (`tests/run.sh`, `.github/workflows/ci.yml`), bilingual README (EN / zh-CN), `NOTICE`, `CONTRIBUTING.md`, and `SECURITY.md`.

### Fixed
- Fixed empty optional-argument shift in `scripts/stage2-verify.sh` (`__NONE__` sentinel).
- Fixed parent directory creation for `scripts/sign-coretrust.sh -o <nested>/out.ipa`.
- Added cross-platform Python `plistlib` fallback in `tests/run.sh` for Linux CI runners.
