# Spec: the live feed renders like the desktop agent pane

**Date:** 2026-10-13
**Status:** being implemented, one phase per PR (§10). Phase 1 is done.
The open questions (§11) were answered with this spec's defaults when the
operator asked for the full look.
**Asked for:** "it should appear like normal AgentMux: no text bubbles, code
formatting where appropriate, system reminders, tool calls, and the
expand/collapse of the tool previews."
**Code read at:** agentmux `84e05ef4b`, agentmux-mobile `main` after #64.
**Related:** `SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` (the feed
and its wire, §6.2 the screen), `docs/reports/REPORT_PANE_LIST_TERMINALS_AND_FROZEN_FEED_2026_10_12.md`.

## 1. Goal and scope

The feed screen (`lib/features/feed/`) shows the same frames the desktop
agent pane gets: Claude Code's stream-json lines, as srv stores them. Today
it draws them as a chat: prompts in right-aligned bubbles, the reply as
plain text, tool calls as bare lines. The goal is that someone who knows the
desktop pane reads the phone without relearning it: the same blocks, in the
same order, styled the same way, at phone width.

**In scope:** how each frame is drawn: prompts, Markdown and code, thinking,
tool calls and their previews, the messages AgentMux and other agents put in
the transcript, system reminders, turn ends and errors, and the live status.

**Not in scope:** sending input or answering questions from the phone (the
feed stays read-only); the desktop's panels that sit *outside* the transcript
(the question and approval panels, the activity dock); history before the
snapshot ("Load earlier" in the feed spec §6.2).

**Desktop reference.** Every desktop behaviour below comes from the agentmux
frontend (`frontend/app/view/agent/**`, `frontend/app/element/markdown*`).
File references are to that repo unless they start with `lib/`.

## 2. Where the phone is today

| Element | Desktop | Phone today |
|---|---|---|
| Prompt | Full-width block, theme colours inverted, 3 px orange bar on the left (`styles/_document-nodes.scss`, `.user-message`) | Right-aligned bubble, 18 % blue tint |
| Assistant text | GitHub-flavoured Markdown (`element/markdown.tsx`) | Plain selectable text, Markdown source shown as is |
| Code | Highlighted fences with a Copy button; tinted inline code | Plain text |
| Thinking | The full text, italic, 60 % opacity, a bar on the left, no label | One "Thinking…" line; the text is thrown away |
| Tool call | Status glyph, icon, label, detail, duration, result pill | Icon, name, one summary |
| Tool preview | Opens by itself while running; per-tool previews (Bash output, Edit diff, highlighted Read/Write) | Closed unless tapped; raw result text |
| Another agent's message (jekt) | Collapsible line with sender, tier and delivery badges | The raw `[JEKT:…]` text in a bubble |
| Broadcast | Header removed, "📣 Broadcast · N agents" | The raw header in a bubble |
| System reminders | No general handling (see §7) | Raw in prompts; dropped elsewhere |
| Turn end | "✓ Worked · 42s · 2.4k tokens", latest turn only | "Turn ended · 4.2s" on every turn |
| Errors, interrupts, compaction, rate limits | Their own rows and dividers | Not shown |

Nothing on the wire needs to change: the phone already receives every frame
the desktop pane renders from. This is rendering work in the app, plus a
Markdown and a syntax-highlighting package.

## 3. Look and layout

- **No bubbles.** Every block is full width, in one column, 4 px apart, as on
  the desktop (`styles/_document.scss`).
- **Prompts** use the desktop's user-input block: background the main text
  colour, text the block background colour (an inverted block), a 3 px bar
  on the left in the user-input colour (#e07832 in the default theme), 3–4 px
  padding, no radius, text wrapped, links tappable. No timestamp (the
  desktop shows one on hover only).
- **Theme.** Adopt the desktop's default dark tokens in
  `lib/shared/theme/app_theme.dart` for the feed (they differ today): main
  text #f7f7f7, secondary rgb(195,200,194), accent rgb(65,159,224), user
  input #e07832, success text #10b981, warning text #d97706, error text
  #ff8080, info rgb(155,108,224), borders 16 % white, panel background
  rgba(31,33,31,.5). Spacing steps 2/4/6/8/12/16/20.
- **Fonts.** Prose in the system sans at 14; code, tool lines and previews
  in a monospace font at 12–13 (the desktop uses Hack; bundle a monospace
  font, or use the platform's, as an open question §11).

## 4. Assistant text: Markdown and code

- **Package:** `flutter_markdown_plus` (the maintained successor of the
  discontinued `flutter_markdown`; verified publisher, full pub score), on
  Dart's own `markdown` parser with the GitHub-flavoured extension set.
  Rejected: `markdown_widget` (unmaintained since 2025-04), `gpt_markdown`
  (aimed at LLM chat output, adds its own LaTeX handling).
- **What renders** (matching `element/markdown.tsx`): paragraphs, headings
  (h1 2em and h2 1.5em with a rule under them, down to h6), lists, links (the
  desktop's link blue), blockquotes on the panel background, tables (zebra
  rows, small uppercase header), horizontal rules, strikethrough, task lists.
- **Code fences:** a block on the panel background, monospace, wrapped, with
  a **Copy** button (always visible on a phone, no hover). Highlighted (§4.1).
  The desktop shows no language label; neither does the phone.
- **Inline code:** monospace, 8 % text-colour tint, 1×4 px padding.
- **AgentMux's rich output** (the classes the desktop allows): `am-ok`,
  `am-warn`, `am-error`, `am-info`, `am-muted`, `am-added` (green, 14 %
  green tint), `am-removed` (red, 14 % red tint, struck through), `am-badge`
  (a pill). Parsed from `<span class="…">` with an inline syntax; any other
  HTML is shown as text, never rendered.
- **GitHub callouts** `> [!NOTE|TIP|IMPORTANT|WARNING|CAUTION]`: a titled box
  with a coloured bar on the left and an 8 % tint (info, success, accent,
  warning, error).
- **Images and video** in the reply: a local path names a file on the
  computer, which the phone can't read; show a card "Image on the computer:
  <file name>". A remote image is not loaded until tapped, as on the desktop.
- **Mermaid** fences: shown as code (rendering diagrams is out of scope).
- **Streaming:** text grows from `stream_event` deltas (today's
  `StreamingTextItem`), re-rendered at most every 90 ms, as the desktop
  throttles it. Closed blocks are parsed once and kept; only the open tail is
  parsed again. The tail is not highlighted until its fence closes. No cursor.

### 4.1 Syntax highlighting

- **Package:** `re_highlight` (verified publisher reqable.com, MIT, pure
  Dart), a port of highlight.js 11.9. The desktop's Markdown uses
  highlight.js with the `github-dark-dimmed` theme
  (`element/markdown.scss`), so the phone uses the same grammars and theme.
  Rejected: `syntax_highlight` (Serverpod) ships only five grammars (Dart,
  JSON, YAML, SQL and its own), and 0.5.0 depends on `super_clipboard`, a
  native plugin that downloads prebuilt binaries at build time;
  `highlight` and `flutter_highlight` (last released 2021).
- **Languages bundled:** the common ones (bash/shell, PowerShell, JSON, YAML,
  TOML, Markdown, Rust, TypeScript/JavaScript, Python, Go, Dart, Kotlin,
  Swift, C/C++, C#, Java, HTML/XML, CSS, SQL, diff), imported one by one so
  the app doesn't carry every grammar. Others stay plain.
- **Off the UI thread:** blocks up to 4 KB are highlighted at once; larger
  ones in an isolate, shown plain until done. Results are cached.
- **Caps:** highlight up to 200 KB of text per block, like the desktop;
  larger is shown plain.

## 5. Thinking

Shown as the desktop shows it: the full text, rendered as Markdown, italic,
60 % opacity, secondary colour, a 2 px bar on the left. While a thinking
block streams it grows like reply text. This needs the thinking text kept:
today `ThinkingItem` is a placeholder and the `thinking` content of the
`assistant` frame is skipped (`lib/features/feed/transcript.dart`).
Open question §11: a setting to hide thinking.

## 6. Tool calls

### 6.1 The header line

One line per call, as `components/ToolBlock.tsx` draws it:
**status glyph · icon · label · detail · duration · pill**.

- **Status:** ⏳ running, ✓ done, ✗ failed, ⊘ denied, ⏹ cancelled, ❓
  waiting for an answer.
- **A 2 px bar on the left:** warning colour while running, success when
  done, error when failed.
- **Per tool** (the desktop's `tool-meta/tool-descriptors.ts`):

| Tool | Icon | Detail | Pill |
|---|---|---|---|
| Bash | 🔧 | the command, shell-coloured, cut from the left | exit N |
| Read | 📖 | path, cut from the left; range "120:179 of 456" | |
| Write | 📝 | path | size |
| Edit | ✏️ | path | N lines |
| Grep | 🔍 | pattern · in dir · glob · type · flags | N matches / N files |
| Glob | 📁 | pattern | N files |
| Agent | 🤖 | description | |
| WebSearch | 🌐 | query | N sources |
| WebFetch | 🌐 | host/path | |
| `mcp__server__tool` | 🛠️ | label "server · tool" | |
| anything else | 🛠️ | the tool's name | |

- **Duration** "(1.2s)" when known. On a narrow screen the pill drops before
  the detail does (the desktop shows pills from 600 px wide).
- **Tool name colours**, as the desktop: shell green, read accent,
  write/edit warning, search cyan, agent magenta.

### 6.2 Expand and collapse

The desktop's rules (`virtualization/disclosure.ts`), unchanged:

- A call that is **running** has its preview open.
- A call that **finishes while on screen** stays open until it scrolls off
  the top, then closes.
- Everything else is **closed**: calls in the snapshot, and calls that
  finished off screen.
- **Tapping the header pins it open**, or closes it. A pin survives new
  output; it is dropped with the transcript on a fresh snapshot.
- **The preview is about 13 lines tall** and scrolls inside. A "taller"
  toggle triples it.

### 6.3 The previews

| Tool | Preview |
|---|---|
| Bash | stdout, then stderr in the error colour, the last 1000 lines, then "Exit code: N". "No output" when empty. |
| Edit | a diff of `old_string` → `new_string` from the call's input: a file line, then per-line + / − with markers in their own column, added lines on a 15 % green background, removed on 15 % red. Highlighted by the file's language. |
| Write | path and size, then the content, highlighted by extension; a `.md` file rendered as Markdown. |
| Read | path and range, then the content with a line-number gutter, highlighted; a `.md` file rendered as Markdown; Claude Code's trailing reminders removed (§7). |
| Grep / Glob | the matches; Glob as a list of paths. |
| Agent | the subagent's final report, as Markdown. |
| WebSearch | its sources, open by default when done (the desktop treats it as content). |
| anything else, MCP | one line as text; several lines in a monospace box; JSON as a one-line summary that expands. |
| running, no output yet | "⏳ Thinking…" |

- **Caps:** previews keep 1000 lines or 1 MB (logs keep the end, files and
  diffs the start) with "… N earlier lines hidden". A result the desktop cut
  in the feed (`amx_truncated`, over 64 KB a frame) keeps today's "Output
  truncated (open on the computer)".
- **Long lines** wrap in prose and scroll sideways in code and diffs.
- **A frame over 64 KB that carries a tool call's input** (a large Write or
  Edit) arrives as `amx_truncated` too, so the call's header has to be built
  from the head the desktop keeps (its `tool_use` id and name come first);
  the preview then says it was too large.

### 6.4 Subagents

Today the phone drops every frame with a `parent_tool_use_id`. The desktop
shows no nesting either (its transcript doesn't group a subagent's steps;
only its status line and activity dock follow them). The phone instead nests
a subagent's tool calls under its Agent call, collapsed, with a count
("12 steps"), opened by a tap. This is the one place the phone goes beyond
the desktop; see §11.

## 7. System reminders, and messages that aren't the user's

**System reminders.** Claude Code adds `<system-reminder>…</system-reminder>`
blocks to user turns and tool results. The desktop has no general rule for
them: a memory reinjection becomes a line "🧠 Memory reinjected — N global,
M personal", reminders are stripped from Read results, text-only reminder
blocks are dropped, and any other reminder shows as raw text. The phone:

- shows each reminder as **one collapsed line** "System reminder", muted,
  that opens to its text in a monospace box;
- shows a memory reinjection as the desktop's 🧠 line;
- strips reminders from Read previews, as the desktop does;
- never shows a reminder inside a prompt block: it is split out and shown
  after it.

Open question §11: whether the desktop should adopt the same collapsed line.

**Other agents' messages (jekts).** A user turn that is a whole
`[JEKT:…]…[/JEKT]` block becomes the desktop's collapsible line:
"▸ 📥 From <agent> [tier] [delivery]". Opened: the message body as prose, a
line with To, MSGID, Trust, Priority and time, and the raw payload behind a
further tap. A 2 px accent bar on the left; red for `TIER=sensitive`, which
starts open. The phone reads the same marker the desktop parses
(`stream-parser.ts`), and shows it; it never acts on it.

**Swarm broadcasts.** The `[BROADCAST:…]` header line is removed; a muted
"📣 Broadcast · N agents" note sits above the prompt block.

**The startup context** (a user turn starting `# Session Context`): one
collapsed line "Session context" that opens to its text.

**AgentMux's own notes:** `cli_notice` and session outcome as a centered
divider with a pill label; context delivery as a card; the interrupted marker
"⏹ Interrupted by user".

**Attachments** (`<attached_files>` / `<attached_images>` in a prompt):
split off and shown as a line of file names above the prompt (the images are
on the computer).

**Questions** (AskUserQuestion): while waiting, the tool row reads "❓ Waiting
for an answer on the computer". Once answered, the question as Markdown and
the answer in a prompt block, as the desktop does.

## 8. Turn ends, errors and the live status

- **No divider per turn.** The latest turn's summary sits at the bottom of
  the transcript, as the desktop's working row: "✓ Worked · 42s · 2.4k
  tokens" (output tokens), and under it "$0.41 · 9 steps" when the `result`
  frame has them. Earlier turns get nothing, as on the desktop.
- **Errors:** a red block "Error" (or "HTTP 401") and the message, with a
  2 px red bar and a red tint, in the transcript where the turn failed.
- **Compaction:** "Compacting conversation…" while it runs, then a centered
  divider "Context compacted", with the summary as a collapsed card.
- **The live status line**, at the bottom while the agent works: an ASCII
  spinner and what it is doing ("Thinking", "Writing the reply", the running
  tool's label, "Rate limited — retrying"), and "↓ 2.4k tokens · 1m 5s".
  Built from the same frames the desktop's `present-status.ts` uses: token
  counts from `message_start` / `message_delta`, the running tool from the
  open tool call, rate limits from `rate_limit_event`.

## 9. Other providers

The desktop translates Codex, Gemini, Kimi and ACP frames into the same
event types and draws them with the same components
(`providers/translator-factory.ts`). The phone shows their frames as plain
text today. This spec covers Claude-shaped frames (Claude Code and Qwen
Code); the other providers follow by porting their translators, one per PR,
after phase 3.

## 10. Phases

Each phase is one PR, tested and shippable on its own.

1. **Look, Markdown and code.** No bubbles, the prompt block, the desktop
   palette and fonts, Markdown, highlighted code fences with Copy, inline
   code, AgentMux spans and callouts, thinking text kept and shown.
2. **Tool calls.** The header line per tool, the expand/collapse rules, and
   the previews (Bash, Edit diff, Read/Write highlighted, Grep/Glob, Agent,
   catch-all), with their caps.
3. **What isn't the user's.** System reminders, jekts, broadcasts, the
   startup context, attachments, AgentMux notes, questions, errors,
   interrupts and compaction.
4. **The working row.** The latest turn's summary and the live status line.
5. **Subagent nesting** (if wanted, §11), then other providers (§9).

## 11. Open questions

Asked to "implement the full look", the implementation takes this spec's
default for each; any can be revisited.

1. **System reminders:** shown collapsed (this spec's default), not hidden
   as the desktop mostly does. Whether the desktop should adopt the
   collapsed line is still open.
2. **Subagents:** nested under their Agent call (default), not flat.
3. **Thinking:** shown in full, like the desktop (default).
4. **Font:** the platform's monospace font, not a bundled Hack.
5. **Light theme:** the phone follows only the desktop's default dark theme
   for now.

## 12. Testing

- **Fixtures from real transcripts:** a short Claude Code session (prompt,
  thinking, text with code and a table, Bash, Read, Edit, Write, Grep, a
  failed call, an MCP call, a subagent, a jekt, a broadcast, a system
  reminder, a compaction, an error), sanitised and committed beside
  `test/features/feed/claude_fixtures.dart`.
- **Widget tests** per element: the prompt block has no bubble; Markdown
  elements; a fence highlights and Copy copies; a running tool is open and a
  finished one closes when scrolled away; pinning; the diff marks lines; a
  reminder is collapsed; a jekt line shows sender and tier.
- **No golden images:** CI runs on Linux and agents build on Windows and
  macOS, whose font rendering differs, so goldens would fail on whichever
  machine didn't make them. The widget tests check the look's structure
  (colours, bars, no radius, full width) instead.
- **Performance:** a 3000-item transcript (the cap) scrolls without jank;
  Markdown is parsed once per closed block; highlighting runs off the UI
  thread.
- **Against a real desktop:** the emulator paired with a `task dev`, watching
  an agent work (`CLAUDE.md`, "Pairing from the emulator").
