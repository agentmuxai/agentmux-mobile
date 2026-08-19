# Discovery diagnostics — telemetry for zero-result scans

**Implemented 2026-08-19.** Verified live on `AgentMux_Pixel9`: the summary header, network
snapshot, hint banner, and both scan-completion summaries all render correctly with real data
(confirmed via `uiautomator dump`, not just unit tests) — see the PR for the exact captured
`content-desc` output.

## Problem

Trigger (this session, 2026-08-19): running the app on the `AgentMux_Pixel9` emulator, the
Discovery screen found nothing — despite the host PC running an AgentMux instance with LAN
discovery (mDNS) actively enabled and advertising.

**Root cause, confirmed by inspecting the emulator's actual network config**
(`adb shell ip addr show`): both of its interfaces sit on `10.0.2.0/24` —

```
eth0:  inet 10.0.2.15/24
wlan0: inet 10.0.2.16/24
```

— the classic QEMU/SLIRP virtual NAT range every Android emulator uses by default. This is an
isolated virtual subnet: it cannot receive multicast (mDNS) from the host's real LAN interface,
and a UDP broadcast sent from inside it (`255.255.255.255`, per `udp_broadcast_prober.dart`)
never leaves `10.0.2.0/24` either — it can't reach the host's actual LAN broadcast domain. This
matches (and extends) the already-documented finding in
[issue #2](https://github.com/agentmuxai/agentmux-mobile/issues/2)'s reliability table
("Android Emulator | All emulators | High — always fails" for mDNS) — the same root cause applies
to the Layer 2 UDP-broadcast fallback too, which had never been explicitly exercised against the
emulator before this session.

**The real problem this spec addresses is not that discovery failed here — it's that the app
gave zero signal about why.** Confirmed by reading the actual scanner code:

- `MdnsScanner.scan()` and `UdpBroadcastProber.probe()` each call `AppLogger.log()` **only** on a
  thrown exception. A clean scan that completes with zero results — the overwhelmingly common
  real-world failure mode (NAT, multicast-filtered corporate/guest WiFi, wrong subnet, no network
  at all) — produces **no log entry whatsoever**. This is exactly what happened this session.
- `DebugLogScreen`'s own empty-state copy — *"No log entries yet. Discovery/connection issues
  will show up here."* — is actively misleading in precisely this case: the issue **is**
  discovery finding nothing, and the screen implies that would show up, but today it doesn't.
- Per-record discard reasons are also silent: `MdnsScanner._resolveService()` returns `null`
  (dropping the whole record) for a missing SRV host/port, a missing `auth_key` TXT field, or no
  resolvable A/AAAA record — three distinct early-returns, none logged.
  `UdpBroadcastProber.parseResponse()` does the same for malformed JSON, wrong `type`/`v`, or
  missing fields. A partially-broken advertisement (e.g. a host publishing PTR but missing
  `auth_key`) looks identical today to "nothing out there at all."
- No network-environment snapshot is ever captured. Nobody reading the debug log can tell
  whether the device even has a usable interface, let alone what subnet it's actually on — that
  required manually running `adb shell ip addr` outside the app entirely to diagnose this session.

## What this spec is NOT

**Not a fix for discovery not working in the emulator.** That's a real, structural networking
limitation — the Android emulator's default SLIRP networking has no reliable Windows-side
bridged-networking alternative as of 2026 — already documented in README.md's sandbox section and
issue #2. Nothing here makes mDNS/UDP-broadcast reach the emulator's virtual NAT; that would need
a different emulator network mode (out of scope, separate investigation if ever pursued) or
testing on a real device.

This spec is entirely about making the **next** occurrence of "why isn't anything showing up" —
on a real device, an unfamiliar office network, a VPN, wherever — diagnosable from the in-app
debug log alone, without needing to attach a debugger or manually run OS networking commands.

## Design

### 1. Log the clean-zero-result case, not just exceptions

Both `MdnsScanner.scan()` and `UdpBroadcastProber.probe()` gain a single summary
`AppLogger.log()` call at the natural end of the stream (timeout or clean completion), **in
addition to** the existing exception-path logging — not replacing it:

- mDNS: `"mDNS scan complete: N PTR record(s) seen, M resolved in <duration>"` (N=0 is exactly
  as loggable as N=3 — the point is a log line exists either way).
- UDP: `"UDP broadcast probe complete: probe sent, N response(s) received (M valid) in
  <duration>"`.

This alone closes the primary gap: a scan that legitimately found nothing now leaves a trace.

### 2. Aggregate discard reasons — don't log per-packet

`_resolveService()`/`parseResponse()`'s individual discard branches should feed **counts** into
the same summary line above, not one `AppLogger.log()` call per discarded record. Two reasons:

- The UDP broadcast port (47891) is a shared, unauthenticated channel — unrelated broadcast
  traffic from other devices/apps on the same network can legitimately hit it. Logging every
  single malformed datagram individually risks flooding the 200-entry ring buffer with noise
  from other people's traffic, not signal about this app.
- A count is more useful anyway: `"mDNS: 2 PTR seen, 0 resolved (2 missing auth_key)"` says more
  than two separate free-text lines would.

Concretely: `MdnsScanner._resolveService()` returns a discard reason alongside `null` (e.g. via a
small result type, not just `LanInstance?`), and `scan()` tallies them into the end-of-scan
summary. Same shape for `UdpBroadcastProber.parseResponse()`'s discard branches.

### 3. Network-environment snapshot, captured once per discovery session

`DiscoveryNotifier.build()` captures a snapshot via `NetworkInterface.list()` (already a
dependency-free `dart:io` call, no new package) at the start of each scan session and logs it
once: `"Network snapshot: wlan0=10.0.2.16/24, eth0=10.0.2.15/24"`. This is the single piece of
information that would have made this session's investigation immediate instead of requiring a
manual `adb shell` detour.

### 4. Lightweight "does this look like a NAT sandbox" hint

Classify the snapshot against a short, explicit list of known-unfriendly patterns and, if
matched, log (and surface as a small non-blocking banner on the Discovery screen, not just
buried in the log) a plain-language explanation:

- `10.0.2.0/24` — QEMU/SLIRP (Android emulator default networking).
- `100.64.0.0/10` — CGNAT.
- `169.254.0.0/16` only, no other non-loopback interface — link-local/no real network.
- No non-loopback interface at all — no network connectivity.

Suggested copy: *"Network environment looks isolated (10.0.2.x) — this is expected on the Android
emulator's default networking, not a bug. LAN discovery can't reach a real network from here; use
manual IP entry with your desktop's real LAN address, or (development only)
`scripts/run-emulator.sh`."* This directly answers, in-app, the exact question this spec's
investigation started from — for the next person, without needing to re-derive it.

### 5. `DebugLogScreen`: fix the misleading empty state, add a summary header

- Empty-state copy changes from *"No log entries yet. Discovery/connection issues will show up
  here"* to something that doesn't imply a clean-zero scan is indistinguishable from never having
  scanned at all (it no longer will be, per §1, but the copy should stop overclaiming regardless).
- A small pinned header above the log list showing the most recent network snapshot + last scan
  outcome per layer, so the big picture doesn't require scrolling/reading free-text log lines to
  reconstruct.

## Scope (in)

- Summary logging (§1) for both scanners' clean-completion path.
- Aggregated (not per-packet) discard-reason counts (§2).
- One-time network-environment snapshot per discovery session (§3), using `NetworkInterface.list()`
  — no new package dependency.
- Known-unfriendly-network heuristic + in-app hint (§4) — plain-language, not a diagnosis engine;
  a short, explicit, reviewable pattern list.
- `DebugLogScreen` empty-state copy + summary header (§5).

## Scope (out) — and why

- **No attempt to make discovery actually work in the emulator.** Structural networking
  limitation, not a telemetry gap — see "What this spec is NOT" above.
- **No remote/server-side telemetry shipping.** Same call `DEBUG_LOGGING_SCOPE.md` already made
  for the logging system this builds on — "out of scope until there's an actual need to see logs
  the app never had a screen open for." Not revisiting that here.
- **No full structured-logging framework, no severity levels, no per-tag filtering.** Reuses
  `AppLogger` as-is; adds one new lightweight concept (per-scan summary counts), not a new
  logging system.
- **No disk persistence beyond the existing 200-entry in-memory ring buffer.** Same reasoning as
  `DEBUG_LOGGING_SCOPE.md` — "why did the thing I just did fail" is the use case, not long-term
  analytics.
