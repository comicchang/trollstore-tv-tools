# Security Policy

## Scope

This repository contains clean-room research tooling and documentation for
exploring CoreTrust signing and application verification behavior on
user-owned Apple TV 4K hardware running tvOS 17.0.

- No private signing keys, certificates, credentials, or compiled exploit
  binaries are distributed in this repository.
- Device scripts are strictly read-only by default and never initiate automatic
  reboots or modify `/Applications`.

## Reporting Issues

If you discover a security concern, accidental credential/PII exposure, or
unsafe script behavior in this repository:

1. Do **not** open a public issue containing sensitive device identifiers,
   private keys, or credentials.
2. Report the issue privately to the repository maintainer via GitHub Security
   Advisories (when enabled) or direct private contact.
