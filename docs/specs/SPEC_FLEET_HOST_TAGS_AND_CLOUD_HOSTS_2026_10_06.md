# Spec: Host platform, channel name, route (LAN / cloud) and HOST/SANDBOX tags, and cloud hosts

**Status:** adopted and built, 2026-10-06 (owner request: "For each host we want to know the platform.
If multiple instances are open we also see the channel name; with one channel, no channel name. We
need to know how we're connected, LAN or cloud. Add the HOST/SANDBOX tag next to each agent." Asked
after noticing that a host on another network never appeared.)
**Author:** AgentY
**Scope:** `agentmux-mobile` (UI, store), the fields it reads from `agentmux` desktops, and the list of
an account's installs it reads from the cloud.
**Builds on:** `SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md` (the host -> channel -> agent tree, the store,
presence). In `agentmux`: `SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md` and
`SPEC_SWARM_REMOTE_AGENTS_PLATFORM_TAG_AND_SELECTION_2026_10_03.md`, which ask for the same tags on the
desktop Swarm. The app reads the same as the Swarm, so labels, the naming rule and the field names are
taken from those.

**Device** means the device running AgentMux Mobile (a phone or a tablet).

---

## 1. Summary

| Ask | Answer | Section |
|-----|--------|---------|
| A host on another network never appears | The device only discovered hosts on its own LAN, and the cloud had no list of an account's installs to read. Cloud hosts now come from that list while signed in. | 2, 5 |
| Platform per host | Desktops already advertise `os`. The device shows `Windows` / `macOS` / `Linux`. | 3.1 |
| Channel name, only when more than one | The device hid a lone channel's name, but counted only the channels it could see. A machine now reports how many it runs. | 3.2 |
| LAN or cloud | A route badge on each host or channel. | 3.3 |
| HOST / SANDBOX per agent | Desktops report each agent's kind. | 3.4 |

---

## 2. Why a host on another network was missing

- Discovery is LAN-only: mDNS, a UDP probe, QR and manual entry (`lib/core/discovery/`). A host that is
  not on the device's network, or has LAN discovery off, is silent, and silence looks the same in both
  cases.
- The app's cloud code read a flat list of the account's agents (`id`, `last_seen`, `messages_sent`)
  with no host, channel or platform, on a separate signed-in screen, so it could not build a host card.
- There was no list of an account's installs to read.

So the fix is a new source, not a UI change: the account's install list (section 5), merged into the
same store as LAN discovery.

---

## 3. Design

### 3.1 Platform tag per host

- Label from `os`: `windows` -> `Windows`, `macos` -> `macOS`, `linux` -> `Linux`. Any other value, or
  none (an older desktop), shows no tag. Nothing is derived from a hostname or version.
- On the host row, before the route badge: `host-a   [Windows] [LAN]`.
- Accepted only as `^[a-z0-9_-]{1,16}$`; anything else is dropped.
- A host whose channels disagree (a Windows machine with a WSL instance) is shown once per platform. A
  channel that reports none gets its own, untagged, card.

### 3.2 Channel name, only when there is more than one

A machine reports `channels_running`: its channels that are up, including ones that do not share on the
LAN (a count only: no names, ports or keys). The card shows channel rows when
`max(visible channels, channels_running) > 1`, with a muted `+N channels not shared on LAN` line for the
difference. Without the field (older desktop), the visible count decides, as before. A channel with no
`channel` reported keeps the `:<port>` label.

### 3.3 How we're connected: LAN or cloud

- Every channel has a **route**: `LAN` (found by mDNS, UDP, or a QR / manual private address), `Cloud`
  (from the account's install list), `LAN + Cloud` (both, reached over the LAN), or `Direct` (a QR or
  manual entry whose address is not private).
- The badge is on the host row when all its channels share a route, otherwise on each channel row.
- The agent screen shows the route too.

### 3.4 HOST / SANDBOX tag per agent

- A tag at the right of each agent row: `host` -> `HOST`, `container` -> `SANDBOX`, as the desktop's
  `RuntimeBadge` does. Unknown or missing: no tag.

### 3.5 Saying what we do not know

- Signed out, or a build without cloud settings: `Cloud hosts are not shown (not signed in)` under
  the list.
- Signed in but the list could not be read: `Cloud hosts unavailable`, with the reason in the debug
  log. A relay that predates the list (404) shows nothing and is asked again every 10 minutes.
- A host that goes quiet dims (existing presence rule) rather than vanishing.

### 3.6 Layout

```
┌──────────────────────────────────────────────┐
│ host-a    [Windows] [LAN]       v0.59.5       │
│   Agent1    HOST                              │
├──────────────────────────────────────────────┤
│ host-b    [Windows] [LAN]       v0.59.11      │
│   stable                                      │
│     Agent2   HOST                             │
│     Agent3   SANDBOX                          │
│   +2 channels not shared on LAN               │
├──────────────────────────────────────────────┤
│ host-c    [macOS] [Cloud]       v0.59.11      │
│   Agent4    HOST                              │
└──────────────────────────────────────────────┘
```

The address and port move off the host row to the agent screen; the host row carries platform, route
and version.

---

## 4. Fields read from desktops (LAN)

All optional; a desktop that does not send one behaves as before.

`GET /agentmux/fleet` and its events:

```json
{
  "epoch": "<16 hex>", "rev": 12,
  "hostname": "host-b", "channel": "stable", "version": "0.59.11",
  "agents": ["Agent2", "Agent3"],
  "os": "windows",
  "install_id": "<install id>",
  "channels_running": 3,
  "agent_kinds": { "Agent2": "host", "Agent3": "container" }
}
```

- `install_id`: the install's id in the account's install list (section 5), so a LAN channel and a cloud
  entry for the same install can be recognised as one. 26 characters of lowercase base32.
- `channels_running`: 1 to 99.
- `agent_kinds`: `host` or `container` per name in `agents`.
- `GET /agentmux/reactive/agent-names` adds `agent_kinds`.
- The UDP reply adds `install_id` and `channels_running` (`os` and `channel` were already there); the
  mDNS TXT record adds `install_id`.

---

## 5. The account's install list (cloud)

While signed in, the device reads `GET /wan-instances` with the account's Cognito access token:

```json
{ "instances": [ {
  "v": 1, "instance_id": "<install id>", "hostname": "host-c", "channel": "stable",
  "os": "macos", "version": "0.59.11", "channels_running": 1,
  "agents": [ { "name": "Agent4", "kind": "host" } ],
  "published_at_ms": 0, "received_at_ms": 0
} ] }
```

(Each entry carries more fields than the device reads.) Only the signed-in account's installs are listed,
those heard from in the last day.

On the device:

- `CloudInstanceSource` fetches on start, every 30 s in the foreground, on pull-to-refresh, and at once
  after signing in or out; stopped in the background, like LAN discovery.
- Each entry becomes a channel with route `Cloud`. Presence: live while `received_at_ms` is under 3
  minutes old, stale after.
- Tapping an agent reached through the cloud opens the cloud agent screen (`/agents/:id`); a LAN agent
  opens the LAN screen.

**Merging.** A LAN channel and a cloud entry are one channel only when the LAN `install_id` equals the
entry's `instance_id`, never by hostname. Hosts are grouped by lower-cased hostname for display, LAN and
cloud alike; a message always goes by its own channel's endpoint. For a merged channel the LAN agent list
wins while the LAN answers, kinds come from whichever source has them, and a host's `channels_running` is
the largest any of its channels reports.

**Auth.** MuxBus accepts only Cognito access tokens. The app used to send the ID token, so every
signed-in cloud call failed; it now stores the access token and sends it on every MuxBus request and the
socket, refreshing a session saved before this change.

---

## 6. Mobile changes

- `LanInstance`: `os`, `channelsRunning`, `installId`; `LanAgent`: `kind`.
- Fleet transport and store, UDP prober, mDNS scanner: read and validate the new fields.
- `CloudInstanceSource`, `MuxbusClient.getInstances`.
- `host_tree.dart`: route per channel, platform, channel count, merge.
- `host_card.dart`: one shared `TagChip` for platform, route and kind; the `+N` line and the notes.
- Demo data: a host of each platform and route.

---

## 7. Testing

- **Parse:** `os` accepted only in its shape; unknown `kind` gives no tag; missing fields never throw;
  oversized lists are cut.
- **Cloud source:** signed out does nothing; 404 is quiet; an error shows the note; presence follows
  `received_at_ms` under a fake clock.
- **Tree:** platform per host and the split by platform; channel rows with `channels_running` 1, 3 and
  absent; the `+N` text; routes; merge by install id; the same hostname with different ids stays two
  channels under one host; which screen an agent opens.
- **Widgets:** each tag, the notes, a 320 dp wide screen.
- **Live:** the emulator against real LAN desktops through the discovery relay; a signed-in device
  against a cloud-only host once the desktops and the cloud side are released.

---

## 8. Privacy

- Platform, kind, channel count and route are display data; nothing reads them for a decision.
- `agent_kinds` tells a LAN peer which agents run in a sandbox, a small widening of the "names only"
  line (owner decision 2026-09-08), made at the owner's request. It goes only to `lan_key` holders, as
  the names already do.
- `channels_running` is a number: no names, ports or keys.
- The install list is new data leaving a desktop: hostname, channel, platform, version, agent names and
  kinds, to the account's own cloud, readable only by the same account, and only while signed in.

---

## 9. Decisions

Taken by the owner on 2026-10-06 ("lets build it all"):

1. Show the count of channels not shared on the LAN.
2. Put agent kinds on the LAN feed.
3. Merge LAN and cloud channels by install id only; group hosts by hostname for display.
4. Build the install list now, with the rest.

## 10. Not in this work

- Agent status (running / idle) or any content on the device.
- Acting on agents of other machines (stop, broadcast).
- A user-set alias for a host name.
