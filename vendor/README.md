# vendor/

This directory intentionally tracks **no compiled binaries** (see `.gitignore`).

## `fastPathSign` (Host-Side CoreTrust Bypass Signer)

`fastPathSign` signs Mach-O binaries in place on the macOS host using the CoreTrust bypass chain.

- Upstream source: <https://github.com/straight-tamago/TrollStore-tvOS> (MIT License, Copyright (c) 2024 straight-tamago)
- Pinned commit: `f1ebe52` (`"Update 2.1"`), `Exploits/fastPathSign`
- Reproducible local build (requires `clang` + OpenSSL `libcrypto`):

```sh
./scripts/fetch-fastpathsign.sh
```

- Output path: `vendor/fastPathSign` (gitignored, macOS host Mach-O)
- Override path: set `FASTPATH_SIGN=/path/to/fastPathSign` when invoking [`scripts/sign-coretrust.sh`](../scripts/sign-coretrust.sh)
