# Report: listing panes and terminals on mobile, and the frozen live feed

**Date:** 2026-10-12
**Status:** §1.3's fixes are in progress: 1, 2, 4 and 5 in agentmux #4758;
6, 7 and 8 in the agentmux-mobile PR that adds this report. Fix 3 is
covered by fix 2 when the lines reach the shared transcript; an append whose
lines never reach it stays unshown (logged at debug). §2.5 phase A (the pane
list) is agentmux #4761 and the agentmux-mobile "All panes" screen; phase B
(terminals) follows.
**Code read at:** agentmux `cf2bb56af` (main), agentmux-mobile `10f117d` (main).
**Related:** `docs/specs/SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md`
(the feed this report is about), `docs/specs/REMOTE_TERMINALS_AND_CONVERSATION_HISTORY.md`
(draft terminal plan, partly out of date; see §2.6).

Two questions from the operator:

1. A conversation scrolls in real time on the desktop but stays frozen in the
   app's live feed. Why?
2. Can the app list the open terminals, and more broadly every active pane on
   the computer? Would each pane type have to be rebuilt for mobile?

Short answers:

1. The feed's server side has two gaps that the desktop pane covers and the
   feed does not. Either one gives exactly this symptom: the snapshot looks
   current, then no `append` ever arrives, while heartbeats keep the header
   saying "Live". The app adds a third, milder one: it only shows complete
   messages, never the streaming text the desktop draws. Which gap hit this
   case can be settled with one `curl` (§1.4). No recent change broke it: the
   feed has worked this way since it shipped on 2026-10-07 (agentmux #4440,
   mobile #48).
2. Yes, and no, most panes don't need rebuilding. List every pane by its
   metadata (one new viewer route), open agents (already built) and
   terminals natively, and show every other pane type as an "open on the
   computer" row. Terminals need a new read-only feed on the desktop and a
   terminal emulator package in the app, behind an off-by-default setting.

---

## 1. The frozen feed

### 1.1 How each side gets live updates

Both read the same transcript and receive the same event: a `blockfile`
append on the agent's block for its `output` file, published by
`append_transcript` (`crates/srv/src/backend/blockcontroller/shell/file_ops.rs:332-389`).
Each append says where its lines landed in up to two streams: the block's own
transcript (`b:<block>`) and the agent's shared transcript (`g:<zone>`,
`agent:<definition>:current`, shared by every block and every srv instance
that runs that agent).

- **Desktop pane:** subscribes to `(blockId, "output")`
  (`frontend/app/view/agent/useAgentStream.ts:557`, `:1029`) and feeds a
  `TranscriptCursor` (`frontend/app/view/agent/transcript-cursor.ts`) that is
  deliberately forgiving: it shows an append that doesn't name its stream,
  fills a gap by reading the missing range, follows a new generation, and
  every 5 s, while it follows the shared stream, asks for the line count to
  catch lines that no event brings (`useAgentStream.ts:1043-1069`: "another
  block or srv instance appending to the agent's shared zone").
- **Phone:** `GET /agentmux/viewer/agents/:name/feed`
  (`crates/srv/src/server/http_viewer.rs:307-344`) looks the agent's block up
  once, subscribes the in-process `FeedHub` to that block
  (`crates/srv/src/backend/viewer/feed.rs:124-160`), sends a snapshot of the
  shared transcript, then forwards each append that `apply_append`
  (`feed.rs:239-267`) accepts. Anything else is skipped, or answered with
  `reset` and a new snapshot.

### 1.2 Causes, most likely first

**1. The feed is tied to the block that was current when it opened.**
`handle_viewer_feed` resolves `name` to a block once
(`http_viewer.rs:313`), and `feed_stream` subscribes to that block once
(`http_viewer.rs:543`). Nothing looks the agent up again while the stream
lives, and the 15 s heartbeat means the phone never has a reason to
reconnect. Meanwhile the agent registry does move an agent to a new block on
a respawn (`crates/srv/src/backend/reactive/handler.rs:413-421`, from
`persistent/spawn.rs:595`) and on HTTP registration. The snapshot comes from
the shared transcript, so it looks current whatever block it was read
through; the appends that follow come from the block now running the agent,
which the hub doesn't watch.

The same blind spot covers a second writer of the shared transcript: another
block of the same agent, or the same agent in another srv instance (another
channel on this machine). Each publishes only on its own broker and under its
own block. The desktop catches those lines with its 5 s line-count poll; the
feed has no poll.

What the operator sees: the snapshot, then nothing; "Live" stays on; the
status chip can keep showing the old block's state.

**2. An append that carries no position in the shared stream is dropped.**
`apply_append` returns `Skip` when the event has no entry for the feed's
stream (`feed.rs:240-242`). `append_transcript` leaves the `g:` entry out
whenever the shared write didn't happen or wasn't counted
(`file_ops.rs:364-367`): the agent lost its lease and `fenced_zone` returned
none (`agent_admission.rs:833-838`, used at `stdout_reader.rs:718`), the
shared write failed, or the line counter was dropped. The desktop shows those
appends anyway (counted as "unpositioned"); the feed skips every one, so the
freeze lasts until the phone reconnects.

**3. The app only shows complete messages.** `Transcript._claudeFrame` ignores
`stream_event` (the token-by-token text) and `thinking`
(`lib/features/feed/transcript.dart:164-165`, `:198`), and skips partial
`assistant` frames (`:138`). The desktop draws `stream_event` deltas
(`frontend/app/view/agent/components/AgentMessageBlock.tsx:23`). During long
thinking or a long reply the desktop scrolls and the phone doesn't move
until the block ends. This looks like a lag, not a permanent freeze, but it
makes every other cause look worse.

**4. A snapshot with an empty generation is rejected.** When the transcript
can't be counted yet, srv sends a snapshot with `gen: ""`
(`http_viewer.rs:445-449`). The app's `_gen` treats an empty string as
missing and drops the whole snapshot (`lib/core/viewer/feed_events.dart`,
`_gen` and the `snapshot` case). The transcript stays null, so the screen
says "Connecting…" while the header says "Live".

**5. Lesser issues found on the way.**
- A `status` event with `state: null` (sent when a state goes away) is
  dropped by `parseFeedEvent`, so the chip never clears.
- A snapshot served from a stale index can end a few lines short; the next
  append is a gap, and srv answers with `reset` and a new snapshot. The phone
  then flickers: this shows as a jump, not a freeze.
- srv logs nothing when a feed opens, resyncs or skips. The live logs of
  0.59.21 have no viewer lines at all, so they can't say which of the above
  happened.
- `viewer_tests.rs` only exercises appends with no shared zone
  (`crates/srv/src/server/tests/viewer/viewer_tests.rs:311-312`); the path
  production uses (`g:` streams) has no feed test.

Checked and ruled out: the event field names and types match between
`snapshot_event`/`append_event` and `parseFeedEvent`; `SseParser` handles
CRLF, comments, `retry:` and events split across chunks; the viewer router
has no compression layer; line counts agree between the append's `g:`
position, `read_range` and `split_records` (they share one blank-line rule).

### 1.3 Proposed fixes

On the desktop (agentmux), in the feed only:

1. **Follow the agent, not the block.** Re-resolve the agent's block on each
   status tick (every second already). When it changes, move the hub
   subscription to the new block and continue from the cursor, or send
   `reset` + snapshot if the cursor can't continue.
2. **Add the shared-transcript poll the desktop has.** While the cursor
   follows a `g:` stream, ask for the line count every few seconds; if it is
   ahead of the cursor, read the missing range and send it as an `append`.
   This catches other blocks and other srv instances, and also cause 2.
3. **Don't drop an append without a shared position.** Treat it like the
   desktop does: when the feed follows `g:` and the event has only `b:`, let
   the poll in fix 2 fill the lines instead of losing them silently.
4. **Log feed opens, resyncs (with the reason) and skipped appends** at debug
   level, with the block id, so the next report can be read from a log.
5. **Test the `g:` path:** a feed with a global store installed; an append
   from another block of the same agent; an append with no `g:` entry; a
   re-registration onto a new block mid-stream.

In the app (agentmux-mobile):

6. **Accept an empty generation** in a snapshot (the server's own feed
   already adopts the first generation of a new transcript,
   `feed.rs:246-248`).
7. **Show streaming text:** build the in-progress assistant text from
   `stream_event` deltas and replace it with the full `assistant` frame when
   it arrives, as the desktop does. Optionally show a "Thinking…" line for
   `thinking` blocks.
8. **Accept `status` with `state: null`** and clear the chip.

Fixes 1, 2 and 6 are the ones that matter for the reported symptom; 7 is what
makes the phone feel live.

### 1.4 How to tell which cause it was

With the agent working, read the raw feed from a computer on the same network
(the token is the paired device's viewer token):

```
curl -k -N -H "Authorization: Bearer <viewer token>" \
  https://<computer ip>:<viewer port>/agentmux/viewer/agents/<agent name>/feed
```

- Only `: hb` lines after the snapshot: the desktop isn't sending (cause 1 or 2).
- `event: append` lines arriving while the phone stays still: the app (cause
  3 or 4). A snapshot with `"gen":""` is cause 4.

To separate 1 from 2 on the desktop: in the agent pane's developer section,
"Transcript cursors" shows the pane's block and its "unpositioned" and
"gaps filled" counts. "Unpositioned" above zero points to cause 2; "gaps
filled" rising points to a second writer (cause 1).

---

## 2. Listing terminals and every pane

### 2.1 What the app can see today

- `GET /agentmux/viewer/agents`: this channel's agents, minus those hidden
  from paired devices (`http_viewer.rs:223-251`).
- `GET /agentmux/viewer/agents/:name/feed`: one agent's transcript, live and
  read-only.
- `GET /agentmux/viewer/procs`: Tower's process list, names only, off unless
  the user turns on `tower:sharewithpaired` (`http_viewer.rs:255-302`). The
  app doesn't call it yet.

Nothing lists panes or terminals over the viewer listener.

### 2.2 Pane types and how to enumerate them

The list of pane types lives in the frontend
(`frontend/app/block/block-registry.ts:34-67`): `term`, `agent`, `browser`,
`editor`, `files`, `sysinfo`, `help`, `launcher`, `swarm`, `media`,
`identity`, `drone`, `warden`, `toolchain`, `tower`, `connectors`, `memory`,
`settings`, and user widgets as `ext:<id>`. srv has no enum: `view` is a
string in the block's `meta`.

srv already holds everything a list needs, in pieces:

- **Layout:** `GET /api/v1/layout` (`crates/srv/src/server/service/introspect.rs:43-96`)
  returns windows, tabs and their panes (`block_id`, `view`, title). It is
  loopback-only, full-key, and leaves out panes that aren't in a tab: agent
  shell drawers and PtyShell shells.
- **Running state:** the process broker (`crates/srv/src/broker/process.rs:83-107`)
  and `get_block_controller_status`
  (`crates/srv/src/backend/blockcontroller/mod.rs:658`): running/done, exit
  code, controller type.
- **Labels:** Tower's `block_label`
  (`crates/srv/src/server/app_api/tower_pane.rs:161-181`): agent name, else
  the pane's title, else "Terminal".

### 2.3 Does each pane type need rebuilding? No

| Approach | Verdict |
|---|---|
| **Metadata list** of every pane: type, label, window/tab, running or not | Do it. One new route; small. |
| **Native view per type** | Only for agents (done) and terminals (new). Sysinfo and Tower are cheap later additions. Editor, files and media would mean serving files off the disk to the phone: a large increase in what a paired device can read. Avoid. |
| **Still screenshot of a pane** | Possible later, opt-in. The desktop can capture one pane (`crates/cef/src/browser_api/routes.rs:314-414`), but only from a visible window; it flickers the window, costs CPU and leaks whatever is on screen. |
| **The desktop's own frontend in a WebView** | Reject. It needs the CEF bridge and the full key over `/ws`, which can type into terminals and drive the UI. The viewer token deliberately opens none of that (`viewer_tests.rs:180-221`). |

So: list everything, open agents and terminals in the app, and show the rest
as rows that say which pane it is and that it opens on the computer.

### 2.4 Terminals

**How they're stored.** Each terminal's PTY output is appended, as raw bytes
with ANSI escapes, to the block's `term` file
(`crates/srv/src/backend/blockcontroller/shell/lifecycle.rs:65-100`). Each
write publishes a `blockfile` event carrying the bytes and the byte offset
where they land, but no line position (`file_ops.rs:140-164`). The file has
no size cap (`FileOpts::default()`, `file_ops.rs:179-183`), so any read must
be a bounded tail, never the whole file.

**Why the agent feed can't carry them.** `FeedHub` passes only the `output`
file (`feed.rs:129`; its test confirms `term` is dropped), and its cursor
counts lines and generations, which `term` events don't have. Terminals need
a byte-offset cursor.

**Size.** One PTY has one size; the last resize wins
(`crates/srv/src/server/websocket.rs:748-763`). A phone must never resize a
terminal (it would re-wrap the desktop's programs). It renders at the
desktop's columns and scrolls sideways. srv doesn't record the current size
today, so it would have to start, to tell the phone.

**Which terminals exist:** terminal panes in tabs, agent shell drawers (a
sub-block named by `term:shellsubblockid`), PtyShell shells, and durable SSH
sessions. The MCP `Shell` tool's sessions have no PTY and nothing stored;
leave them out.

**Side finding:** an agent run inside a terminal pane writes to `term`, not
`output`, so its agent feed is probably empty (not verified).

### 2.5 Recommended plan

**Phase A: pane list (desktop + app).**
- `GET /agentmux/viewer/panes`: every pane with type, label, window and tab,
  running state, and for agents the agent name. Include agent shell drawers
  and PtyShell shells. Leave out hidden agents. Don't send command lines or
  working directories: commands can hold credentials
  (`crates/srv/src/backend/layout_file.rs:490-494` already warns about this).
- App: a "Panes" section per computer, grouped by window and tab. Agent rows
  open the existing feed; terminal rows open Phase B; the rest are
  informational.

**Phase B: read-only terminals.**
- Setting "Share terminals with paired devices", **off by default** (terminal
  scrollback routinely contains secrets, and there is no per-terminal hide
  flag; a per-pane hide flag could come later).
- `GET /agentmux/viewer/terminals/:block_id/feed` (SSE): a snapshot of the
  last ~256 KB of `term`, starting after a newline so it doesn't open
  mid-escape, plus the terminal's columns and rows; then `append
  {offset, data64}` events from a hub variant that accepts `term` and tracks
  byte offsets; `reset` on truncation or when the phone falls behind. Same
  leases, caps (4 feeds per device, 16 total) and 1 MB behind rule as the
  agent feed.
- App: a terminal emulator package (for example `xterm` on pub.dev; it must
  pass the OSV dependency scan), rendering at the desktop's width, never
  sending input or a resize.

**Phase C (separate spec): typing into a terminal.** This is remote code
execution on the computer. It needs its own grant (the cross-host access
spec's L1/L2), confirmation on the desktop, and must never ride on the
read-only viewer token.

### 2.6 What changes in the existing draft

`REMOTE_TERMINALS_AND_CONVERSATION_HISTORY.md` predates the viewer listener.
Its recommended "scoped per-device read credential" now exists (the viewer
token), and its polling plan can use SSE like the agent feed. Its read-only
scope and plain-text-first idea still hold; this report's Phase B goes
straight to a terminal emulator because the bytes already stream with
offsets. Update that draft, or replace it with a spec built from §2.5.

---

## 3. Security rules any of this must keep

- Viewer routes stay only on the pinned-TLS viewer listener, opened only by a
  paired device's token, and that token opens nothing else
  (`http_viewer.rs:4-18`, `viewer_tests.rs:180-234`).
- Read-only. No input, no resize, no file reads.
- Hidden agents are left out of every list and their feeds 404; a new pane
  list must apply the same filter.
- Terminals are opt-in per computer, off by default.
- Bounded everything: tail reads only, the existing frame, behind and
  per-device caps.
- Content is kept in memory on the phone, as today.

## 4. Open questions for the operator

1. Should terminals be shared per computer (one switch) or per terminal?
2. Is a still screenshot of other pane types wanted at all, given what it can
   leak?
3. Fix order: the frozen feed first (fixes 1, 2, 6, 7), then the pane list,
   then terminals?
