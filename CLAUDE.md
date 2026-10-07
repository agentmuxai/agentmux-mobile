# AgentMux Mobile — Agent Instructions

## Git hooks — one-time setup

This repo strips `Co-Authored-By:` trailers from every commit (policy:
only the actual person/identity who opened the PR is attributed). The
hook lives at `.githooks/commit-msg` but isn't active until
`core.hooksPath` points at it — run once per clone:

```bash
git config core.hooksPath .githooks
```

(No `npm`/`prepare` script to piggyback this onto in a Flutter project —
every other repo in this org auto-activates the same hook via `npm install`;
this one needs the explicit one-liner.)

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

**`dev-full.sh` shows this machine the way a phone sees it** (LAN only, the
broadcast `lan_key`); pass `--dev-connect` to also bake in this machine's own
sidecar URL and full key. Don't verify LAN behaviour through `--dev-connect`:
the full key shows things no phone can see (other channels with LAN off).
See `docs/specs/SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md` §5.5.

**With `--dev-connect`, if the dev connection never appears, or shows "not
authorised" after a desktop restart, rebuild the app — don't debug the
network.** The desktop mints a **fresh
`auth_key` on every launch** (`agentmux-launcher`'s `srv_spawner.rs`:
"Generate a fresh auth_key per run"), but `AGENTMUX_DEV_KEY` is baked into the
app at *build* time by `run-emulator.sh`. So any AgentMux restart — including a
silent auto-update — invalidates the built-in key and the request 401s. The
in-app Debug log (🐛) carries the specific stale-dev-key message.

**From an agent inside AgentMux, start the emulator and `dev-full.sh` with
AgentMux's `Shell` tool, not the Bash tool.** Since Claude Code 2.1.285
(2026-09-29) a `run_in_background` Bash command is stopped after a time limit
(default 30 min) in unattended sessions, which includes agents AgentMux runs:
the emulator vanishes and the discovery relay stops with `dev-full.sh`. A
command started with `Shell` runs under AgentMux itself, has no such limit,
and is stopped with `ShellStop`. Give `Shell` a plain command line (no quoted
program path; use `C:\PROGRA~1\...` or a small wrapper script for paths with
spaces), e.g. `C:\Users\<user>\AppData\Local\Android\Sdk\emulator\emulator.exe
-avd AgentMux_Pixel9 -no-snapshot-load`, then a wrapper script that puts
Flutter and `platform-tools` on `PATH` and runs `bash scripts/dev-full.sh`.

**When launching the emulator or `flutter run` from a Bash *tool call* anyway,
never append a shell `&`** — use the Bash tool's own `run_in_background: true`
(with no `&`) instead, and expect the time limit above. This is harness-level
behavior, not repo-specific: a tool call returns as soon as the backgrounded
command is spawned, so the tracked process
is the launcher shell that exits in milliseconds, and the real long-running
process is killed out from under you. It fails *silently* — the emulator simply
vanishes from `tasklist` with nothing in its log, and `adb devices` keeps
showing a stale `offline` ghost entry, which reads like an emulator bug rather
than a process-lifetime one.

Note this is specifically about tool calls, **not** about `&` in general:
README.md's step 2 uses a trailing `&`, which is correct for a human in an
interactive shell (the parent shell stays alive) and wrong to copy verbatim
into a tool call. The README says so inline. The full explanation lives in the
`agentmux` repo's `CLAUDE.md` ("Launching `task dev` from an agent / MCP
Shell") — cross-referenced here because an agent working only in this repo has
no reason to read that file, and this cost real debugging time on 2026-09-08.

## Architecture

Flutter mobile companion for the AgentMux desktop fleet. Connects via
[agentmux-cloud](https://github.com/agentmuxai/agentmux-cloud) (muxbus) off-LAN, or directly to a
desktop backend over LAN (mDNS / UDP-broadcast fallback / QR-code pairing — see
`lib/core/discovery/`). Read-first: agent configuration, workspace, and tool execution stay on
the desktop app.

## Dependency vulnerability scanning

`.github/workflows/dependency-scan.yml` runs Google's OSV-Scanner on the resolved Pub
dependency tree: on PRs that touch `pubspec.yaml`/`pubspec.lock` (fails on any known
vulnerability), weekly, and on demand (those two also upload SARIF to Security > Code
scanning). It scans the committed `pubspec.lock`, the exact versions the app is built with.
After changing `pubspec.yaml`, run `flutter pub get` and commit the updated lockfile: CI runs
`flutter pub get --enforce-lockfile` and fails if they don't match. To check locally:
`osv-scanner scan source --lockfile=./pubspec.lock`.

## Known coverage gaps

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

## Changesets (required on every PR)

Every PR adds a changeset: `scripts/changeset.sh <patch|minor|major> "<one-line summary>"`, then commit the file it writes to `.changesets/`. The `changeset` CI check fails without one; a PR that genuinely needs no entry gets the `no-changeset` label. See `.changesets/README.md`.
