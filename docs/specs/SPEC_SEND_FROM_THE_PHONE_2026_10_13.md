# Spec: sending to an agent from the phone

**Date:** 2026-10-13
**Status:** phases 1 and 2 built and checked end to end on Android,
2026-10-14: agentmux #4870, #4872, #4875; agentmux-mobile #79–#82. The iOS
key store (Secure Enclave, Swift) is written but not yet built or run: it
needs a Mac. Phase 3 (Stop) is not started. The operator took every
recommendation in §10. §5.2.1 is the contract between the two sides.
**Asked for:** "what about sending messages, can you spec that out?", then:
"we don't need the typing sync … whoever presses <enter> sends the message
and it appears on both device and desktop".
**Code read at:** agentmux `origin/main` 4435e2d, agentmux-mobile `main` 60fa0d5.
**Related:** `SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` (the viewer
channel, read-only: §4.1, §6.1, §10, §12), `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md`,
`REMOTE_TERMINALS_AND_CONVERSATION_HISTORY.md` §6, and in agentmux
`SPEC_SWARM_BROADCAST_AS_USER_MESSAGE_2026_10_01.md` (how srv, not text,
decides a message is the user's).

## 1. Short answer

The phone and the desktop pane each have their own composer. **Whoever
presses Enter sends**, and the message appears on both: in the desktop pane
as a prompt, and in the phone's feed. Nothing is shared while typing; a draft
on one side is never seen on the other.

When this spec was written the phone could already send, but not as you.
"Send a message…" posted to `/agentmux/reactive/inject` over plain HTTP with
the `lan_key` the desktop broadcasts to the whole network. The agent got a
jekt from an agent called `mobile`, `DELIVERY=lan`, `TRUST=network-claimed`:
by its own rules a message from an unproven agent, not the operator. Anyone
on the LAN could send the same thing. This spec replaced it with sending over
the paired, pinned-TLS viewer channel, as the user, for devices the owner
allows; the old path is gone (agentmux-mobile #82).

## 2. Where things were before (2026-10-13)

The baseline this spec started from; §5 and §6 say what replaced each row.

| | Before | Problem |
|---|---|---|
| Phone → agent | `LanAgentScreen` → `POST /agentmux/reactive/inject` `{target_agent, message, source_agent: "mobile"}`, header `X-AuthKey: <lan_key>`, plain HTTP (`local_api_client.dart:142-151`) | Not you to the agent (a jekt); the key is public on the LAN; the message travels unencrypted |
| Paired viewer channel | Pinned TLS, `amxv_` bearer token per device, revocable; GET + SSE only (`http_viewer.rs:62-78`) | Read-only by design: "never inject" (feed spec §4.1, tested §9) |
| Desktop prompt | Composer → `agentinput` RPC over `/ws` → a plain user turn (`TurnOrigin::User`) | `/ws` needs the full instance key, which a device must never get |
| Busy agent | Desktop holds a typed message until the next tool call or turn end (`heldQueue`, frontend only); srv-side input goes in at once, mid-turn | Two behaviours; the phone would get srv's |

## 3. Goals and non-goals

**Goals**
1. A composer at the bottom of the feed screen. Enter sends, to the agent,
   **as the user**: the same as typing in the desktop pane.
2. A message sent from either side appears on both, in order, once.
3. Only over the paired channel (pinned TLS, the device's own token), only for
   devices the owner allowed to send, revocable at once.

**Not in this spec:** showing what is being typed on the other side (asked
about, then dropped); answering questions and approving tools (their own
panels, their own spec); attachments and images; slash commands; sending to
terminals (remote code execution: `REMOTE_TERMINALS…` §6 keeps it out); the
cloud route (it needs the feed's end-to-end encryption first, feed spec §7).

## 4. Permission: a device may read, or read and send

- **Default: read only.** Pairing stays as it is. Sending is a second grant,
  per device, turned on **on the desktop only** (AgentMux › Paired devices ›
  the device › "Can send messages"). The phone can say how; it can't grant
  itself.
- **Per agent:** an agent hidden from paired devices can't be sent to.
  Container agents follow the same rule as host agents.
- **Proof of the device, not just its token.** Sending makes the phone the
  operator for that agent, so a copied bearer token must not be enough. Send
  requests are signed with the device key the feed spec plans (§10, "bound to
  a device key"; `pairing_service.dart:69`), held in the phone's keystore
  (Android Keystore / Secure Enclave): the request carries a timestamp and a
  signature over method, path, timestamp and body hash; srv checks it against
  the key registered at pairing and rejects stale (±60 s) or replayed
  (`message_id` seen) requests. A device paired before device keys existed
  must pair again to send. Decided (§10.2): signatures are required from the
  first version. The key and the signature format are in §5.2.
- **Revocation** (unpair, or turning "Can send" off) ends sending at once: the
  next request gets 403.
- **Rate limit:** 30 sends a minute per device.

`hello` gains `send` so the phone knows whether to offer the composer:
`"allowed"` (grant on and a key on file), `"off"` (no grant), or
`"pair_again"` (grant on, but the device paired without a key).

## 5. Sending

### 5.1 Enter sends, on either side

- **Desktop:** unchanged. Enter in the pane's composer sends; Shift+Enter is
  a new line.
- **Phone:** the keyboard's Enter key is **Send** (the IME shows a send key).
  A new line comes from a hardware keyboard's Shift+Enter, or from pasted
  text; the composer still grows to five lines for a long message. There is
  also a Send button, for when the keyboard is hidden.
- The two composers are independent. Text typed on one side is never seen on
  the other until it is sent; sending from one side leaves the other side's
  draft alone.

### 5.2 The route

`POST /agentmux/viewer/agents/:name/input` on the viewer listener:

```json
{ "message": "Run the tests again", "message_id": "<uuid v4>" }
```

- Auth: the device token, the send grant, the signature (§4).
- srv delivers it through the same path as a message typed in the pane
  (`agentinput` / `agent.send`, `TurnOrigin::User`), so the agent sees a
  plain user turn. **The text gets no header:** as with Swarm broadcasts,
  srv's route, not a label in the text, decides it's the user's (see
  `SPEC_SWARM_BROADCAST_AS_USER_MESSAGE` on why a text label would be a claim,
  not a proof). Markers inside the body (`[JEKT:`, `[BROADCAST:`,
  `[AgentMux]`) are neutralised as for any message.
- `message_id` makes it idempotent: a retry after a dropped connection is
  delivered once. The reply is `202 {message_id, state: "delivered" | "queued"}`.
- Errors: 403 (no send grant, revoked, hidden agent), 404 (unknown agent), 409
  (agent can't take input: stopped, still logging in), 413 (a message over
  10,000 bytes, or a body over 64 KB), 429. §5.2.1 has the exact list.

### 5.2.1 The contract, exactly

**The device key.** An ECDSA P-256 key pair made on the phone at pairing,
inside the platform's key store and never exportable (Android Keystore,
StrongBox when the phone has it; iOS Secure Enclave). P-256 because it is the
one curve both stores hold in hardware on every supported phone. One key per
paired computer; unpairing deletes it.

**Pairing** sends the public key in the existing optional field:
`POST /agentmux/viewer/pair {code, device_name, device_key}`, where
`device_key` is standard base64 of the 65-byte uncompressed SEC1 point
(`0x04 ‖ X ‖ Y`). On Android that is the last 65 bytes of
`PublicKey.getEncoded()`; on iOS, `SecKeyCopyExternalRepresentation`. srv
also still accepts the 32-byte shape it took before (an Ed25519 key), and
verifies either; the phone sends P-256.

**The request.**

```
POST /agentmux/viewer/agents/<name, percent-encoded>/input
Authorization: Bearer amxv_…
Content-Type: application/json
X-Amxv-Timestamp: 1791963024123
X-Amxv-Signature: <standard base64 of the DER (ASN.1) ECDSA signature>

{"message":"Run the tests again","message_id":"0b6f…-uuid-v4"}
```

The signature is over these five lines, UTF-8, joined by `\n`, no trailing
newline:

```
amxv-sig-v1
POST
/agentmux/viewer/agents/<name, percent-encoded>/input
1791963024123
<lowercase hex SHA-256 of the exact body bytes sent>
```

- Line 3 is the request path exactly as sent, without query string.
- Line 4 is `X-Amxv-Timestamp`, milliseconds since the epoch; srv refuses it
  more than 60 s from its own clock.
- Sign with SHA256withECDSA (Android) / `.ecdsaSignatureMessageX962SHA256`
  (iOS); both produce DER, which is what srv verifies.

**The body.** `message`: 1 to 10,000 bytes of UTF-8 after trimming trailing
whitespace (the same cap as any message an agent is sent). `message_id`: a
UUID v4 the phone makes when the user presses Enter and reuses for every
retry of that message. The whole request body is at most 64 KB.

**Replies.**

| Status | Body | Meaning for the phone |
|---|---|---|
| 202 | `{message_id, state: "delivered" \| "queued"}` | Sent. "queued": the agent is busy and reads it at its next step |
| 202 | same, plus `"duplicate": true` | A retry of a message already taken; nothing sent twice |
| 400 | `{error}` | Bad body; don't retry |
| 401 | `{error}` | Token unknown: unpaired. Mark the pairing invalid |
| 403 | `{error, reason}` | `reason`: `send_off` (grant off), `pair_again` (no key on file), `bad_signature`, `stale_timestamp` (fix the clock or retry once) |
| 404 | `{error}` | No such agent in this channel, or one hidden from paired devices (not even named, as in the list and the feed) |
| 409 | `{error, reason}` | `reason`: `not_running` (nothing runs it: open it on the computer), `starting`, `needs_login`, `in_flight` (this `message_id` is being sent right now: retry in a moment), `not_supported` (the agent runs in a terminal pane), `failed` (`error` says why). Keep the text, let the user retry |
| 413 | `{error}` | Message over 10,000 bytes, or body over 64 KB |
| 429 | `{error}`, `Retry-After` | Over 30 a minute |

srv remembers each device's `message_id`s for 10 minutes, so a retry within
that window is answered from memory. The phone's "Try again" (§5.5) reuses
the `message_id`, so a send whose reply was lost is never delivered twice.

### 5.3 It appears on both

There is one record of what was sent: the agent's transcript. Both sides
show the message from there, so they can't disagree.

- **Sent from the phone, on the desktop:** the prompt block, as if typed,
  with a muted **"From <device>" note** above it (a phone icon, then "From
  Pixel 9"; this spec calls it the From note), the treatment the
  broadcast note has. It comes from the stored record, never from the text,
  so it can't be forged. srv stores the user record of a phone's message
  with one extra top-level field the agent's stdin never gets:
  `{"type":"user","message":{"role":"user","content":"…"},"amx":{"via":"viewer","device":"Pixel 9","message_id":"<the phone's id>"}}`.
  The phone's feed carries the same line, so the phone matches its
  "Sending…" line to it by `amx.message_id`.
- **Sent from the phone, on the phone:** the same frame arrives on the feed.
  Until it does, the message shows under the composer, muted ("Sending…");
  when the frame with its `message_id` arrives it takes its place in the
  feed. This usually takes well under a second on a LAN.
- **Sent from the desktop, on the phone:** it already appears in the feed,
  as a prompt block, as any desktop prompt does today.
- **Order:** both sides show messages in transcript order, which is the order
  srv received them, whichever side sent first.

### 5.4 When the agent is busy

The desktop pane holds a typed message until the next tool call or the end
of the turn; srv-side input goes in at once and the CLI reads it at its next
step. v1 gives the phone srv's behaviour, said in the composer ("The agent
is working: it reads this at its next step"). Matching the desktop's hold
needs the hold moved from the frontend into srv, a change for both sides,
left for later (decided, §10.4).

### 5.5 The phone's composer

- At the bottom of the feed screen, under the working row, replacing the
  "Send a message…" menu item for devices that can send.
- No send grant: no composer; the menu says "Sending is off for this device:
  turn it on in AgentMux › Paired devices".
- Disconnected or reconnecting: Send is disabled; the text stays. A failed
  send keeps the text and shows "Didn't send: <reason>. Try again"; nothing
  is re-sent on its own.
- The phone's unsent text is kept per agent while the app runs, like the
  desktop's drafts, and dropped when the app closes.

## 6. Security

| Threat | Answer |
|---|---|
| Someone on the LAN sends as the operator | Sending needs the paired device's token, its send grant and its device-key signature; the `lan_key` grants none of it |
| A copied token | Not enough to send: requests are signed by a key that never leaves the phone's keystore |
| A replayed request | Timestamp window and `message_id` checks |
| A phone message forging a marker or label | Markers neutralised; the From note comes from the stored record's `amx`, which only srv writes, not from the text |
| A lost or stolen phone | Unpair on the desktop: sending stops at once; the phone lock and keystore protect the key meanwhile |
| An agent hidden from devices | Not sendable, not listed |

**The old `lan_key` send.** With paired sending, the phone no longer uses
`/agentmux/reactive/inject` at all: `LanAgentScreen` and its route go
(decided, §10.3). An unpaired computer's agents are listed but can't be sent
to; the feed's place says "Pair to watch and send".

## 7. What changes where

**agentmux (srv and frontend)**
- Device record: a `can_send` grant and the device's public key; the Paired
  devices UI to change it.
- The viewer route `POST …/input`, signature checks, `send` in `hello`,
  and tests that it refuses a read-only device and the `lan_key`, and that a
  read-only token still opens nothing else.
- Delivery through the user-turn path, with `amx` on the stored user
  record; the pane's From note.

**agentmux-mobile**
- Device key generation at pairing (keystore), request signing.
- The composer: Enter sends, the Send button, "Sending…", retry, per-agent
  unsent text.
- Matching a sent message to its frame by `message_id`; the From note in
  the feed for messages sent from any phone.

## 8. Phases

1. **Device keys and the send grant** (both repos): pairing registers a key;
   the desktop's Paired devices list can allow sending. No new behaviour yet.
2. **Send as the user** (both): the route, the composer, the From note.
   The `lan_key` path stops being used for paired computers.
3. **Stop**: a Stop button on the phone while the agent works, through the
   same grant (`agent.stop`).

## 9. Testing

- srv: the route's auth matrix (no token, read-only device, revoked, bad
  signature, stale timestamp, replayed `message_id`, `lan_key`, hidden
  agent); a phone message lands as a plain user turn with `via: viewer`;
  markers in it are neutralised.
- frontend: the From note renders from the record's `amx` only.
- mobile: Enter sends and clears; composer states (no grant, disconnected,
  sending, failed); a retry reuses its `message_id`; the "Sending…" line is
  replaced by the feed's frame.
- End to end: the emulator paired with a `task dev`: send from the phone and
  see it on both; send from the desktop and see it on both; send from both
  close together and see the same order on both.

## 10. Decisions

The operator took each recommendation on 2026-10-14: (1) the agent gets a
plain user turn; (2) signatures from the first version; (3) the `lan_key`
send screen goes; (4) delivered at once while the agent is busy; (5) Enter
sends on the phone. The questions as they were asked:

1. **Should the agent know a message came from the phone?** This spec: no,
   it's the user's (a plain user turn), and only the people looking at the
   pane see the From note. The alternative is a srv-written line the agent sees.
2. **Device-key signatures required to send** (this spec), or the token
   alone for a first version?
3. **The `lan_key` send screen** for unpaired computers: remove it, or keep
   it with a plain warning?
4. **A busy agent:** deliver at once, as srv does (v1), or hold until the
   next tool call, as the desktop pane does (needs the hold moved into srv)?
5. **New lines on the phone:** Enter sends, so a soft keyboard can't type a
   new line. Is that fine, or should the phone's Enter add a line and only
   the Send button send?
