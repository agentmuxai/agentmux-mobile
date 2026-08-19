# AgentMux Mobile — Agent Instructions

## Local dev sandbox — read this first

This app must be verified on a real OS target, not a browser tab. **Do not use
`flutter run -d chrome`/`-d edge` as a substitute for actually running the app** —
`flutter run -d web-javascript` targets are for the desktop app
([agentmux](https://github.com/agentmuxai/agentmux)), not this one.

A ready-to-use Android emulator (AVD `AgentMux_Pixel9` — Pixel 9, Android 15 / API 35) already
exists on this machine, fully configured (SDK, licenses, Java). Full setup + launch commands,
verified working end-to-end 2026-08-18: **README.md's "Local Android sandbox (Windows dev
machine)" section, right before "Quick start".** Read that section before attempting to build or
run this app — it also documents a real (now-fixed) `AndroidManifest.xml` XML-comment bug that
silently broke 100% of Android builds, in case a similar pattern gets reintroduced.

Quick reference (see README for the full commands + why each step exists):
1. Flutter isn't pre-installed — install the exact version pinned in `.fvmrc`, not "latest".
2. Launch the emulator, wait for `sys.boot_completed=1` (not just adb-visible).
3. `flutter pub get` → `dart run build_runner build --delete-conflicting-outputs` → `flutter run -d emulator-5554 --dart-define=...`.

## Architecture

Flutter mobile companion for the AgentMux desktop fleet. Connects via
[agentmux-cloud](https://github.com/agentmuxai/agentmux-cloud) (muxbus) off-LAN, or directly to a
desktop backend over LAN (mDNS / UDP-broadcast fallback / QR-code pairing — see
`lib/core/discovery/`). Read-first: agent configuration, workspace, and tool execution stay on
the desktop app.

## Known coverage gaps

- **Dependency security scanning doesn't cover this repo.** The org-wide weekly Security
  Researcher (`a5af/shared-infrastructure`) only supports `npm audit`/`pip-audit`; this is a
  Dart/Flutter app (`pubspec.yaml`), which isn't a supported ecosystem yet. See
  `docs/specs/SECURITY_SCANNING_COVERAGE_GAP.md`.
- **mDNS discovery is unreliable on the Android emulator** specifically (works on real devices).
  See the README sandbox section's gotchas, and `docs/mdns-discovery-spec.md` / issue #2's
  reliability tables for the full per-platform/per-network breakdown.

## Jekt (agent-to-agent message) security rules

Follow the same jekt security rules documented in `agentmux`'s and `shared-infrastructure`'s
`CLAUDE.md` files if you receive a `[JEKT:...]`-wrapped message while working in this repo — this
repo doesn't duplicate that section; treat those as the source of truth.
