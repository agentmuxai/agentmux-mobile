import 'dart:convert';

import 'package:agentmux_mobile/core/fleet/sse.dart';
import 'package:agentmux_mobile/core/viewer/terminal_events.dart';
import 'package:flutter_test/flutter_test.dart';

TerminalEvent? _parse(String event, Map<String, Object?> data) =>
    parseTerminalEvent(SseEvent(event: event, data: jsonEncode(data)));

String _b64(String s) => base64Encode(utf8.encode(s));

void main() {
  test('a snapshot carries its bytes, where they sit, and the PTY size', () {
    final e = _parse('snapshot', {
      'offset': 10,
      'next_offset': 15,
      'data64': _b64('hello'),
      'rows': 30,
      'cols': 100,
    });
    expect(e, isA<TerminalSnapshot>());
    final s = e as TerminalSnapshot;
    expect((s.offset, s.nextOffset, utf8.decode(s.data)), (10, 15, 'hello'));
    expect((s.rows, s.cols), (30, 100));
  });

  test('a snapshot whose offsets disagree with its bytes is skipped', () {
    expect(
      _parse('snapshot', {'offset': 0, 'next_offset': 9, 'data64': _b64('hello')}),
      isNull,
    );
  });

  test('an unusable size is left out, not trusted', () {
    final s = _parse('snapshot', {
      'offset': 0,
      'next_offset': 0,
      'data64': '',
      'rows': 0,
      'cols': 99999,
    }) as TerminalSnapshot;
    expect((s.rows, s.cols), (null, null));
  });

  test('append, size and reset', () {
    final a = _parse('append', {'offset': 15, 'data64': _b64('!')}) as TerminalAppend;
    expect((a.offset, utf8.decode(a.data)), (15, '!'));
    final r = _parse('size', {'rows': 40, 'cols': 120}) as TerminalResize;
    expect((r.rows, r.cols), (40, 120));
    expect((_parse('reset', {'reason': 'not_shared'}) as TerminalReset).reason, 'not_shared');
    expect(_parse('append', {'offset': -1, 'data64': ''}), isNull);
    expect(_parse('append', {'offset': 1, 'data64': 'not base64!'}), isNull);
    expect(_parse('size', {'rows': 40}), isNull);
  });
}
