# Contributing to TSLTV Non-Lite

Contributions, verification reports, and documentation improvements are welcome.

## Local Checks

Before opening a pull request, run the full local validation suite:

```sh
./tests/run.sh
```

This checks:
- POSIX `sh -n` syntax on all scripts under `scripts/` and `tests/`
- `shellcheck -S warning` lint cleanliness
- `Info.plist` / entitlements XML validation
- CLI `--help` and `--dry-run` smoke behavior
- Privacy / local-path / private-IP leak scanning
- Tracked binary guard (no compiled binaries, `.ipa`/`.tipa`, or third-party `Assets.car`)
- Relative Markdown link integrity across all documentation
- Clean-room tvOS probe compilation (automatically executed on macOS hosts with Xcode tvOS SDK)

## Repository Standards

1. **No vendored binaries or third-party assets**: Keep external tools (such as `fastPathSign`) out of git history; provide reproducible fetch/build scripts under `scripts/` and attribute upstream projects in [`NOTICE`](NOTICE).
2. **No hardcoded personal infrastructure**: Never commit private LAN IPs (use RFC 5737 documentation addresses like `192.0.2.10`), local home paths, passwords, certificates, device UDIDs, or personal jailbreak root hashes.
3. **Read-only by default & explicit destructive actions**: Device inspection scripts must default to read-only, never reboot devices automatically, and support `--dry-run`.
4. **Honest verification boundaries**: Clearly separate observed lab evidence from unverified assumptions (for example, Stage 1 jailbroken verification vs. Stage 2 cold-reboot verification).
