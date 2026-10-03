# Spec: Live fleet topology (host -> channel -> agent) that keeps up with change

**Status:** adopted 2026-10-03 (owner: "adopt all the best recommendations, write spec to file and
implement"). Implemented, not yet merged: mobile in #34 (this repo), desktop in agentmuxai/agentmux#4297
(`docs/specs/SPEC_LAN_FLEET_FEED_2026_10_03.md` there). The
desktop routes were checked live against this app's own transport (section 8).
**Date:** 2026-10-03
**Author:** Clamk
**Scope:** `agentmux-mobile` (client, UI) and `agentmux` / `agentmux-srv` (a narrow, names-only read
surface for LAN peers)
**Aligns with:** `agentmux` `docs/specs/SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md`, the
desktop Swarm's view of the same host -> channel -> agent tree. Naming rule, freshness thresholds
and the names-only privacy line are taken from there, so the phone and the desktop agree.

Legend: **[verified]** = read in code or observed live on 2026-10-03. **[general practice]** = how
well-known systems such as Discord's gateway behave, from their public documentation, not from this
repo. **[decision]** = adopted for this work.

---

## 1. Why this exists

The fleet is not static. One machine (Narko) runs three AgentMux channels at once; channels start
and stop, agents come and go, hosts sleep, the phone changes networks. The app took one snapshot at
start-up and another on manual refresh, so everything on screen was right only for that moment.

### 1.1 Findings

All **[verified]** on 2026-10-03.

| # | Finding | Evidence |
|---|---------|----------|
| F1 | Charlie and Starpower showed no agents. | They hold only the broadcast `lan_key`; the desktop refuses it on `/agentmux/discovery` (404) and accepts it on `/agentmux/reactive/agent-names`, which the app never called. |
| F2 | Two channels on one host collapsed into one card. | `isSameInstance` merged on hostname alone. |
| F3 | Narko, as an external host, did not appear until LAN discovery was enabled on it. | With it off, its srv processes listen on `127.0.0.1` only. The owner then enabled LAN on two of its three channels (ports 29700 and 29704; the dev channel 29706 stays loopback-only). |
| F4 | Only one channel per host answers the UDP probe. | After enabling, only the 29704 process holds UDP 47891; a probe returns Narko once (29704), never 29700. The desktop deliberately avoids `SO_REUSEADDR` (on Windows it lets another process steal the socket). If the holder's bind fails, the other instance logs and never retries. |
| F5 | mDNS does see every LAN-enabled channel. | A browse returns `agentmux-narko-29700` and `agentmux-narko-29704` separately, each with its own port, and 0.59.7 adds a `channel` TXT field (desktop #4241). mDNS does not work on the Android emulator (issue #2), so the emulator sees only F4's single UDP answer. |
| F6 | A `lan_key` holder reads agent names only, per instance. | `handle_reactive_agent_names`, names-only by owner decision 2026-09-08. `host.cross_channel` and `host.agents` need the full key. |
| F7 | The earlier four-channel Narko tree was an artefact of the dev connection. | It came from the dev auto-connect's full key over loopback, which a phone never has. |
| F8 | The app has no notion of change over time. | `DiscoveryNotifier.build()` ran mDNS 5 s, UDP 2 s, then stopped. |
| F9 | mDNS "service removed" is not a reliable signal. | The desktop documents it firing on ordinary TTL churn; it expires peers by their advertised TTL instead (`peer_staleness_window_secs`, 300 s floor). |
| F10 | The desktop's push channel (`/ws`) is full-key only. | `auth_middleware` accepts only `state.auth_key` (or a container grant). Unusable with a `lan_key`. |

### 1.2 What "good" looks like

The owner's bar: "Discord is really good at it". In user-visible terms:

1. A new channel or agent appears within seconds, without pull-to-refresh.
2. Something that goes away dims first and disappears later; nothing flickers.
3. Sleep, network changes and desktop restarts heal by themselves.
4. The screen never says "no agents" when the truth is "could not ask".
5. A burst of changes (a host booting three channels) is one smooth update.
6. Expanded/collapsed state and scroll position survive every update.

---

## 2. Principles

**P1. Snapshot first, then changes. [general practice]** Discord's gateway sends the full state once
(`READY`) and then events. A client that can always rebuild from a snapshot cannot drift for long.

**P2. Events carry the whole (small) state. [decision]** An agent-name list is tens of entries, so
every push event is a complete snapshot of one channel, tagged `epoch:rev`. Applying one twice or
late is harmless (the client keeps the highest `rev` per `epoch`), and there is no gap to detect and
no replay buffer to get wrong. Deltas are the right tool at Discord's scale, not at ours.

**P3. Resume cheaply, resync honestly. [general practice]** Discord's `RESUME` versus
`INVALID_SESSION`. Here the client reconnects with `Last-Event-ID: epoch:rev`. If nothing changed,
the host sends only heartbeats; otherwise, or if the srv restarted (new `epoch`), it sends the
current snapshot.

**P4. Detect dead connections actively. [general practice]** A TCP stream can look open for minutes
after a laptop lid closes. The host sends a heartbeat every 15 s; two missed (30 s of silence) means
reconnect.

**P5. Back off with full jitter. [general practice]** Delay = random(0, min(60 s, 1 s x 2^attempt)),
reset after 30 s connected. Phones must not reconnect in lockstep after a desktop restart.

**P6. Presence has states. [general practice]** Online, stale, gone; never "deleted because one
packet was late".

**P7. Expire by lease. [verified for desktop]** Any successful contact (mDNS record, UDP reply,
heartbeat, HTTP 200) renews an endpoint's lease. Silence, not a removal event, ends it (F9).

**P8. Separate discovery, sessions, store and view. [decision]** Discovery finds endpoints;
sessions keep them current; a store holds the merged truth; the tree is a pure function of it.

**P9. Pure, idempotent reducer. [decision]** `apply(state, event) -> state`, tested without a
network or a real clock.

**P10. Stream only what is on screen. [general practice]** Discord loads large guilds lazily. Here:
stream while the app is in the foreground, stop everything in the background, resync on return.

**P11. Stable identity, never positional. [decision]** Keys, sort order and UI state follow
identity, so an insertion never moves what the user is looking at.

**P12. Say what you do not know. [decision]** "No agents reported" means the host said so. A
refusal, timeout or error is shown as such.

---

## 3. Identity

| Level | Key | Notes |
|-------|-----|-------|
| Host | `hostname`, lower-cased | Same key the desktop Swarm uses (`host:<hostname>`). Display only; not proof of anything (section 7). Falls back to the address when a server reports none. |
| Channel | `(host, channel)` | `channel` is advertised by every 0.59.7+ srv (TXT, UDP reply, `/agentmux/fleet`). For an older srv that does not send it, the port is the key and `:<port>` the label. |
| Run | `epoch` | Random per srv launch, only inside the fleet feed. A new epoch means "this channel restarted"; the client takes its snapshot as-is. |
| Agent | `(host, channel, name)` | Names compare case-insensitively (the desktop lower-cases registration keys). |

`address:port` is a locator, not an identity: one channel can be reached at several addresses
(loopback and LAN), and DHCP can move a host.

---

## 4. Wire contract (desktop, `agentmux-srv`)

Everything here is reachable with the broadcast `lan_key` through `lan_or_full_auth_middleware`.
Nothing exposes more than agent **names** plus instance metadata (hostname, channel, version,
port), all of which a LAN peer can already see in the mDNS record.

### 4.1 `GET /agentmux/fleet`

```json
{
  "epoch": "9f2c41d07a6b3e58",
  "rev": 12,
  "hostname": "narko",
  "channel": "local-main-b28b7a-051fbf53",
  "version": "0.59.7",
  "agents": ["AgentY", "Clamk"]
}
```

- `agents`: this instance's reachable agents (`reactive_handler.list_agents()`), names only, sorted
  case-insensitively, de-duplicated.
- `epoch`: 16 lowercase hex chars, random per srv launch. `rev`: starts at 1, +1 on every change of
  the name set.
- `ETag: "<epoch>:<rev>"`. A request with a matching `If-None-Match` gets `304 Not Modified`, no
  body. `Cache-Control: no-cache`.

### 4.2 `GET /agentmux/fleet/events` (Server-Sent Events)

- `Content-Type: text/event-stream`, `Cache-Control: no-cache`.
- First line `retry: 3000`.
- On connect: if `Last-Event-ID` equals the current `<epoch>:<rev>`, send nothing yet; otherwise send
  `event: fleet`, `id: <epoch>:<rev>`, `data: <the 4.1 JSON on one line>`.
- On every change: one more `fleet` event, same shape.
- Every 15 s: a comment line `: hb`.
- Change detection: a single task compares the name set once a second and publishes through a
  `tokio::sync::watch`, so every stream sees the latest state and none can fall behind.
- At most 32 concurrent streams per srv; beyond that `503` (a LAN peer must not be able to exhaust
  the srv).

Why SSE rather than WebSocket: the flow is one-way, it carries the auth header, resume is built
into the protocol, it needs no ping/pong framing on the phone, and it stays separate from the
full-key `/ws` bus (F10).

### 4.3 UDP reply: `siblings` (fixes F4)

The one srv that holds UDP 47891 also lists the other channels on the same machine that have LAN
discovery on:

```json
{ "type": "agentmux_discover_response", "v": 1, "hostname": "narko", "port": 29704,
  "auth_key": "<this channel's lan_key>", "channel": "local-main-...", "...": "...",
  "siblings": [ { "channel": "stable", "port": 29700, "auth_key": "<that channel's lan_key>", "version": "0.59.4" } ] }
```

- Source: a host-global file per LAN-enabled instance, `<shared>/lan/instances/<channel>.json`
  `{channel, port, lan_key, version, pid, updated_at_ms}`. Written when LAN discovery starts,
  rewritten every 20 s while it runs, removed when it stops and on clean shutdown. Readers skip an
  entry older than 60 s, whose pid is dead, or that is this instance itself.
- **As built:** `siblings` is in the 47891 reply (the one phones read) only, not in the
  desktop-to-desktop reply on the peer port, whose readers use a 1024-byte buffer. The 47891 reply
  is kept under 1400 bytes so it stays one datagram, which in practice fits 5 to 10 siblings
  depending on channel-name length; `siblings` is always present, empty when there are none.
- Only LAN-enabled siblings are ever listed: each one already broadcasts its own `lan_key` to the
  LAN over mDNS, so relaying it exposes nothing new. A channel with LAN off (Narko's dev channel)
  never writes a file and is never listed. The full `auth_key` is never written or sent.
- **Responder failover:** an instance whose UDP bind fails retries every 15 s while LAN discovery
  stays on, so when the holder stops, another LAN-enabled channel takes over.

### 4.4 `/agentmux/discovery` (full key)

`host.channel` is added (this instance's own channel), so a QR or manually paired phone can name it.

### 4.5 Compatibility

All additions are new fields or new routes. Older phones ignore them. A new phone against an older
desktop falls back route by route: no SSE -> poll `/agentmux/fleet` -> poll
`/agentmux/reactive/agent-names` (or `/agentmux/discovery` with a full key). No `siblings` -> it
still finds every channel mDNS can see.

---

## 5. Client architecture (`agentmux-mobile`)

```
 Discovery (continuous)        Sessions (one per channel)         FleetStore           View
 mDNS re-browse  --+
 UDP probe       --+--> Endpoint(locator, key, hints) --> SSE | poll fleet | poll names --> reducer --> buildHostTrees --> UI
 UDP siblings    --+                                      (heartbeat, backoff, lease)     (pure)      (pure)
 QR / manual / dev-+
```

### 5.1 Discovery

- **While in the foreground**, discovery runs as a loop, not once: a UDP probe and a 4 s mDNS browse
  every 5 s for the first minute, then every 30 s. Pull-to-refresh runs one round immediately.
- A UDP reply's `siblings` each become an endpoint at the replying host's address.
- Every sighting renews the endpoint's lease.
- **Background:** discovery and all sessions stop. **Foreground:** discovery runs at once and every
  session resyncs (with jitter). For 15 s after returning, a channel past the 300 s limit is shown
  dimmed rather than hidden, so channels that went quiet only because the app slept do not vanish
  and reappear.
- **Network change**, checked each round: only a change in the private IPv4 /24 subnets of
  non-cellular interfaces counts (`lanNetworkSignature`). IPv6 privacy addresses rotate and mobile
  data comes and goes without the Wi-Fi network changing, and an empty interface list means
  "unknown". On a real change every LAN session reconnects over the new network and discovery runs
  fast again; nothing is deleted, so hosts of the old network dim and age out like any other quiet
  channel and the screen never blanks.

### 5.2 Sessions

One per channel endpoint:

1. Try `GET /agentmux/fleet/events`. On 404/405 (old desktop), drop to polling.
2. Polling: `GET /agentmux/fleet` with `If-None-Match` (404 -> agent names via the existing
   fallback). Interval 3 s while the host changed in the last minute, else 10 s; +/-20% jitter.
3. On a network error: backoff (P5) and a `stale` mark; data kept.
4. On 401: state `unauthorized`, retried slowly (60 s); never shown as "no agents".

### 5.3 Store and presence

- Per channel: `agents`, `epoch`, `rev`, `lastContact`, `error`.
- **Presence** [aligned with the desktop Swarm, section 4 of its spec]: `live` while contact is under
  60 s old; `stale` (dimmed, "last seen 2 min ago") from 60 s; `gone` and hidden at 300 s. Manual, QR
  and dev endpoints are never hidden automatically.
- A `fleet` event or poll result for the same `epoch` with `rev` <= the stored one is ignored; a new
  `epoch` replaces the channel's state.
- UI updates are coalesced to at most one every 150 ms.

### 5.4 View

- host -> channel -> agent; the channel level appears only when the host has more than one channel,
  and then always with its name (owner's rule, same as the desktop Swarm).
- Hosts, channels and agents sorted by name, case-insensitively; keys are identities.
- Presence shown on the host and channel rows; an error is shown as a short line on the channel
  ("unreachable", "not authorised"), never as an empty agent list.

### 5.5 Dev workflow

`scripts/dev-full.sh` no longer passes the dev auto-connect key by default, so the emulator sees
this machine exactly as a phone would (F7). `--dev-connect` opts back in.

---

## 6. Timing defaults

| Setting | Value |
|---------|-------|
| SSE heartbeat (host) | 15 s |
| Declared dead after | 30 s without a byte |
| Backoff | full jitter, 1 s base, 60 s cap, reset after 30 s connected |
| Poll interval (fallback) | 3 s active, 10 s quiet, +/-20% jitter |
| Discovery rounds | every 5 s for 60 s, then every 30 s |
| Stale / hidden | 60 s / 300 s since last contact |
| UI coalescing | 150 ms |
| Concurrent SSE streams per srv | 32 |

---

## 7. Security and privacy

- **Names only to LAN peers**, as before (owner decision 2026-09-08; the desktop Swarm spec keeps
  the same line). The fleet feed adds `epoch`/`rev`/`channel`/`version`/`hostname`, none of them
  agent data.
- **Channel names are visible on the LAN.** A dev channel's name can contain a branch name. Only
  LAN-enabled channels are ever advertised or listed, and that was already true of the TXT record.
- **No full key ever leaves the machine** through any of this; siblings carry only `lan_key`s their
  owners already broadcast.
- **Untrusted input:** every field from a peer is bounded (name length, list length) and never used
  as a path or format string.
- **No secrets in logs** on either side: locators and states only.
- **Hostname is a label, not proof.** A LAN device could claim a hostname; the cost is a mislabelled
  card, not access.

---

## 8. Testing

- Mobile reducer and presence: duplicate and stale `rev`, new `epoch`, presence transitions under a
  fake clock, `unauthorized` is not empty, manual entries never hidden.
- Mobile SSE parser: multi-line data, comments, `id`, `retry`, partial chunks.
- Mobile tree: existing `buildHostTrees` tests plus sort stability.
- Desktop: `/agentmux/fleet` shape, ETag and 304, `lan_key` accepted and nothing beyond names; SSE
  first event, `Last-Event-ID` resume, heartbeat, stream cap; sibling file lifecycle, stale/dead/self
  filtering, never listing a LAN-off channel; UDP bind retry.
- Live: Narko (two LAN channels, one LAN-off), Charlie, Starpower, from the emulator through the
  relay. Start and stop a channel and watch the tree follow without a refresh.
- **Done 2026-10-03, cross-implementation:** the desktop branch's srv, run isolated on loopback,
  driven by this app's `HttpFleetTransport`: poll 200 then 304 on the ETag; stream accepted, snapshot
  within 5 ms, heartbeat at 15.0 s; resume with the current id sends no snapshot; a wrong key is a
  401, not "unsupported"; registering an agent pushed `rev 2` with its name to an open stream within
  about a second. On the emulator (released desktops, so the fallback path): Narko appears as an
  external LAN host beside Charlie and Starpower, agents from `agent-names`. Not yet seen live:
  `siblings` (needs two LAN-enabled channels on one host running the new desktop build).

---

## 9. Not in this work

- Cloud (muxbus) installs feeding the same store: needs the per-account presence directory in
  `agentmux-cloud` (the desktop Swarm spec's Phase 3). The store and view are built to take another
  source.
- Agent status (running/idle) or any content: owner decision pending in the desktop Swarm spec.
