# Spec: Agent working / idle status, and a read-only live feed of an agent's pane, on a paired device

**Status:** adopted 2026-10-07 on the recommendations (owner: "use your best recommendations, lets get it
complete"); phases 1 to 3 being built, 4 and 5 deferred as recommended. Owner request: "we want to know the 'working' and 'idle' state of each
of the agents. we also want to work on a live feed of each agent's pane, for now read only. tap the
agent name and you see the live feed directly. lets do an analysis, write spec to file."
**Author:** AgentY
**Scope:** `agentmux-mobile` (status chips, the feed screen, pairing), `agentmux` / `agentmux-srv` (a
status field, a viewer credential, an encrypted read-only feed), and later the cloud path.
**Builds on:** `SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md` and
`SPEC_LIVE_FLEET_TOPOLOGY_2026_10_03.md` (this repo). In `agentmux`:
`SPEC_SWARM_OTHER_HOSTS_AND_CHANNELS_2026_10_02.md` (§6 and §9 item 1: remote status and content),
`SPEC_CROSS_HOST_AGENT_ACCESS_2026_10_01.md` (grants, "L0 observe", never hand out the instance key),
`SPEC_AGENT_PANE_CROSS_CHANNEL_LAN_WAN_SYNC_2026_08_21.md` (pane output fan-out, paired viewers),
`SPEC_MUXSPECT_CROSS_TIER_CONVERSATION_VISIBILITY_2026_08_21.md` (`conversation_visibility`).

**Device** means the device running AgentMux Mobile: a phone or a tablet today. The viewer grant and
the feed are not specific to it; another AgentMux desktop or a web viewer could use them the same way.

Legend: **[verified]** = read in `agentmux` `main` (`ecf037d4f`) or this repo's `main`, 2026-10-07.
**[decision]** = proposed here. **[open]** = needs the owner.

---

## 1. Summary

| Ask | What exists | What this spec adds | Size |
|-----|-------------|---------------------|------|
| Working / idle per agent | The desktop backend already knows, per agent, whether a turn is running (`turn_active`) and derives `Running / Idle / Done / Error`. Nothing a device can reach carries it. | A small `agent_status` field on the LAN feed and in the cloud install record. | Small. Needs the "names only" line moved by one field. |
| Live feed of an agent's pane, read-only, on tap | The pane's content is the agent's transcript, appended and pushed live on the desktop. Every read path is full-key only and served on loopback only. The device has no read path at all. | A **paired viewer** credential, an **encrypted** read-only stream of one agent's transcript, and a feed screen that opens when you tap an agent. | Large. Needs a pairing flow, an encrypted listener and a renderer. |

Status is cheap and close to done. The live feed is content, so it must not ride on anything that is
readable by every device on the network, and it needs encryption on the wire. That is most of the work.

---

## 2. What exists

### 2.1 Working / idle **[verified]**

- **Backend is the authority.** `TurnActivityTracker` (`blockcontroller/health.rs:81`) holds
  `active_turn`; it is set when a turn starts and cleared on the provider's end-of-turn frame (Claude:
  `persistent/stdout_reader.rs:193`), for persistent, ACP, Codex app-server and one-shot controllers.
  It also records what started the turn (`TurnOrigin { User, Automated, System }`).
- **Derived lifecycle.** `broker/process.rs:69`: `enum Lifecycle { Running, Idle, Done, Error, Unknown }`
  from `turn_active` plus process state (`lifecycle_from`, :155).
- **On the wire today (full key, loopback only):** `controllerstatus` WS event with `turn_active`
  (republished every 20 s during a turn), `block.GetControllerStatus`, `processbroker:status-changed`,
  `GET /agentmux/reactive/transcript` (`turn_active`), `GET /api/v1/muxspect/conversations`.
- **Not on any LAN route.** The fleet feed and `agent-names` carry names (and, from #4426, kinds). The
  route's doc comment records the owner decision of 2026-09-08: "Do not extend this response with
  anything beyond names without revisiting that decision." The desktop Swarm spec (§6) already classed
  running / idle as "activity metadata, not content" and recommended it as Phase 4 (§9 item 1, open).
- **Beyond working / idle.** The desktop's own UI also knows: a question pending for the user
  (`term:awaiting_user` block meta, counted only during a turn), compacting, rate-limited (a sub-state of
  streaming), interrupted, disconnected.
- **Known edges.** (a) Agents run in a terminal pane (shell controller) never report a turn
  (`turn_active` hard-coded false), so for them "idle" would be a lie. (b) A turn whose end frame is lost
  recovers only after about 180 s. (c) The desktop's working indicator goes dark when only accepted
  background work remains; the backend's `turn_active` does not apply that rule, so the two can briefly
  disagree. (d) A `turn_active` that ended is an absent field, so readers must treat absent as false.

### 2.2 Pane content **[verified]**

- **What a pane shows** is the agent's transcript: the block's `output` file, the provider's raw
  stream-json, one frame per line (user prompts, assistant text, tool calls and results). The desktop
  frontend parses it (`useAgentStream.ts`) into the document the pane renders.
- **Live updates:** every append is written, then published as a `blockfile` event
  (`{zoneid, filename:"output", fileop:"append", data64, pos:[{stream, gen, line, lines}]}`), and
  `replace` / `delete` when the transcript is rewritten. `gen` and `line` already make a resumable
  cursor.
- **Bounded reads:** `blockfile:read_range` (`offset`, `limit` up to 10 000, `tail_turns`,
  `tail_bytes`, `expect_gen`) serves the pane's backfill. Recent work (#4416, #4417) keeps large
  transcripts from blocking it.
- **Every read path needs the full instance key and is on the loopback router only:** `/ws`, the
  `blockfile:*` RPCs, `GET /agentmux/reactive/transcript` (`GetAgentTranscript`, tail only, at most 500
  lines, pull), `muxspect` routes. The LAN listener serves only the LAN routes.
- **The `lan_key`** is broadcast in the mDNS record and the UDP probe reply, so anything on the network
  can read it. The cross-host access spec's rule: it "proves nothing and must never gate anything
  privileged".
- **QR pairing today** puts the **full instance key** in the QR (`agentmux://connect?...&token=<key>`).
  Since the LAN listener was split from loopback (#3875), that key opens nothing more than the LAN routes
  over the network, and it changes on every desktop restart.
- **No consumer of `conversation_visibility` exists yet** (the transcript-request responder is not
  built). The setting defaults to `private`.

### 2.3 The mobile app **[verified]**

- Tapping an agent opens `LanAgentScreen`, a composer that **sends** a message (`/agentmux/reactive/inject`
  with the `lan_key`). A cloud-only agent opens the cloud agent screen (messages addressed to the agent).
- No transcript, status or pane data is read anywhere.

---

## 3. Agent status

### 3.1 States shown

| State | Chip | From (desktop) |
|-------|------|----------------|
| `working` | green, animated dot, "working 3m" | `turn_active` |
| `waiting` | amber, "needs you" | `turn_active` and `term:awaiting_user` |
| `idle` | grey | process alive, no turn |
| `stopped` | grey outline | process exited cleanly |
| `error` | red | process exited with an error |
| none | no chip | unknown: older desktop, a terminal-pane agent, or the block can't be read |

[decision] Terminal-pane agents (shell controller) report **no state**, not `idle`, because nothing tracks
their turns. Rate-limited, compacting and interrupting count as `working`; they are refinements for later.

### 3.2 Wire (desktop)

All additive.

- `GET /agentmux/fleet` and its events add
  `agent_status: { "<name>": { "state": "working", "since_ms": <unix ms> } }` and `now_ms` (the
  desktop's clock when the snapshot was made, so the device shows "for 3m" without trusting its own
  clock against the desktop's).
- `GET /agentmux/reactive/agent-names` adds the same `agent_status`.
- A state change bumps `rev`, like a name change. The feed already compares once a second and coalesces,
  so a turn that starts and ends within a second may not be seen; that is acceptable for a chip.
- Computed in srv from `get_block_controller_status(..).turn_active`, the controller type, the process
  state and the block's `term:awaiting_user`, through one function that both the feed and the cloud
  record call. Unit-tested state by state, including the shell-controller case and absent-means-false.

### 3.3 Cloud

The install presence record (from `SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS`) gains `state` per agent. A
state change is published at most every 10 s per install (debounced), not on every flip, so an account
with many busy agents stays within the cloud's per-account request budget. The device reads the list
every 30 s, so a cloud-only host's chips can lag by up to about 40 s; the chip says "as of 30 s ago" when
the record is older than a minute. Live status for cloud hosts comes with the cloud feed (section 7).

### 3.4 Privacy

`agent_status` is activity metadata: when an agent is busy and since when, nothing it says or does. Like
names and kinds, it goes to `lan_key` holders, which means anyone on the network. **[open] D1:** the
owner's request answers the desktop Swarm spec's §9 item 1 ("then running/idle, recommended, no content")
and moves the 2026-09-08 "names only" line by one more field. Recommended: yes.

---

## 4. The live feed: who may read, and how

The feed is content: prompts, code, file contents in tool results, possibly secrets an agent printed.
It needs three things the LAN routes do not have.

### 4.1 A credential that is not public **[decision]**

Not the `lan_key` (public on the network) and not the instance `auth_key` (it opens everything srv can
do, including shells, and changes on every restart). Instead, a **viewer grant**:

- **Pairing.** The desktop shows a QR in the existing host popover ("Pair a device"). It carries the
  host's address and port, a one-time pairing code (expires in 2 minutes, single use), and the
  fingerprint of the desktop's TLS certificate (4.2). The device scans it, connects, presents the code and
  its own device public key, and receives a **viewer token**.
- **Scope.** The token admits only the read-only viewer routes (status and the feed); never inject,
  never anything on the loopback router. It survives desktop restarts (stored in the instance's
  database, hashed). It is a bearer secret, sent only inside the pinned TLS session (4.2). The device
  also registers a public key at pairing, unused until the cloud feed (section 7) encrypts to it.
- **Desktop side.** Settings lists paired devices (name, paired when, last seen) with **Revoke**. A new
  pairing shows a toast. Matches the cross-host access spec's "L0 observe" grant and its rule never to
  hand a remote caller the instance key.
- **Replaces today's QR.** The new QR no longer carries the instance key. The existing manual entry
  stays for the LAN routes.

### 4.2 Encryption on the wire **[decision]**

The LAN routes are plain HTTP, which is fine for names and not for content. The viewer routes are served
on a **TLS** listener with a self-signed certificate the desktop generates once and keeps; the device pins
it by the fingerprint from the QR (no CA, no trust-on-first-use). Same port range rules as the existing
LAN listeners, so one firewall rule still covers it. [open] D2: alternatively, application-level
encryption of each frame under a key agreed at pairing; TLS is recommended because it is standard,
covers headers and needs no custom crypto on either side.

### 4.3 Which agents a device may watch **[open] D3**

A paired device is the owner's own device, so the per-agent `conversation_visibility` (built for other
agents asking) does not apply as is. Recommended: a paired device may watch every agent of the channel it
paired with; an agent can be marked **"hide from paired devices"** (one checkbox in the agent's settings), which
removes it from the viewer routes' status and feed. Other channels on the same machine: Phase 4, through
the host-global transcript store, only for channels that have also paired with the device.

---

## 5. The live feed: wire

Viewer routes, on the TLS listener, viewer token only:

- `GET /agentmux/viewer/agents` → `{ now_ms, agents: [ { name, kind, state, since_ms } ] }`, the same
  status as 3.2, minus agents hidden from devices.
- `GET /agentmux/viewer/agents/:name/feed` (Server-Sent Events, the same pattern as the fleet feed):
  - On connect: up to the last 50 turns or 256 KB (`tail_turns` / `tail_bytes` through the bounded
    `read_range` path, never a whole-file read), as one `snapshot` event: `{ gen, from_line, lines: [...] }`.
  - Then one `append` event per published `blockfile` append: `{ gen, line, lines: [...] }`.
  - `id: <gen>:<line>`; a reconnect with `Last-Event-ID` resumes after that line if `gen` is unchanged,
    otherwise sends a fresh `snapshot`. A `replace` / `delete` on the desktop sends `reset`, then a
    `snapshot`.
  - `status` events whenever the agent's state changes, so the screen's chip is live without polling.
  - Heartbeat comment every 15 s; at most 4 feeds per device and 16 per srv; 503 beyond.
  - **Size limits:** a single line over 64 KB (a large tool result) is cut to 64 KB with a
    `truncated: true` flag; the device says "output truncated (open on the desktop)". Nothing is ever
    buffered without bound for a slow device: a stream that falls more than 1 MB behind is closed with
    a `reset` and resumes from a fresh snapshot.
- Lines are the provider's own frames, plus `provider` once per stream. srv does not rewrite them; the
  device renders them (section 6). [open] D4: alternatively srv normalises frames into a small
  provider-neutral shape (`role`, `text`, `tool`, `status`) so the device has one parser. Recommended for
  later, once the device's renderer shows which fields matter; Phase 3 ships the device parsing Claude-shaped
  streams (Claude, and Qwen Code, which emits the same shape) and showing other providers as plain text.

---

## 6. The mobile app

### 6.1 Tap opens the feed

- **Tap an agent name → the live feed**, directly (owner's request). Same for LAN, merged and cloud agents
  once each path exists; until a host is paired the screen says so and offers "Pair this computer"
  (opens the QR scanner).
- **Read-only.** No composer on the feed screen. [open] D5: today's "send a message" screen stays
  reachable from the feed's overflow menu ("Send a message…"), or is removed for now. Recommended: keep it
  in the menu; it already exists and is a different action.

### 6.2 The feed screen

- Header: agent name, `HOST` / `SANDBOX`, the status chip (live), host and channel, and a connection dot
  (`Live`, `Reconnecting…`, `Paused` in the background).
- Body, newest at the bottom, following new output while scrolled to the bottom; scrolling up stops
  following and shows "Jump to latest".
  - Your prompts as bubbles; the assistant's text as Markdown; thinking hidden.
  - Each tool call as one line (`Bash  git status`, `Edit  lib/app.dart`, `Read  …`) with its state
    (running, done, failed); tap to expand its result, monospace, already capped at 64 KB.
  - Turn boundaries as a thin divider with the turn's duration.
  - A question waiting for the user shown as a highlighted card (the desktop answers it; read-only here).
- Long transcripts: only the snapshot's turns are loaded; "Load earlier" asks for the previous 50 turns
  (`before=<gen>:<line>`, a later addition to 5).
- Background: the stream stops (no battery or data use); on return it resumes with `Last-Event-ID`.

### 6.3 Status chips on the host list

The host card's agent rows gain the chip from 3.1 at the right, after `HOST` / `SANDBOX`. A working agent
shows how long ("3m"). Rows do not reorder by state (stable identity, as before).

---

## 7. Cloud (phase 5)

Off the LAN, the same feed needs the cloud. The cloud already carries messages between an account's
installs and devices; carrying a live transcript is a new kind of traffic: more volume, and content
leaving the machine.

- [decision] **End-to-end encrypted.** The desktop encrypts feed frames to the paired device's key;
  the cloud forwards ciphertext and never sees content. Pairing (4.1) already exchanges the keys, so a
  device paired on the LAN can watch the same agents from anywhere.
- **On demand only.** A stream exists only while a device has the feed screen open; the desktop learns of
  the request through the cloud's existing channel to it and stops when the device goes away.
- The cloud-side design (routing, limits, cost) is a separate spec in the cloud repository.
- [open] D6: build the cloud feed, and in which release; it is the most expensive phase.

---

## 8. Phases

| Phase | What | Repos | Depends on |
|-------|------|-------|------------|
| **1** | `agent_status` on the LAN feed, `agent-names` and the cloud record; chips on the device | desktop, mobile | D1 |
| **2** | Viewer grant and pairing: TLS listener, pinned certificate, new QR, paired-devices list with Revoke; device pairing flow | desktop, mobile | D2 |
| **3** | Viewer routes and the feed (5); the feed screen, tap opens it (6), Claude-shaped streams first | desktop, mobile | 2, D3, D4, D5 |
| **4** | Other channels on the same machine; other providers' rendering or srv normalisation | desktop, mobile | 3 |
| **5** | Cloud feed, end-to-end encrypted | cloud, desktop, mobile | 2, D6 |

Phase 1 is a few days of work and stands alone. Phases 2 and 3 together are the first time a device sees a
pane; neither ships content without the other.

---

## 9. Testing

- **Status:** the state function, one case per row of 3.1, the shell-controller case, absent
  `turn_active`, `term:awaiting_user` outside a turn (not `waiting`); `rev` bumps on a state change;
  device chips from fixtures; "for 3m" from `now_ms`, not the device's clock.
- **Pairing:** a code works once and expires; a wrong fingerprint is refused by the device; a revoked
  token is refused on the next request and drops an open feed; the viewer token opens no other route
  (inject, loopback routes, LAN routes' writes); the `lan_key` and the instance key open no viewer route.
- **Feed:** snapshot then appends in order; resume after a dropped connection without gaps or
  duplicates; `gen` change and transcript replace send `reset` and a fresh snapshot; a 5 MB tool result is
  cut to 64 KB; a slow reader is reset, not buffered; stream caps; a hidden agent is absent from both
  routes.
- **App renderer:** Claude-shaped fixtures for prompts, text, tool calls and results, a question, a
  turn boundary; follow and "Jump to latest"; background stop and resume.
- **Live:** an emulator paired with a desktop built from the branch; watch an agent run a turn; restart
  the desktop and see the device resume without re-pairing.

---

## 10. Security and privacy

- **Status** is metadata, on the public LAN feed (D1). **Content** is never on a LAN-key route.
- The viewer grant is read-only, per device, revocable, bound to a device key, and never the instance
  key. Pairing needs physical access to the desktop's screen.
- The feed travels only over TLS pinned at pairing (LAN) or end-to-end encrypted (cloud).
- Agents can be hidden from devices (D3).
- Nothing new is logged beyond states, counts and device names. No content, tokens or keys in logs on
  either side.
- The device keeps feed content in memory only; leaving the screen drops it. No transcript is written to
  the device's storage or its backups.

---

## 11. Decisions

Taken on the recommendations, 2026-10-07:

1. **D1** `agent_status` on the LAN feed and the cloud record: yes.
2. **D2** TLS with a certificate pinned at pairing: yes.
3. **D3** A paired device sees every agent of its channel, with a per-agent "hide from paired devices": yes.
4. **D4** The app parses Claude-shaped frames first; srv normalisation later: yes.
5. **D5** "Send a message…" stays, in the feed screen's menu: yes.
6. **D6** The cloud feed (phase 5) waits until phases 1 to 3 have shipped and are used. Phase 4 waits too.

## 12. Not in this work

- Writing to an agent from the feed (answering questions, approving tools, interrupting).
- Watching terminal (shell) panes.
- Agents of hosts that have not paired with the device, beyond names, kinds and status.

---

## 13. Contract (phases 1 to 3)

### 13.1 Status (phase 1)

- `GET /agentmux/fleet`, its events, and `GET /agentmux/reactive/agent-names` add `now_ms` and
  `agent_status: { "<name>": { "state": "working" | "waiting" | "idle" | "stopped" | "error",
  "since_ms": <unix ms> } }`. An agent with no known state is left out of the map.
- The cloud install record becomes `v: 2`: each agent may carry `state` (same values). The signed
  material for v2 writes each agent as `name` U+0002 `kind` U+0002 `state` (`state` empty when absent);
  everything else is as v1. The cloud accepts v1 and v2. The desktop publishes v2, and a change of states
  alone is published at most every 10 s.

### 13.2 Viewer listener and pairing (phase 2)

- **Certificate.** On first need the desktop creates a self-signed ECDSA P-256 certificate and key and
  keeps them in its data directory. Fingerprint: lowercase hex SHA-256 of the certificate's DER bytes.
- **Listener.** TLS, on each LAN address, on the next free port of the LAN port range; up while LAN
  discovery is on, like the other LAN listeners. Its port is advertised as `viewer_port` in the fleet
  feed and the UDP reply, so a paired device finds it again after an address change.
- **Pairing code.** 10 characters of base32 (A to Z, 2 to 7), single use, valid 120 s. Five wrong codes
  in a minute from one address give 429; ten wrong codes in a row cancel every outstanding code.
- **QR.** `agentmux://pair?v=1&host=<ipv4>&port=<viewer_port>&fp=<fingerprint>&code=<code>&hostname=<name>&channel=<channel>`.
- **`POST /agentmux/viewer/pair`** (no token) `{ "code", "device_name" (1 to 64 chars), "device_key"
  (optional, standard base64 of a 32-byte public key) }` -> `200 { "token", "device_id", "hostname",
  "channel", "version", "install_id"? }`; `401` for an unknown or expired code; `429` as above.
- **Token.** `amxv_` + base64url (no padding) of 32 random bytes, sent as `Authorization: Bearer <token>`.
  Stored as its SHA-256 with the device's name, key, creation and last-seen times. Revoking deletes the row
  and closes that device's open feeds.
- **Desktop UI.** The host popover's "Pair a device" shows the QR with a countdown (RPC
  `viewer.pair-start` -> `{ url, expires_ms }`). Settings has "Paired devices": name, paired, last seen,
  Revoke (RPCs `viewer.devices`, `viewer.revoke { device_id }`). The agent's settings have "Hide from paired
  devices". The old QR (`agentmux://connect` with the instance key) is replaced.

### 13.3 Viewer routes (phase 3)

Viewer listener only; `Authorization: Bearer` required (401 otherwise):

- `GET /agentmux/viewer/hello` -> `{ hostname, channel, version, install_id?, device_id }`.
- `GET /agentmux/viewer/agents` -> `{ now_ms, agents: [ { name, kind?, state?, since_ms? } ] }`, without
  agents hidden from paired devices.
- `GET /agentmux/viewer/agents/:name/feed` (Server-Sent Events; 404 for an unknown or hidden agent):
  - `snapshot` `{ provider, gen, from_line, next_line, lines: [ "<frame>", ... ] }`: the last 50 turns or
    256 KB, whichever is smaller, read through the bounded range read.
  - `append` `{ gen, line, lines: [...] }` for each published append.
  - `reset` `{ reason }` when the transcript is replaced, deleted or its `gen` changes, followed by a
    `snapshot`.
  - `status` `{ state, since_ms, now_ms }` when the agent's state changes (and once after `snapshot`).
  - `id: <gen>:<next line>`; a reconnect with a matching `Last-Event-ID` resumes there, otherwise gets a
    `snapshot`.
  - A frame longer than 64 KB is replaced by `{"type":"amx_truncated","bytes":<n>,"head":"<first 2048 chars>"}`.
  - `: hb` every 15 s. At most 4 feeds per device and 16 per srv (503 beyond). A stream more than 1 MB
    behind is sent `reset` and closed.
  - `provider` is the agent's provider id (`claude`, `codex`, `gemini`, `qwen`, ...).

### 13.4 The device (phases 1 to 3)

- Phase 1: the chip of 3.1 on each agent row from `agent_status` (LAN) or `state` (cloud), "for 3m" from
  `now_ms` and `since_ms`.
- Phase 2: the QR scanner accepts `agentmux://pair`; the device posts the code over TLS pinned to `fp`,
  stores the token, fingerprint, host, port, hostname, channel and install id in secure storage, and shows
  the host as paired. A paired host is matched to discovered channels by install id, else by hostname and
  channel. "Unpair" deletes the local record.
- Phase 3: tapping an agent of a paired channel opens the feed screen (6.2) over the pinned connection;
  an unpaired one shows "Pair this computer" with the scanner. "Send a message…" is in the screen's menu.
