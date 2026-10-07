# Spec: Host platform, channel name, route (LAN / cloud) and HOST/SANDBOX tags, and why a cloud-only host is missing

**Status:** adopted and being built, 2026-10-06 (owner request: "why isn't Area54 showing? For each host we want to
know the platform. If multiple instances are open we also see the channel name; with one channel, no
channel name. We need to know how we're connected, LAN or cloud. Add the HOST/SANDBOX tag next to each
agent. Write a spec to file.")
**Author:** AgentY
**Scope:** `agentmux-mobile` (UI, store), `agentmux` / `agentmux-srv` (small additive fields on the LAN
feed), and the cloud tier (a per-account list of installs, which does not exist yet)
**Builds on:** `SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md` (this repo: the host -> channel -> agent tree,
the store, presence). In `agentmux`: `SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md` and
`SPEC_SWARM_REMOTE_AGENTS_PLATFORM_TAG_AND_SELECTION_2026_10_03.md`, which ask for the same tags on the
desktop Swarm. The phone should read the same as the Swarm, so labels, the naming rule and the wire
field names are taken from those.

Legend: **[verified]** = read in code on `main`, or observed live on 2026-10-06. **[decision]** =
proposed here. **[open]** = needs the owner.

---

## 1. Answers first

| Ask | Answer | Section |
|-----|--------|---------|
| Why isn't Area54 showing? | The phone only discovers hosts on its own LAN. The cloud is not a source for the host tree, and the cloud has no list of an account's installs to read yet. A host that is not on this LAN, or has LAN discovery off, cannot appear. | 2 |
| Platform per host | The desktop already advertises it (`os`); the phone ignores it. Read it and show `Windows` / `macOS` / `Linux`. No wire change needed for LAN hosts. | 4.1 |
| Channel name, only when more than one | The phone already hides a lone channel's name. But narko shows one channel because it runs three and shares only one on the LAN, so the rule never fires. Needs a count of running channels from the host. | 4.2 |
| LAN or cloud | A route badge on each host (or channel). Today every row is LAN, so it is a label only; it matters once cloud hosts exist. | 4.3 |
| HOST / SANDBOX per agent | The desktop knows it (`agentMode`) but sends names only. Add one additive field. | 4.4 |

---

## 2. Why Area54 is not showing

**[verified] What the phone does today.** Discovery is LAN-only: mDNS, a UDP probe, QR and manual
entry (`lib/core/discovery/`). Every source becomes an endpoint in `FleetStore`
(`SPEC_LIVE_FLEET_TOPOLOGY` section 5). `SPEC_LIVE_FLEET_TOPOLOGY` section 9 lists "cloud installs
feeding the same store" as not built.

**[verified] What the cloud path is.** The app's cloud code (`MuxbusClient.getAgents`) reads a flat
list of the account's agents: `id`, `last_seen`, `messages_sent`. It carries no host, channel or
platform, so it cannot build a host card. It is also a separate signed-in screen, not part of the
discovery tree. The emulator build used for this check has no sign-in settings (the `MUXBUS_*`
`--dart-define`s), so it cannot reach the cloud at all.

**[verified] What the cloud knows.** The public desktop spec
(`SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md`, section 2) records that the client has no
presence or agent-list API for other installs and that the per-account directory it needs is
Phase 3, not built. So even a signed-in phone could not list Area54 today.

**[verified] Evidence for the emulator.** The discovery relay on this machine relayed UDP replies from
exactly three LAN addresses, which are the three hosts on screen. Nothing else answered.

**[verified] Evidence that Area54 is not a LAN peer of this machine.** Area54 and narko exchange jekts
over the cloud (`DELIVERY=wan`), not over the LAN (`INVESTIGATION_V0_57_6_FRESH_PORTABLE_DEBUG_LOG_2026_09_25.md`
section 6, in `agentmux`).

**[open] Not verified:** whether Area54 shares a subnet with the phone and simply has LAN discovery off.
Both cases look the same from here (silence). It is checked on Area54's own desktop (is LAN
discovery on?) and by comparing its network with the phone's. Either way the phone should say so rather than omit the host (section 4.5).

So the fix for "Area54 missing" is not a UI change. It needs the cloud tier of the host tree
(section 6, Phase 2). Sections 4.1 to 4.4 are independent of it and can ship first.

---

## 3. Findings behind the other asks

All **[verified]** on 2026-10-06, narko, desktop `main` and a live probe.

| # | Finding | Evidence |
|---|---------|----------|
| G1 | `os` is already on the wire. | mDNS TXT carries `os`; the UDP identity reply sets `response["os"]`. The 47891 reply the phone reads is that identity reply plus `siblings`. A live probe of narko returned `"os":"windows"` next to `channel`. The phone's `LanInstance` has no `os` field, so it is dropped. |
| G2 | `os` is not in the fleet feed. | `GET /agentmux/fleet` has `epoch, rev, hostname, channel, version, agents` only. |
| G3 | `os` is a plain lowercase token, sanitized on receipt. | `host_os.rs`: `^[a-z0-9_-]{1,16}$`; self-reported, display only. |
| G4 | Narko runs three channels and shares one. | Three srv processes listen. Only one binds a LAN address and has a LAN instance file; the other two listen on loopback only. The probe reply's `siblings` is `[]`. The phone therefore sees one channel, and one channel means no channel name. |
| G5 | The HOST / SANDBOX distinction exists on the desktop and not on the wire. | Block meta `agentMode` is `"host"` or `"container"`; `RuntimeBadge` shows `HOST` / `SANDBOX`; `operator_config_seed::agent_kind` maps it. The registry entry (`AgentEntry`) and the fleet feed carry no mode. |
| G6 | The LAN `instance_id` is the version string, not an install id. | Comment in `lan_discovery.rs`: "`instance_id` is the *version*". So a LAN record cannot be matched to a cloud install today. |

---

## 4. Design

### 4.1 Platform tag per host

- Label from `os`: `windows` -> `Windows`, `macos` -> `macOS`, `linux` -> `Linux`. Any other value, or
  no value (an older build), shows no tag. Nothing is derived from a hostname or version.
- Shown on the host row, before the route badge (4.3): `narko   [Windows] [LAN]`.
- Source: `LanInstance.os`, parsed from the UDP reply and the mDNS TXT record. Validate against
  `^[a-z0-9_-]{1,16}$` on receipt, as the desktop does; unknown values are dropped.
- A host with several channels has one platform (they share a machine). If channels disagree (a
  Windows host with a WSL instance appears as two instances with different `os`), the host is shown
  once per distinct `os`, keyed `(hostname, os)`. [decision] The desktop spec keeps these as two
  sections for the same reason.
- Cloud hosts take `os` from the install record (section 6).

### 4.2 Channel name, only when there is more than one

The rule is already built: `HostNode.showChannels` is `channels.length > 1`. What is wrong is the
count. A host counts as having one channel when the phone can *see* one, not when it *runs* one (G4).

[decision] Rule: show channel names when the host has more than one **running** channel, where the
host reports the total. Two parts:

1. The host adds `channels_running` (an integer, 1 to 99) to the UDP reply and the fleet feed. It
   counts every channel of this machine's user that is up, including ones that do not share on the LAN.
   It is a count only: no names, no ports, no keys.
2. When `channels_running > 1` the card shows channel rows even if only one is visible:
   the visible channel by name, and one muted line `+2 not shared on LAN`. When `channels_running`
   is absent (older build) the existing rule applies, based on the visible channels.

On narko today this would read:

```
narko   [Windows] [LAN]
  stable                             LAN
     Camper   HOST
     AgentX   HOST
  +2 channels not shared on LAN
```

**D1 (decided, section 12).** The earlier spec chose that a channel with LAN discovery off is never
listed (`SPEC_LIVE_FLEET_TOPOLOGY` section 4.3 and 7). A count does not list it, name it or expose its
key, so it does not reverse that.

A channel with no `channel` reported keeps the existing `:<port>` label.

### 4.3 How we're connected: LAN or cloud

- Every endpoint has a **route**: `lan` (found by mDNS, UDP, QR or manual) or `cloud`.
- A host or channel shows a badge: `LAN`, `Cloud`, or `LAN + Cloud` when both are live. When both are
  live the phone uses the LAN and keeps the cloud as the fallback; the badge says both so a
  "why is it slower now" question has an answer.
- Where it appears: on the channel row when channel rows are shown, otherwise on the host row. A host
  can legitimately mix (one channel on the LAN, another reachable only by cloud); then each channel
  carries its own badge and the host row shows none.
- Manual and QR entries are `LAN` unless the address is not private, in which case the badge reads
  `Direct`. [decision]
- The agent detail screen shows the route too, because it is the route an injection takes.

**A LAN channel and a cloud channel become one only by install id, never by hostname.** [decision]
Merging endpoints by hostname would let a device on the LAN calling itself "Area54" receive messages
meant for the cloud Area54. A LAN record has no install id today (G6); section 5 adds it, and section 7
gives the merge rules.

### 4.4 HOST / SANDBOX tag per agent

- A small tag at the right of each agent row: `HOST` or `SANDBOX`. The mapping is the desktop's:
  `agentMode` `"host"` -> `HOST`, `"container"` -> `SANDBOX`. Same colours and wording as
  `RuntimeBadge`.
- An agent whose kind is not reported (older build, or the cloud list today) shows **no tag**, not a
  guess. A new value the phone does not know shows no tag.
- Wire (section 5): one additive field. The names list stays a list of strings, so older phones are
  unaffected.

### 4.5 Saying what we do not know

Following P12 of the earlier spec: the host card never implies "this is everything".

- A signed-out phone, or a build with no cloud settings, shows one muted line under the list:
  `Cloud hosts are not shown (not signed in)`.
- Signed in but the cloud call failed: `Cloud hosts unavailable`, with the reason in the debug log.
- A phone that has seen Area54 before and no longer hears it on the LAN dims it (existing presence
  rule) rather than dropping it at once.

### 4.6 Layout

```
AgentMux
┌──────────────────────────────────────────────┐
│ charlie   [Windows] [LAN]       v0.59.5       │
│   Maricon   HOST                              │
│   Opaz      HOST                              │
├──────────────────────────────────────────────┤
│ narko     [Windows] [LAN]       v0.59.11      │
│   stable                                     │
│     Camper   HOST                             │
│     AgentX   SANDBOX                          │
│   +2 channels not shared on LAN               │
├──────────────────────────────────────────────┤
│ Area54    [macOS] [Cloud]       v0.57.5       │
│   AgentA    HOST                              │
└──────────────────────────────────────────────┘
```

(Area54's platform and agents are illustrative; its platform is not known from anything read today.)

The address and port stay out of the host row's main line (they are in the debug view and the agent
screen): the host row now carries platform, route and version.

---

## 5. Wire contract, LAN (desktop, `agentmux-srv`)

All additive; every older phone and desktop ignores unknown fields.

### 5.1 `GET /agentmux/fleet` and `fleet` events

```json
{
  "epoch": "9f2c41d07a6b3e58", "rev": 12,
  "hostname": "narko", "channel": "stable", "version": "0.59.11",
  "agents": ["AgentX", "Camper"],
  "os": "windows",
  "install_id": "mw3am46w5weex4a4fqrc3avnua",
  "channels_running": 3,
  "agent_kinds": { "AgentX": "container", "Camper": "host" }
}
```

- `os`: `host_os::local_os()`.
- `install_id`: this install's WAN instance id (`wan_identity` `instance_ensure`, 26 chars of lowercase
  base32), the id the cloud tier keys its records by. Not a secret: it is a hash of the instance's
  public key. Omitted when the instance identity store is not available.
- `channels_running`: 1 for this channel plus the number of other channels of this machine that have a
  live entry in the host-global shared registry (`swarm_remote::other_channels` with its own
  `HIDE_AFTER_MS`). A channel with no agent registered does not count; that is acceptable for a hint.
  Range 1 to 99.
- `agent_kinds`: one entry per name in `agents`, value `"host"` or `"container"`, from the agent's
  block `agentMode` through `operator_config_seed::agent_kind`. An agent whose block cannot be read is
  left out (the phone shows no tag).
- A change in `agent_kinds` or `channels_running` bumps `rev`, like a change of names.

### 5.2 `GET /agentmux/reactive/agent-names`

Adds `agent_kinds` with the same shape. `agents` is unchanged.

### 5.3 UDP 47891 reply (and the desktop identity reply)

Adds `install_id` (when known) and `channels_running`. `os` and `channel` are already there. The reply
must stay within `lan_instances::MAX_REPLY_BYTES`; siblings are trimmed first, as today.

### 5.4 mDNS TXT

Adds `install_id` when known. `channels_running` is not put in TXT (it changes, and TXT updates are
costly); the phone reads it from the fleet feed.

---

## 6. Wire contract, cloud (relay and desktop)

This is Phase 3 of the desktop Swarm spec, built here for the phone first. The desktop Swarm can read the
same list later.

### 6.1 The record

One record per install (one AgentMux instance: a channel on a machine), published by that install:

```json
{
  "v": 1,
  "instance_id": "mw3am46w5weex4a4fqrc3avnua",
  "instance_public_key": "<standard base64, 32 bytes>",
  "hostname": "narko",
  "channel": "stable",
  "os": "windows",
  "version": "0.59.11",
  "channels_running": 3,
  "agents": [ { "name": "AgentX", "kind": "container" }, { "name": "Camper", "kind": "host" } ],
  "published_at_ms": 1791352493388,
  "sig": "<standard base64, 64 bytes>"
}
```

Bounds: `hostname` and `channel` 1 to 128 chars, `version` 1 to 64, `os` matches `^[a-z0-9_-]{1,16}$`
or is empty, `channels_running` 1 to 99, at most 200 agents, `name` 1 to 128 chars, `kind` is `host`
or `container`. No string may contain a control character (U+0000 to U+001F).

**Signature.** Ed25519 by the instance key over the UTF-8 bytes of these fields joined by U+0001:

```
"amx-install-presence-v1", v, instance_id, hostname, channel, os, version,
channels_running, agents_canonical, published_at_ms
```

Numbers in decimal. `agents_canonical` is the agents sorted by `name` lower-cased (ties by `name`),
each written `name` U+0002 `kind`, joined by U+0003; empty when there are none. The record's `agents`
array is sent in that same order. Test vectors are shared between the Rust and TypeScript suites, as
for the WAN key records.

### 6.2 Relay routes

Both take the signed-in account's Cognito access token and see only that account's installs. The
relay side is specified and built in the cloud repository; this is what a client needs.

- `PUT /wan-instances/:instance_id/presence`, the record of 6.1 as the body. `200 { "stored": true }`;
  `400` for a record that is malformed, not signed by the instance it names, or more than 10 minutes
  from the relay's clock; `410` for an instance its owner revoked; `404` from a relay that predates
  the route. Each publish replaces the install's previous record.
- `GET /wan-instances` answers `{ "instances": [ <record> + "received_at_ms" ... ] }`: the account's
  installs heard from in the last 24 hours, revoked installs left out, sorted by hostname then channel.

The phone trusts the relay for the list (same account, TLS); it does not re-verify signatures in this
phase.

### 6.3 Desktop publisher

`muxbus/wan_presence.rs`, beside `wan_publish.rs`, using the same account token and base URL:

- Builds the record from the fleet feed's snapshot (names, kinds), `channels_running`, `local_os`,
  hostname, channel and version, and signs it with the instance key.
- Publishes once signed in, on every change of the snapshot (debounced 2 s), and every 60 s
  otherwise. Not signed in: does nothing. A 404 (an older relay): retries hourly. Any other failure:
  retries at the next tick. Never logs the token or the signature.

### 6.4 The phone

- Signed in: a `CloudInstanceSource` fetches `GET /wan-instances` on start, every 30 s in the
  foreground, and on pull-to-refresh; stopped in the background, like LAN discovery.
- Each record becomes a channel entry with route `cloud`. Presence: `live` while
  `received_at_ms` is under 3 minutes old (three publish intervals), `stale` after, hidden after 24
  hours (the relay stops returning it).
- Tapping a cloud-only agent opens the existing cloud agent screen (`/agents/:id`); a LAN or merged
  agent opens the LAN screen, as today.

---

## 7. Merging LAN and cloud

- A **channel** seen both on the LAN and in the cloud list is one channel when its LAN `install_id`
  equals the cloud record's `instance_id`. Its route is `LAN + Cloud`, and it is reached over the LAN.
- Channels are grouped into **hosts** by lower-cased hostname, LAN and cloud alike, as the desktop
  Swarm does. A host card can therefore hold a LAN channel and a cloud-only channel; each keeps its
  own badge and its own endpoint. Grouping is display only: a message to an agent always goes by its
  own channel's endpoint, never by a route chosen from a hostname.
- `install_id` is not a secret, so a LAN device could advertise another install's id. A merged channel
  is then reached over the LAN, which is exactly the exposure a LAN-only phone has today (a LAN peer
  is network-claimed). The merge adds no new path for a message.
- Agents of a merged channel: the LAN list wins when both answered within the presence window (it is
  fresher); kinds are taken from whichever source has them.
- `channels_running` of a host is the largest value any of its channels reports.

---

## 8. Mobile changes

- `LanInstance`: add `os`, `channelsRunning`, `installId`; `LanAgent`: add `kind`.
- Fleet transport and store: carry `os`, `install_id`, `channels_running`, `agent_kinds` from the fleet
  feed and the names fallback; existing `rev` rules unchanged.
- UDP prober and mDNS scanner: read `os`, `install_id`, `channels_running`; validate `os`.
- `CloudInstanceSource` and its client call (`MuxbusClient.getInstances`).
- `host_tree.dart`: `Route` per channel; `HostNode.platform`, `HostNode.channelsRunning`; merge (7);
  `showChannels` is `max(channels.length, channelsRunning ?? 0) > 1`; the `+N` line.
- `host_card.dart`: platform tag, route badge, `HOST` / `SANDBOX` per agent, one shared `TagChip`;
  the endpoint line moves off the host row; the signed-out and cloud-error notes (4.5).
- Demo data: a host of each platform and route.

---

## 9. Phases (all being built; owner, 2026-10-06: "lets build it all")

| Phase | What | Repos |
|-------|------|-------|
| **0** | `os`, platform tag, route badge, endpoint line | mobile |
| **1** | 5.1 to 5.4; agent tags; channel count and `+N` line | desktop, mobile |
| **2** | 6 and 7: presence record, relay routes, publisher, cloud source, merge | cloud, desktop, mobile |

A phone sees Phase 1 fields once the hosts run a desktop release that has them, and cloud hosts once
the relay change is deployed and the hosts run that release. Each repo's change works on its own
against the others' older versions.

---

## 10. Testing

- **Parse:** `os` accepted only as `^[a-z0-9_-]{1,16}$`; unknown `kind` gives no tag; missing fields
  never throw; oversized lists are cut.
- **Tree:** platform per host; `showChannels` with `channels_running` 1, 3 and absent; the `+N` text;
  route per channel; merge by install id; same hostname with different ids stays two channels under
  one host; a cloud-only agent routes to the cloud screen.
- **Signature vectors:** one fixed key, record and signature asserted by both the Rust and the
  TypeScript tests.
- **Relay:** each rejection (bounds, path mismatch, id mismatch, bad signature, clock skew, revoked,
  no account), the 24-hour cut, account scoping (another account's rows never returned).
- **Desktop:** fleet shape with the new fields; `rev` bumps on a kind change; agent-names fallback; UDP
  reply fields and size; publisher builds a record that verifies, skips when signed out, backs off on 404.
- **Live:** the emulator against narko (three channels, one shared), charlie and starpower; a signed-in
  phone against a cloud-only host once the relay and desktop changes are deployed.

---

## 11. Security and privacy

- Platform, kind, channel count and route are **display data**; nothing reads them for a decision.
  Everything from a peer or the relay is bounded and validated.
- `agent_kinds` tells a LAN peer which agents run in a sandbox: a small widening of the "names only"
  line (owner decision 2026-09-08), at the owner's request; it says where an agent runs, not what it
  does, and goes only to `lan_key` holders, as the names already do.
- `channels_running` is a number: no names, ports, branches or keys.
- The cloud list is new data leaving the machine: hostname, channel, platform, version and agent names
  and kinds, to the account's own relay, readable only by the same account. The desktop Swarm spec's
  open question 2 ("may the cloud tier send agent names off the machine?", recommended yes, same
  account only) is answered yes by the owner's request; the publisher runs only while signed in.
- Merging never creates a new route for a message (7).
- No token, key or signature is logged.

---

## 12. Decisions

Taken by the owner on 2026-10-06 ("lets build it all") on the recommendations above:

1. **D1**: show the count of channels not shared on the LAN (`+2 channels not shared on LAN`).
2. **D2**: put agent kinds on the LAN feed.
3. **D3**: merge LAN and cloud channels by install id only; group hosts by hostname for display.
4. **D4**: build the cloud list now (Phase 2), together with Phases 0 and 1.

## 13. Not in this work

- Agent status (running / idle) or any content on the phone.
- Acting on agents of other machines (stop, broadcast); that is the desktop's own open question.
- A user-set alias for a host name (open in the desktop Swarm spec).
- The desktop Swarm reading the cloud list (its Phase 3 UI); the relay routes are ready for it.
