# Roadmap

## Done

- [x] Open-source `.deb` → `.ipa` converter (`scripts/deb2ipa.sh`) with `.jbroot` stripping & `--store`
- [x] Pixel-exact RGBA8 tvOS layered `Assets.car` icon inverter (`scripts/invert-tvos-icon.sh`)
- [x] Generic BYOIPA repackager (`scripts/repack-ipa.sh`) & YouTube tvOS BYOIPA builder (`scripts/build-youtube-tvos.sh`) with default-ON icon inversion (`--no-invert-icon` toggle)
- [x] Host-side recursive CoreTrust batch signer (`scripts/sign-coretrust.sh`) with nested `.appex` per-bundle entitlements, symlink guard, and `cryptid` check
- [x] Clean-room tvOS diagnostic probe (`src/probe/`) and read-only post-reboot verification (`scripts/stage2-verify.sh`)
- [x] Bilingual documentation, full third-party attribution, and offline CI verification gate (`tests/run.sh`)

## Planned

- [ ] Optional `--preserve-entitlements` mode for `sign-coretrust.sh` to dump and normalize existing entitlements directly from input Mach-Os
- [ ] Additional open-source `.deb` packaging recipes and automated Linux/macOS matrix smoke tests
