# Debug logging — scope

## Problem

Discovery-layer errors were previously swallowed by bare `catch (_) {}`
blocks (fixed in #11, #12 by switching to `dart:developer.log`). That gets
error visibility into an attached `flutter run` console / DevTools session,
but two gaps remain:

1. Nothing persists across app restarts or survives once the debug session
   detaches — no way to ask a user "what happened" after the fact.
2. `dart:developer.log` isn't reachable from a running release build the way
   a developer can reach it, so a user hitting a discovery failure has no way
   to hand you anything concrete.

## Scope (in)

- `AppLogger`: a thin wrapper around `dart:developer.log` that also appends
  each entry to a fixed-size in-memory ring buffer (last 200 entries).
- Same call sites already emitting `developer.log` today (mdns_scanner,
  udp_broadcast_prober, local_api_client, discovery_provider) switch to
  `AppLogger.log` instead — same signal, now also retained.
- One debug log screen reachable from the Discovery screen's app bar (that
  screen is unauthenticated and always reachable — unlike Settings, which
  sits behind the MuxBus cloud-auth gate — and it's exactly where discovery
  failures surface), showing the ring buffer newest-first with a
  "copy to clipboard" action so a user can paste it into a bug report or
  hand it to support.

## Scope (out) — and why

- **No disk persistence.** A ring buffer that resets on restart is enough for
  "why did the thing I just did fail" — the dominant real use case (this
  session's own emulator/LAN investigation being the motivating example).
  Disk persistence adds a retention/rotation/privacy-review surface this app
  doesn't need yet.
- **No remote log shipping / crash reporting service.** Out of scope until
  there's an actual need to see logs the app never had a screen open for.
- **No structured/leveled logging framework, no per-tag filtering UI.** One
  flat list is sufficient at current log volume (discovery + auth are the
  only loggers today).
- **Not wired into non-discovery code paths yet.** Auth, billing, injection
  etc. keep their current error handling; extending `AppLogger` to them is a
  follow-up if it proves useful here, not a prerequisite.

## Shape

```
lib/core/logging/
  app_logger.dart       # AppLogger.log(...), AppLogger.entries (ring buffer)
lib/features/debug/
  debug_log_screen.dart # newest-first list + copy-to-clipboard
```

`AppLogger.log(message, {name, error, stackTrace})` mirrors
`dart:developer.log`'s signature so call sites are a one-line swap.
