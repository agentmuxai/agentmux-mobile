import 'dart:convert';

import '../fleet/sse.dart';

/// One event of `GET /agentmux/viewer/agents/:name/feed`
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 13.3). Lines are the
/// provider's own transcript frames, one JSON document each, unparsed here.
sealed class FeedEvent {
  const FeedEvent();
}

/// The tail of the transcript: the last 50 turns or 256 KB.
class FeedSnapshot extends FeedEvent {
  const FeedSnapshot({
    required this.provider,
    required this.gen,
    required this.fromLine,
    required this.nextLine,
    required this.lines,
    this.id,
  });

  /// The agent's provider id (`claude`, `codex`, `gemini`, `qwen`, ...).
  final String provider;

  /// The transcript's generation; a new one means it was rewritten.
  final String gen;
  final int fromLine;
  final int nextLine;
  final List<String> lines;

  /// The SSE id, `<gen>:<next line>`, to resume after.
  final String? id;
}

/// Lines appended to the transcript, starting at [line].
class FeedAppend extends FeedEvent {
  const FeedAppend({
    required this.gen,
    required this.line,
    required this.lines,
    this.id,
  });
  final String gen;
  final int line;
  final List<String> lines;
  final String? id;
}

/// The transcript was replaced, deleted or its generation changed; a fresh
/// [FeedSnapshot] follows (or the stream closes, and a reconnect gets one).
class FeedReset extends FeedEvent {
  const FeedReset(this.reason);
  final String reason;
}

/// The agent's working / idle state, for the feed header's status chip.
class FeedStatus extends FeedEvent {
  const FeedStatus({required this.state, this.sinceMs, this.nowMs});

  /// `working`, `waiting`, `idle`, `stopped` or `error`.
  final String state;
  final int? sinceMs;

  /// The desktop's clock when it sent this, so "for 3m" never compares the
  /// device's clock with the desktop's.
  final int? nowMs;
}

/// Bounds on what one event may carry; the peer is authenticated but a bug
/// on it must not exhaust this device's memory.
const maxFeedLinesPerEvent = 20000;
const _maxShortField = 128;

/// Parses one SSE event of the feed; null for an event this app does not
/// know or a body that is not well formed (skipped, not fatal).
FeedEvent? parseFeedEvent(SseEvent e) {
  final Object? json;
  try {
    json = jsonDecode(e.data);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  switch (e.event) {
    case 'snapshot':
      final gen = _gen(json['gen']);
      final from = json['from_line'];
      final next = json['next_line'];
      final lines = _lines(json['lines']);
      if (gen == null || from is! int || next is! int || lines == null) {
        return null;
      }
      return FeedSnapshot(
        provider: _short(json['provider']) ?? '',
        gen: gen,
        fromLine: from,
        nextLine: next,
        lines: lines,
        id: e.id,
      );
    case 'append':
      final gen = _gen(json['gen']);
      final line = json['line'];
      final lines = _lines(json['lines']);
      if (gen == null || line is! int || lines == null) return null;
      return FeedAppend(gen: gen, line: line, lines: lines, id: e.id);
    case 'reset':
      return FeedReset(_short(json['reason']) ?? '');
    case 'status':
      final state = _short(json['state']);
      if (state == null) return null;
      final since = json['since_ms'];
      final now = json['now_ms'];
      return FeedStatus(
        state: state,
        sinceMs: since is int ? since : null,
        nowMs: now is int ? now : null,
      );
  }
  return null;
}

/// A generation, sent as a number or a string.
String? _gen(Object? v) {
  if (v is int) return '$v';
  if (v is String && v.isNotEmpty && v.length <= _maxShortField) return v;
  return null;
}

String? _short(Object? v) =>
    v is String && v.length <= _maxShortField ? v : null;

List<String>? _lines(Object? v) {
  if (v is! List || v.length > maxFeedLinesPerEvent) return null;
  // A non-string entry still counts as a line, so line numbers stay right.
  return [for (final l in v) l is String ? l : ''];
}
