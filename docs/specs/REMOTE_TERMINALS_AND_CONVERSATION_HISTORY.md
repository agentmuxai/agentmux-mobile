# Spec: Remote terminals + agent conversation history on mobile

**Status:** draft (proposal — nothing implemented)
**Date:** 2026-09-09
**Author:** Loap #2
**Scope:** `agentmux-mobile` (UI, client) + `agentmux` / `agentmux-srv`
(a scoped read credential, which does not exist yet)

---

## 1. What's being asked

1. **Terminals** — a new section listing the terminals on a connected
   AgentMux instance, and letting you **see their content**.
2. **Agents** — extend the existing section to show an agent's
   **conversation history**.

Both are read-only viewing of content that today only exists on the desktop.

## 2. The headline finding

**Almost every server-side API this needs already exists, and a QR-paired
phone can already reach all of it.** The obstacle is not missing endpoints —
it's that the credential the phone holds is *far too powerful*, and there is
no weaker one to hand it.

So the engineering problem is **reducing** privilege, not granting it. That
inverts the usual shape of a feature spec and drives the phasing in §5.

## 3. Current state

### 3.1 Mobile app

Two largely separate worlds (`lib/app.dart`):

| World | Routes | Can do today |
|---|---|---|
| **Cloud** (muxbus, auth-gated) | `/agents`, `/usage`, `/settings` bottom-nav shell | list agents, read the **message feed**, inject, usage/billing |
| **LAN** (direct to a desktop) | `/discover`, `/instance/:addr/agent/:name` | discover instances, list agents, **inject only** |

Two distinctions worth stating plainly, because they're easy to conflate:

- **The existing "message feed" is not conversation history.** `getMessages`
  (`lib/core/api/muxbus_client.dart:41`) returns `Message` records with
  `from`/`to`/`priority`/`read` — the agent-to-agent **jekt inbox**. An
  agent's actual conversation with its model is a different artifact and is
  not exposed to mobile anywhere today.
- **The LAN agent screen has no history at all** —
  `lib/features/lan_agent/lan_agent_screen.dart` is a name plus a compose bar.

There is a WebSocket broadcast stream (`lib/core/api/muxbus_socket.dart`), but
it is **cloud-tier only**; the LAN path has no streaming channel.

### 3.2 Which credential does the phone actually hold?

**Correction (2026-09-09):** an earlier version of this section argued "the
app calls `GET /agentmux/discovery`, which is full-auth, therefore the app is
already operating with the full `auth_key`." That inference is wrong — it
conflates *calling* a route with *succeeding* at it. The app calls
`/agentmux/discovery` for every instance it knows about regardless of how
that instance was connected; whether the call succeeds depends entirely on
which credential that specific instance carries. Caught via a real Codex
review finding on the PR this spec shipped in, which pointed out the same
conflation independently on a related fix in the same PR
(agentmux-mobile#20/#21) — see that PR's discussion for the sibling case.

There are **three** distinct provenances, not two, and they matter a lot for
what phase 1 can actually do:

| Path | Code | Credential | Reaches `/agentmux/discovery`? |
|---|---|---|---|
| mDNS/UDP scan (the everyday "Discover" flow) | `MdnsScanner`/`UdpBroadcastProber` → `_enrichWithAgents` | narrow `lan_key` | **No — guaranteed 401, always, structurally.** Not staleness, not a bug to fix by retrying: `lan_key` was never valid for this route (`lan_or_full_auth_middleware` grants exactly three routes — `reactive/inject`, `reactive/agent`, `reactive/agent-names` — and `/agentmux/discovery` isn't one of them). |
| QR / manual pairing | `qr_scan_screen.dart` / `manual_add_sheet.dart` → `addManual` | full `auth_key` (`HostPopover.tsx:81-92` encodes `getApi().getAuthKey()` into the QR) | Yes |
| Dev auto-connect | `_maybeAutoConnect`, build-time `--dart-define` | full `auth_key`, baked in at **build** time | Yes, until the desktop restarts — the launcher mints a fresh `auth_key` every run, so this specific path degrades to a 401 over time (see `docs/retro/retro-mobile-dev-and-discovery-session-2026-09-08.md` A4) |

**Consequence this changes:** "No agents reported" on the *existing* Agents
list is not a rare glitch for a plain, mDNS/UDP-discovered instance — it is
the permanent, guaranteed outcome, today, for every instance connected
through the app's primary discovery flow. Only instances added via QR/manual
pairing or dev auto-connect can show agents at all. This spec's Terminals and
History features inherit that same split: they work today, with zero new
server code, **only** for QR/manually-paired instances — never for a plainly
discovered one, regardless of any authorization decision in §4.4.

**What the full `auth_key` also grants**, beyond the read access this feature
wants: `POST /api/v1/shell/create`, `/api/v1/agent/open`,
`/api/v1/fleet/bulk-stop`, `/api/v1/ui/click`, the credential/identity routes,
and `/ws`. It is an all-or-nothing key; there is no read-only tier anywhere in
the system.

> **Security issue found while researching this, worth fixing independently of
> this feature:** the comment justifying the QR's use of the full key
> (`HostPopover.tsx:73-77`) claims the token is *"the SAME value the backend
> already broadcasts in plaintext in its mDNS TXT record."* That was true when
> the QR shipped (PR #2243, 2026-07-20) and stopped being true a month later
> (PR #2572, 2026-08-14), which narrowed the broadcast value to `lan_key`. The
> QR now grants strictly more than mDNS does, and its stated rationale no
> longer holds. This should be raised on its own, not bundled here.

### 3.3 Server — terminals

A "terminal" is not one thing. Four candidates:

| Concept | Backing | Enumerable today? | Scrollback |
|---|---|---|---|
| **Standalone Terminal pane** (`view: "term"`) | `ShellController`, real PTY | ✅ via `GET /api/v1/layout` | blockfiles `term` + `cache:term:full` |
| **Agent shell drawer** | same controller/PTY | ❌ **headless sub-block, not in `tab.blockids`** — id is on the agent block's `term:shellsubblockid` meta | same |
| **Agent's own pane** | `PersistentController` etc. | n/a — not a term view | NDJSON `output` (that's §3.4, not a terminal) |
| **MCP `Shell` session** | `ShellNodeRunner`, no PTY, no block | ✅ via `shell.ListActive` (running only) | ❌ **never persisted** — live `shell_chunk` events only |

**Scrollback persistence is shipped** (`SPEC_TERMINAL_SCROLLBACK_PERSISTENCE_2026_07_23.md`,
PR #2279 — both Part A raw write-through and Part B `SaveTerminalState`;
the spec's own text calling Part B a stub is historical). Stored in SQLite
(`db_wave_file`/`db_file_data`), read via
`GET /agentmux/file?zoneid=<block_id>&name=term|cache:term:full` with
`ptyoffset`/`termsize` in the base64 `X-ZoneFileInfo` header — exactly what
`frontend/app/view/term/termwrap.ts` already does.

Known gap the scrollback spec itself flags: the raw `term` blockfile **grows
unbounded**; nothing truncates it.

### 3.4 Server — transcripts

Stored per-block as NDJSON blockfile `output`, mirrored to a global
cross-channel zone `agent:<definition_id>:current` in a separate filestore;
archived sessions are gzipped and read back transparently.

Read APIs (all full-auth): `GET /agentmux/reactive/transcript?agent=&max_lines=`
(cap **500**, default 100 — `reactive.rs:1797`), `GET /api/v1/muxspect/conversations`
(1-line preview per agent), `blockfile:read_range` over `/ws` for paging, and
`history.*` RPC for past provider sessions.

**Reach: host + one cross-channel hop, loopback only. Never LAN or WAN.** A
phone talking directly to the desktop's HTTP server is "host tier" from the
server's perspective, so this is fine for our case — but it means there is no
existing remote-read path to reuse or extend.

### 3.5 `conversation_visibility` does *not* gate HTTP reads — correcting an easy assumption

Schema v26 added a `conversation_visibility` column (`private` default /
`ask` / `trusted_peers`) and a `db_conversation_trust_grants` table, and
PR #2764 shipped `transcript_request` parsing plus its tier/escalation
enforcement.

But per `SPEC_MUXSPECT_CROSS_TIER_CONVERSATION_VISIBILITY_2026_08_21.md`'s own
Non-goals: *"No retrofit of visibility scoping onto host/cross-channel —
anyone holding the instance key can already read any local agent's transcript,
consent model or not."*

So that consent model gates **only** the (still unbuilt) LAN/WAN
`transcript_request` jekt flow. **An HTTP reader bypasses it entirely, by
design.** Also still unbuilt: any UI or RPC to *set* `conversation_visibility`
or *grant* trust (in practice every agent is `private`), the auto-resolve
short-circuit, and `RequestTranscript`/`PollTranscriptRequest` — nothing
anywhere currently *constructs* a `transcript_request`.

This raises a real product question rather than a constraint — see O-2.

---

## 4. Proposed design

### 4.1 Navigation

Two peer sections plus settings, scoped to the connected instance:

```
Agents   |   Terminals   |   Settings
```

`Agents` keeps its list and gains a **History** tab in detail. `Terminals` is
new. (O-1 covers how this composes with the existing cloud bottom-nav.)

### 4.2 Terminals

**List.** Rows: title/command, owning pane or agent, running/exited, last
activity. Sources, in order of completeness:

- `GET /api/v1/layout` → filter panes with `view == "term"` (standalone panes)
- for each agent block, read `term:shellsubblockid` meta to include
  **agent-shell drawers**, which `layout` alone misses (§3.3)
- optionally `shell.ListActive` for MCP shell sessions — but note their output
  is **never persisted**, so they can be listed and not read. Recommend
  excluding them from v1 rather than showing rows that can't open (O-3).

**Content.** Read `GET /agentmux/file?zoneid=<block_id>&name=…`. Two fidelities:

- **Plain text (recommended for v1):** fetch `term`, strip ANSI, render
  monospace with jump-to-latest. Robust, no new server work.
- **Full xterm fidelity:** replay `cache:term:full` + delta from `ptyoffset`
  the way `termwrap.ts` does. No xterm.js on Flutter; significant work. Defer.

**Paging is mandatory, not optional** — the raw blockfile is unbounded (§3.3).
Use the `offset` parameter and fetch a bounded tail; never fetch from 0.

**Live updates:** v1 is pull-to-refresh/polling. Streaming would need a LAN
WebSocket the app doesn't have (§3.1).

**Read-only.** Terminal *input* is out of scope — see §6.

### 4.3 Agent conversation history

A **History** tab in agent detail, rendering `output` NDJSON as turns, paged,
newest-last. Backed by `/agentmux/reactive/transcript` for a simple bounded
read (remember the 500-line cap), and `blockfile:read_range` over `/ws` if
real paging is wanted.

Keep it visually distinct from the message feed — they are different things
(§3.1) and merging them makes both harder to read.

### 4.4 Authorization — the actual work

Because a QR-paired (or dev-connected) phone already holds the full
`auth_key`, v1 could ship **with no server changes at all** — but, per §3.2's
correction, only for instances connected that way. A phone that only ever
used the app's normal "Discover" flow (mDNS/UDP) is not merely missing a nice
UI for this — it structurally cannot reach any of it, including the
already-shipped Agents list, until something in §4.4 changes.

Shipping on the existing key is also worth not doing quietly even for the
QR/manual case: it would normalize handing phones a key that can spawn
shells, open agents, bulk-stop the fleet, and drive the UI.

Options:

**Option A — scoped read credential (recommended).** A third tier alongside
`auth_key`/`lan_key`: a per-device, revocable, read-scoped token minted at
pairing time, accepted by its own middleware group over a small allowlist of
read routes (`layout`, `file` restricted to `term`/`output` zones,
`reactive/transcript`, `muxspect/conversations`). The precedent for a separate
top-level router with its own middleware already exists
(`lan_or_full_auth_middleware`). Also fixes the §3.2 QR issue as a side effect,
and survives the per-launch `auth_key` rotation that already bites the dev flow
(retro A4).

**Option B — ship v1 on the existing full key, add scoping later.** Fastest to
a demo, but every shipped phone is then a full-privilege client, and revoking
one means rotating the instance key for everyone. If chosen, do it knowingly
and time-box the follow-up.

**Option C — widen `lan_key` to cover reads.** **Rejected.** That key is
broadcast in cleartext to the whole network, LAN transport encryption
(LAN P1-1) is not implemented, and terminal scrollback is raw PTY bytes that
routinely contain secrets. Both `Config::lan_key`'s doc comment and
`handle_reactive_agent_names`' (*"Do not extend this response with anything
beyond names without revisiting that decision"*) draw this line explicitly.
Recorded here so the option is visibly closed rather than silently skipped.

## 5. Phasing

| Phase | Contents | Server work | Works for mDNS/UDP-discovered instances? |
|---|---|---|---|
| 1 | Terminals list + plain-text scrollback (paged, pull-to-refresh) | none strictly required for QR/manual-paired instances (§4.4); Option A if chosen | **No — needs Option A regardless of phase** |
| 2 | Agent History tab | none — `/agentmux/reactive/transcript` exists | **No**, same reason |
| 3 | Scoped read credential + per-device revocation UI | Option A, if deferred from phase 1 | Turns "no" above into "yes" |
| 4 | Live streaming (LAN WebSocket), xterm-fidelity rendering | new WS endpoint | Depends on phase 3 landing first |

Two properties worth being explicit about, since they pull in opposite
directions: the feature works *for QR/manually-paired instances* before the
security work does, which is exactly why §4.4 should be decided **before**
phase 1 ships, not after — and it does **not** work at all for the app's
primary discovery flow until phase 3, regardless of how phases 1-2 are
sequenced. If mDNS/UDP-discovered instances are meant to be the common case
for this feature (plausibly true — QR pairing is presently a fallback/initial
step, not the everyday flow), phase 3 is not really optional-and-later; it is
a prerequisite for the feature mattering to most users.

## 6. Explicitly out of scope

- **Terminal input / command execution from the phone.** Viewing is a read
  capability; typing is remote code execution on the desktop. Own spec, own
  threat model.
- **Widening `lan_key`** (§4.4 Option C).
- **Retrofitting `conversation_visibility` onto HTTP reads** — the upstream
  spec explicitly declines this; changing it is that spec's decision, not this
  one's (but see O-2).
- Cross-instance aggregation ("all terminals on all hosts").

## 7. Open questions

- **O-1 — navigation shape.** Per-instance tabs inside the LAN flow, or
  converge the whole app on one instance-scoped shell? Affects how much of
  `app.dart` moves.
- **O-2 — should mobile voluntarily honor `conversation_visibility`?** It is
  not required to (§3.5), and today every agent is `private` by default, so
  honoring it literally would show nothing. Options: ignore it (matches every
  other host-tier reader), or treat mobile as a distinct tier that respects it
  — which would need the setting to be settable first, which it isn't.
- **O-3 — which terminals count?** Standalone panes only, or also agent-shell
  drawers (needs the `term:shellsubblockid` lookup) and MCP shell sessions
  (listable but **unreadable** — no persisted output)?
- **O-4 — paging/retention limits.** The raw `term` blockfile is unbounded and
  the transcript endpoint caps at 500 lines. What's the phone's tail size?
- **O-5 — authorization option** (§4.4). Gates whether phase 1 ships on the
  full key.
