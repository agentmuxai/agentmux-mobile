# Retro: mobile dev loop, LAN discovery, and release pipeline — 2026-09-08

Friction log from one long session (Loap #2, claudius/Windows) covering:
getting the Flutter app running on the emulator, fixing LAN discovery,
making the repo public, and scaffolding the store-release workflows.

Logged for later smoothing — **not** a prioritized backlog. Each item notes
which repo actually owns the fix, since these span three.

---

## A. Product gaps found in AgentMux itself (`agentmux` / `agentmux-srv`)

These are real, reproducible, and the highest-value items here.

### A1. LAN peers never report their agents — blocks cross-host coordination
`GET /agentmux/discovery`'s `lan[]` entries and the `DiscoverAgents` MCP tool
both return `agents: []` for every LAN peer, even when the peer is fully
discovered with correct hostname/version (confirmed live for `starpower` and
`gamerlove`). Consequence: there is no way to find out *which* agents exist on
another machine. When asked to message an agent on another host, the only
option was to address it blind by name and hope delivery succeeded (it did —
`SendMessage` resolves by name across tiers — but discovery gave zero
confirmation the target existed).
**Owner:** `agentmux-srv` (`backend/lan_discovery.rs`). **Impact:** high — this
is the gap between "LAN discovery works" and "cross-host agent coordination
works."

### A2. `/agentmux/discovery`'s `host` object has no hostname
The `host` object exposes `version`, `local_url`, `addressable`, `agents`,
`cross_channel` — but no machine hostname. `local_url` is always loopback
(`http://127.0.0.1:<port>`), so a client literally cannot display what machine
it's talking to. The value already exists: `whoami::fallible::hostname()` is
computed at boot (`bootstrap.rs`) and passed to `LanDiscoveryController`, but
never lands on `AppState` or in this response.
**Owner:** `agentmux-srv` (`server/mod.rs` `handle_discovery`, `AppState`).
**Impact:** medium — small change (~15 lines), directly fixes the mobile app
showing a raw `10.0.2.2` instead of `claudius`.

### A3. Duplicate/partial LAN peer entries for the same host
`DiscoverAgents` returned two entries for `192.168.1.68` — one with
`hostname: "gamerlove"` (port 63324) and one with `hostname: ""` (port 60371).
The blank one is the known blank-TXT-first-resolution case, but the practical
result is a peer list with confusing duplicates of the same machine.
**Owner:** `agentmux-srv` (`lan_discovery.rs`). **Impact:** low-medium.

### A4. Dev auto-connect gets a 401 on rescan — ROOT-CAUSED, not a code bug
With `AGENTMUX_DEV_ADDR`/`AGENTMUX_DEV_KEY` set, the initial connect succeeds
and the agent list populates, but a later scan logged
`fetchAgents failed for http://10.0.2.2:59859 ... status code of 401`.

**Cause:** `agentmux-launcher`'s `srv_spawner.rs` mints a **fresh `auth_key`
per run** ("Generate a fresh auth_key per run", UUID v4), while
`AGENTMUX_DEV_KEY` is baked into the Flutter app at **build** time by
`run-emulator.sh`. Any AgentMux restart — including a silent auto-update —
invalidates the built-in key. Confirmed by the session's own evidence: the
desktop went 0.55.37 → 0.55.39 mid-session, i.e. it restarted underneath the
already-built app.

So there's nothing to "fix" in the auth path — it's inherent to baking a
per-run credential in at build time. What *was* wrong is that it failed
**silently**: `fetchAgents` swallows the error and returns `[]`, so the card
renders "No agents reported", which reads as "this instance has no agents"
rather than "your key is stale". Addressed by giving the 401 its own log
message naming the cause and the remedy (rebuild), plus a note in `CLAUDE.md`
where someone actually hits it. **Owner:** resolved (mobile diagnostics).

---

## B. Mobile app / dev loop (`agentmux-mobile`)

### B1. Two cards for the same machine — RESOLVED
The same physical host appeared twice on the Discovery screen — once as
`10.0.2.2` (dev auto-connect, loopback) and once as `claudius` (real UDP
broadcast, LAN address), because dedup was keyed on `address + port` and the
two paths legitimately report different ports.

Fixed without needing a new `instance_id` field: `agentmux` PR #3094 had
already added `host.hostname` to `/agentmux/discovery`'s response, but the
mobile client never consumed it — `fetchDiscoveryInfo()` didn't parse it, and
both `addManual`/`_maybeAutoConnect` hardcoded `hostname: address` (the raw
IP) instead. Wired the field through and changed every dedup site
(`isSameInstance`, `@visibleForTesting`) to treat matching non-empty
hostnames as the same instance, falling back to the original address:port
comparison when either side has none.

### B2. `dev-full.sh` has no readiness wait for the relay
`scripts/dev-full.sh` starts `discovery_relay.dart` and immediately launches
the app. Across runs, the relay sometimes logged **zero** probes received
while the app reported datagrams received — consistent with the app's first
scan firing before the relay's socket is bound. Needs a bind-readiness wait
(poll the port) rather than assuming the background start is instant. This made
live verification non-deterministic and cost real debugging time chasing a
race that looked like a logic bug.

### B3. Nothing had ever built for iOS
No CI job and (apparently) no local build has ever targeted iOS in this repo.
That's how the invalid `--` inside an XML comment in `ios/Runner/Info.plist`
survived (fixed this session, commit `30547bd`) — the exact same bug class
already documented for `AndroidManifest.xml`. Strongly suggests more latent
iOS-side breakage; delegated a real macOS build check to Clare@starpower.

### B4. No XML/plist well-formedness check in CI
Both known instances of this bug class (`AndroidManifest.xml` previously,
`Info.plist` now) would have been caught by a two-line CI step
(`plutil -lint` / any strict XML parse). Currently `ci.yml` only runs
`flutter analyze` + `flutter test`, neither of which parses these files
strictly. **Cheapest high-value fix in this document.**

### B5. Release builds were signed with the debug key
`android/app/build.gradle.kts` shipped with a literal
`// TODO: Add your own signing config` and `signingConfig = signingConfigs.getByName("debug")`
for the release build type — meaning `flutter build appbundle --release`
produced something Play would reject outright. Fixed this session, but it sat
undetected because nothing had tried to actually release.

---

## C. Environment / harness friction (claudius, Windows + Git Bash)

### C1. Backgrounding with `&` silently kills long-running processes
Launching the Android emulator with `... &` inside a Bash tool call let the
tool return immediately, then the emulator was killed (Windows job-object /
process-group teardown). No error, no log line — it just vanished from
`tasklist`, and `adb devices` kept showing a stale `offline` ghost entry.
Cost ~15 minutes of misdiagnosis. The fix (use the Bash tool's own
`run_in_background: true`, never a shell `&`) **is** already documented — but
in the `agentmux` repo's `CLAUDE.md`, under a `task dev` heading. An agent
working in `agentmux-mobile` has no reason to read it.
**Smoothing:** cross-reference that rule from `agentmux-mobile`'s `CLAUDE.md`,
since it's harness-level, not repo-level, knowledge.

### C2. Silent-command idle timeout kills legitimate waits
A poll loop beginning with `adb wait-for-device` was killed at 600s for
producing "no output for the idle timeout" — because `wait-for-device` blocks
with zero output by design, so nothing printed until it returned. Any long
silent wait needs to be restructured to emit progress. Non-obvious, and the
error message blames pagers, which sends you down the wrong path.

### C3. `grep -P` is unavailable
`grep -qP` fails with `grep: -P supports only unibyte and UTF-8 locales` in
this Git Bash environment. Bit me in `dev-full.sh` (caught in testing; fixed
to `grep -qE`). Worth knowing before writing any checked-in shell script here.

### C4. Path-style mismatch between bash tools and Python
`python3` can't open `/c/Users/...` paths (needs `C:\Users\...`), while every
bash tool uses the former. Produced a confusing `FileNotFoundError` mid-audit
that briefly looked like a missing file.

### C5. No Ruby on this machine
Couldn't even syntax-check the fastlane `Fastfile` (`ruby -c`), let alone run
it. Combined with no macOS/Xcode, the entire iOS release path is unverifiable
from this box — which is a legitimate reason to route iOS work to a macOS
agent, not a thing to fix locally.

### C6. Emulator cold boot is slow and opaque
2–3 minutes with no useful progress signal, plus a stale `offline` device
entry alongside the real one. The README already documents the ghost-entry
gotcha (that helped) — the slowness is inherent, but a documented "expect
~3 min, watch `sys.boot_completed`" note in `dev-full.sh` output would set
expectations.

---

## D. Process notes — my own missteps, logged as signal

Included because they say something about where this workflow is easy to get
wrong, not for their own sake.

- **D1.** I introduced the *same* `--`-inside-XML-comment bug in my own
  `Info.plist` comment on first write, immediately before discovering the
  pre-existing one. Two independent instances of one bug class in one session
  is a strong argument for **B4**.
- **D2.** First draft of the fastlane invocation in `release-ios.yml` mixed two
  different calling conventions (`fastlane run <action>` vs `fastlane <lane>`)
  and pointed at the wrong path for the decoded API key (`github.workspace`
  instead of `$HOME`). Both caught on re-read, both would have failed at
  runtime. Reinforces that the iOS path needs real execution, not review.
- **D3.** Used `ScheduleWakeup` to wait on a background task early on; it's for
  `/loop` dynamic pacing, not general waiting. Harmless, but wrong tool.

---

## Suggested order if picking this up

1. **B4** — plist/XML lint in CI. Two lines, catches a bug class that has now
   bitten twice.
2. **A2** — expose hostname in `/agentmux/discovery`. Small, self-contained,
   immediately visible in the mobile UI.
3. **A1** — populate LAN peer agent lists. Biggest functional unlock
   (cross-host agent discovery), also the biggest change.
4. **B2** — relay readiness wait in `dev-full.sh`. Removes nondeterminism from
   every future discovery debugging session.
5. **C1** — cross-reference the no-`&` harness rule into this repo's CLAUDE.md.
6. **A4** / **B1** / **A3** — smaller correctness/polish items.
