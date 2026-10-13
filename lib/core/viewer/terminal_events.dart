import 'dart:convert';
import 'dart:typed_data';

import '../fleet/sse.dart';

/// One event of `GET /agentmux/viewer/terminals/:block_id/feed`: a terminal's
/// output, raw PTY bytes (ANSI escapes and all), placed by byte offset.
sealed class TerminalEvent {
  const TerminalEvent();
}

/// The tail of the terminal's output, from a line start.
class TerminalSnapshot extends TerminalEvent {
  const TerminalSnapshot({
    required this.offset,
    required this.nextOffset,
    required this.data,
    this.rows,
    this.cols,
  });

  /// Where [data] starts in the output.
  final int offset;

  /// Where the output ends: the next append starts here.
  final int nextOffset;
  final Uint8List data;

  /// The size the desktop gave the PTY, when known.
  final int? rows;
  final int? cols;
}

/// Bytes written to the terminal at [offset].
class TerminalAppend extends TerminalEvent {
  const TerminalAppend({required this.offset, required this.data});
  final int offset;
  final Uint8List data;
}

/// The desktop resized the PTY.
class TerminalResize extends TerminalEvent {
  const TerminalResize({required this.rows, required this.cols});
  final int rows;
  final int cols;
}

/// The output was cleared, or the feed lost its place: a fresh
/// [TerminalSnapshot] follows, or the stream ends (`behind`, `hidden`,
/// `not_shared`, `gone`).
class TerminalReset extends TerminalEvent {
  const TerminalReset(this.reason);
  final String reason;
}

/// A terminal size this app will lay out; anything else is not a size.
int? _dimension(Object? v) => v is int && v > 0 && v <= 1000 ? v : null;

int? _offset(Object? v) => v is int && v >= 0 ? v : null;

/// Bounds on one event's payload: a snapshot is at most 256 KB on the
/// desktop; a peer that sends far more is misbehaving.
const _maxDataBytes = 1 << 20;

Uint8List? _data(Object? v) {
  if (v is! String) return null;
  try {
    final bytes = base64Decode(v);
    return bytes.length <= _maxDataBytes ? bytes : null;
  } on FormatException {
    return null;
  }
}

/// Parses one SSE event of the terminal feed; null for an event this app
/// does not know or a body that is not well formed (skipped, not fatal).
TerminalEvent? parseTerminalEvent(SseEvent e) {
  final Object? json;
  try {
    json = jsonDecode(e.data);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  switch (e.event) {
    case 'snapshot':
      final offset = _offset(json['offset']);
      final next = _offset(json['next_offset']);
      final data = _data(json['data64']);
      if (offset == null || next == null || data == null) return null;
      if (next != offset + data.length) return null;
      return TerminalSnapshot(
        offset: offset,
        nextOffset: next,
        data: data,
        rows: _dimension(json['rows']),
        cols: _dimension(json['cols']),
      );
    case 'append':
      final offset = _offset(json['offset']);
      final data = _data(json['data64']);
      if (offset == null || data == null) return null;
      return TerminalAppend(offset: offset, data: data);
    case 'size':
      final rows = _dimension(json['rows']);
      final cols = _dimension(json['cols']);
      if (rows == null || cols == null) return null;
      return TerminalResize(rows: rows, cols: cols);
    case 'reset':
      final reason = json['reason'];
      return TerminalReset(reason is String && reason.length <= 64 ? reason : '');
  }
  return null;
}
