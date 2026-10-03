/// One dispatched Server-Sent Event.
class SseEvent {
  const SseEvent({required this.event, required this.data, this.id});

  /// The `event:` field, `message` when the server sent none.
  final String event;
  final String data;

  /// The last `id:` seen on or before this event, if any.
  final String? id;
}

/// Incremental `text/event-stream` parser, following the WHATWG rules this
/// app needs: `event`, `data` (multi-line), `id`, `retry`, comments, and all
/// three line endings, including a `\r\n` split across two chunks.
///
/// Comments (`: hb`) dispatch nothing; the caller treats any received bytes as
/// proof the connection is alive, so heartbeats need no event of their own.
class SseParser {
  /// A line longer than this without a terminator is not a sane event stream;
  /// refusing it bounds memory against a misbehaving or hostile peer.
  static const maxLineLength = 1 << 20;

  final _buffer = StringBuffer();
  String _event = '';
  final _data = <String>[];
  String? _lastEventId;

  /// The most recent `retry:` value, in milliseconds.
  int? retryMs;

  String? get lastEventId => _lastEventId;

  /// Feeds one decoded chunk and returns the events it completed.
  List<SseEvent> add(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final events = <SseEvent>[];
    var start = 0;
    var i = 0;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        // A lone `\r` at the very end may be the first half of `\r\n`; wait
        // for the next chunk before deciding.
        if (c == 0x0D && i == text.length - 1) break;
        _line(text.substring(start, i), events);
        i += (c == 0x0D && text.codeUnitAt(i + 1) == 0x0A) ? 2 : 1;
        start = i;
      } else {
        i++;
      }
    }
    final rest = text.substring(start);
    if (rest.length > maxLineLength) {
      throw const FormatException('event-stream line exceeds the size limit');
    }
    _buffer
      ..clear()
      ..write(rest);
    return events;
  }

  void _line(String line, List<SseEvent> events) {
    if (line.isEmpty) {
      if (_data.isNotEmpty) {
        events.add(SseEvent(
          event: _event.isEmpty ? 'message' : _event,
          data: _data.join('\n'),
          id: _lastEventId,
        ));
      }
      _event = '';
      _data.clear();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _event = value;
      case 'data':
        _data.add(value);
      case 'id':
        if (!value.contains('\u0000')) _lastEventId = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null && ms >= 0) retryMs = ms;
    }
  }
}
