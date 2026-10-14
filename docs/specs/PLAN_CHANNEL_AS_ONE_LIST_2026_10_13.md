# Plan: each channel as one list on the phone

**Date:** 2026-10-13
**Status:** plan, for the operator's review. Nothing implemented.
**Asked for:** "keep everything in a single list. Tabs don't matter, you can
just keep a label, but it doesn't affect order on mobile. Start with Agents
(as it appears now) and then Swarm, Sysinfo and Tower, those are always
available for selecting. They simply relay info about the instance and it
doesn't matter if they are even open on the instance. All that matters is
there is at least 1 agent for Swarm to show. Sysinfo and Tower always show.
Then after that, list the open terminals by their title." Then: no section
headings; terminals in desktop order, flattened; keep the one-line summaries.
**Code read at:** agentmux `origin/main` 4435e2d, agentmux-mobile `main` 60fa0d5.
**Related:** `SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` (the viewer
channel), the All panes and terminal work (#61, #62; agentmux #4761, #4764),
`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` (a separate track, §6).

## 1. What it looks like

Each channel on the home screen is one list, in this order:

1. **Agents**, as they appear now (state chip, summary line).
2. **Swarm**, when the channel has at least one agent.
3. **Sysinfo**, always.
4. **Tower**, always.
5. **Terminals**, by title, in desktop order flattened (window, then tab,
   then position). The tab is a small muted label on the right; it never
   changes the order.

No section headings: each row's icon and second line say what it is. The
"All panes" row and its screen go away.

```
┌────────────────────────────────────────────┐
│ AgentMux                    ⟳   ⌗   +   ⋮  │
├────────────────────────────────────────────┤
│ 💻 narko  [Windows] [LAN]      v0.59.21  ^ │
│    3 channels                              │
│ ┌────────────────────────────────────────┐ │
│ │ ⑂ local-clamk-release-v0.59…  [LAN] [Paired] ^ │
│ │  ● Clamk        [HOST] (● working 12m) │ │
│ │    Fixing the release notes…           │ │
│ │  ● QTest        [HOST] (● working 14m) │ │
│ │    Mobile feed: phase 5 merged         │ │
│ │  ○ Loap         [HOST] (idle 2h)       │ │
│ │  ⬡ Swarm         3 agents · 2 working ›│ │
│ │  ▤ Sysinfo       CPU 23% · RAM 61%    ›│ │
│ │  ♜ Tower         142 processes        ›│ │
│ │  >_ cargo build            Tab 2      ›│ │
│ │     running · watch live               │ │
│ │  >_ pwsh — agentmux        Tab 1      ›│ │
│ │  >_ ssh narko-build        Build      ›│ │
│ │     exited 0                           │ │
│ └────────────────────────────────────────┘ │
│ ┌────────────────────────────────────────┐ │
│ │ ⑂ dev-main-38b2af585f…  [LAN] [Paired] v │
│ └────────────────────────────────────────┘ │
│   +1 channel not shared on LAN             │
└────────────────────────────────────────────┘
```

**Swarm, Sysinfo and Tower are views of the instance, not panes.** They show
whether or not they are open on the desktop, and each has a one-line summary
on the right.

**A channel that isn't paired** lists its agents and Swarm (both from LAN
discovery), then one muted line: "Pair to see Sysinfo, Tower and terminals".
A refused pairing has no such line: its channel row already says "Pair
again".

**The demo** (`/demo`, which makes no network call) shows the agents only:
Swarm, Sysinfo and Tower read the computer live.

## 2. What exists, and what's missing

| Row | Data on the phone today | Missing |
|---|---|---|
| Agents | LAN discovery and the fleet feed: name, kind, state, summary (#63) | Nothing |
| Swarm | The same agent list | A Swarm screen on the phone |
| Sysinfo | Nothing. srv samples CPU and memory for the desktop (`backend/sysinfo.rs`, now run by the lease scheduler, #4833), but no viewer route serves it | A viewer route on the shared data layer (§3a); a Sysinfo screen |
| Tower | `GET /agentmux/viewer/procs`: tasks and the busiest and largest processes, names only. 403 unless the desktop's `tower:sharewithpaired` is on, which is off by default | A Tower screen; what the row says when sharing is off (§5) |
| Terminals | `GET /agentmux/viewer/panes`: every pane, window by window and tab by tab, with titles and state, and `terminals_shared` | Flattening into the channel's list; the panes screen goes |

## 3. Steps

Each step is one PR, tested and shippable on its own. Steps 1 and 2 are
phone-only; step 3 is desktop then phone.

### Step 1. One list per channel: agents, then terminals (agentmux-mobile)

- The channel section lists its agents (unchanged), then its terminals from
  `/agentmux/viewer/panes`, flattened in the order the route gives (window,
  tab, position), terminals only.
- A terminal row: `>_`, the title, the tab as a muted label on the right, and
  its state line ("running · watch live", "exited 0") as the panes screen
  shows it now. A tap opens the terminal screen (#62), unchanged.
- Terminals not shared (`terminals_shared: false`): one muted line, "Turn on
  Share terminals on the computer to watch them here", as the panes screen
  says it now.
- Remove the "All panes" row, `PanesScreen` and its route. Move anything
  still useful from it (the per-pane state words) into the row.
- When it loads: the panes list is fetched when the channel section is
  expanded and the device is paired, and again on pull-to-refresh and on
  return to the screen. A failed fetch shows the agents and one muted line,
  "Couldn't list terminals", with retry.
- Tests: order (window, tab, position) with tab labels not grouping; only
  terminals listed; not shared; not paired; fetch failure.

### Step 2. Swarm (agentmux-mobile)

- The row: `⬡ Swarm`, shown when the channel has at least one agent. Its
  summary is "3 agents · 2 working" (counts by state; "· 1 waiting" when one
  needs an answer).
- The screen: every agent of the channel on one screen, as the desktop's
  Swarm shows them: name, kind, state with how long, and the summary line,
  most active first (waiting, working, idle, stopped). A tap opens the
  agent's feed.
- Built from data the phone already has (the fleet feed and `viewer/agents`):
  no desktop change.
- Tests: the row's presence rule (0 agents → no row), the counts, the screen's
  order, the tap.

### Step 3a. A Sysinfo route on the shared data layer (agentmux)

**Builds on AgentX's Sysinfo rewrite**
(`docs/reports/REPORT_SYSINFO_REWRITE_AND_MODERN_MONITOR_2026_10_13.md`), not
beside it. That report moves Sysinfo, Tower and the pane headers onto one
data layer: one process snapshot, ring buffers with `since seq N` reads, and
a scheduler that runs a source only while a consumer holds a **lease** on it.
Its consumer table already lists "Remote frame / paired viewer: what that
view asks for, per request". The scheduler and the baseline lease for the
machine's counters are built (#4833); the shared snapshot, the
`sampler.want` / `sampler.release` leases and the `since seq N` read are not
yet (its phases 1–3).

- `GET /agentmux/viewer/sysinfo`: machine totals (CPU, per-core CPU, memory,
  commit on Windows) from the data layer's ring, with the sample's time. The
  totals are the always-on baseline, so this costs no extra sampling.
- `GET /agentmux/viewer/sysinfo/feed?since=<ts>`: the same as SSE, about
  once a second, with the feed's 15 s heartbeat; first the history after
  `since` (ms), then live samples. Once the shared scheduler exists, the
  stream holds a lease for as long as it is open.
- Viewer token only, read-only, as the other viewer routes. Nothing per
  process (that is Tower), no command lines.
- **Agreed with AgentX (2026-10-14):** none of the shared layer is built
  yet (no `since seq` read, no lease API; the scheduler is owned by the
  sysinfo loop), so v1 reads the broker's persisted ring directly,
  `Broker::read_event_history(EVENT_SYS_INFO, …)`, filtering `since` by `ts`
  in ms. Each SSE event is one `TimeSeriesData` (`rpc_types/misc.rs`:
  `{ts, values, uptime_secs}`, already exported) with the desktop's metric
  names (`cpu`, `cpu:N`, `mem:total/used/available/free`, `mem:commit:*`,
  `net:bytes*`, `disk:*`). No lease for now: `cpu:N` comes from the same
  baseline refresh as `cpu`. When the scheduler becomes a shared service the
  stream holds a lease while open, and a sequence number arrives as an
  optional `seq`, so `since=<ts>` keeps working. AgentX keeps
  `/agentmux/viewer/procs` byte-for-byte stable when Tower moves.
- Tests: auth (no token, bad token, the `lan_key` refused), the shape, the
  stream's first event, the lease taken while streaming and released after.

### Step 3b. Sysinfo (agentmux-mobile)

- The row: `▤ Sysinfo`, always shown, summary "CPU 23% · RAM 61%" from one
  `GET`, refreshed with the channel list.
- The screen: CPU and memory over the last few minutes, live from the feed
  route, as the desktop's Sysinfo draws them (a line for CPU, one for memory;
  per-core under a tap). Kept in memory only, like the feed.
- Against an older desktop without the route (404): the row stays, its
  summary says "Needs a newer AgentMux", and the screen says so.
- Tests: summary formatting, the 404 case, the chart's data window.

### Step 4. Tower (agentmux-mobile, and one desktop choice)

- The row: `♜ Tower`, always shown. Its summary is "142 processes" from
  `/agentmux/viewer/procs`. That route keeps its contract when the rewrite
  moves Tower onto the shared data layer (its phase 3); a phone request then
  becomes a short lease instead of a sample of its own.
- When the desktop doesn't share processes (403): the row stays, its summary
  says "Not shared", and the screen says how to turn it on ("Tower ›
  Share with paired devices" on the computer). **Open question §5.1:** keep
  sharing off by default, or turn it on for paired devices.
- The screen: the desktop's Tower, read-only: tasks first, then the busiest
  and largest processes, names only, with CPU and memory; refreshed every few
  seconds while open. A filter box, passed as `?filter=`.
- Tests: summary, the 403 case, refresh, filter.

## 4. Order of work

1. Step 1 (one list, terminals flattened, All panes removed): it reshapes the
   screen everything else goes into.
2. Step 2 (Swarm): phone-only.
3. Step 3a then 3b (Sysinfo): the one desktop route this needs.
4. Step 4 (Tower): phone-only, unless the default changes.

Each step is checked on the emulator paired with an isolated `task dev`, as
the feed work was.

## 5. Open questions

1. **Tower sharing:** off by default today, so most phones would show "Not
   shared". Keep it off (it lists process names), or turn it on for paired
   devices?
2. **Unpaired channels:** the agents and one "Pair to see…" line (this plan),
   or the agents alone?
3. **Refresh:** the channel list fetches panes, Sysinfo's summary and
   Tower's count when expanded and on refresh. Should they also refresh on a
   timer while the home screen is open (say every 15 s), or only then?

## 6. The other track: sending from the phone

`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` (paired, signed sending as the user;
Enter sends on either side; the message appears on both) is independent of
this plan and can go before, after or between its steps. Its own phases:
device keys and the send grant; sending as the user; a Stop button.
