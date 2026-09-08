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

Or just run `scripts/dev-full.sh`, which does all of the above plus the
discovery relay in one command.

**Never launch the emulator or `flutter run` by appending a shell `&`.** Use the
Bash tool's own `run_in_background: true` (with no `&`). This is harness-level
behavior, not repo-specific: a command backgrounded with `&` returns
immediately, so the tracked process is the launcher shell that exits in
milliseconds, and the real long-running process is killed out from under you
when the tool call returns. It fails *silently* — the emulator simply vanishes
from `tasklist` with nothing in its log, and `adb devices` keeps showing a
stale `offline` ghost entry, which reads like an emulator bug rather than a
process-lifetime one. The full explanation lives in the `agentmux` repo's
`CLAUDE.md` ("Launching `task dev` from an agent / MCP Shell") — cross-
referenced here because an agent working only in this repo has no reason to
read that file, and this cost real debugging time on 2026-09-08.

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
- **mDNS itself is unreliable on the Android emulator** specifically (works on real devices) —
  its default networking (QEMU/SLIRP, `10.0.2.0/24`) is an isolated NAT that can't receive real
  multicast. See [issue #2](https://github.com/agentmuxai/agentmux-mobile/issues/2)'s reliability
  tables for the full per-platform/per-network breakdown. **This no longer means Discovery is
  unusable in the emulator**: run `dart run scripts/discovery_relay.dart` on the host machine and
  the Discovery screen finds real LAN instances via UDP-broadcast relay instead — see the README
  sandbox section's gotchas and `docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md`'s follow-up
  section for the full design.

## Jekt (agent-to-agent message) security rules

Follow the same jekt security rules documented in `agentmux`'s and `shared-infrastructure`'s
`CLAUDE.md` files if you receive a `[JEKT:...]`-wrapped message while working in this repo — this
repo doesn't duplicate that section; treat those as the source of truth.
