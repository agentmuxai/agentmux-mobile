import 'dart:convert';

import 'package:agentmux_mobile/core/fleet/sse.dart';
import 'package:agentmux_mobile/core/viewer/feed_events.dart';
import 'package:flutter_test/flutter_test.dart';

FeedEvent? _parse(String event, Map<String, Object?> data, {String? id}) =>
    parseFeedEvent(SseEvent(event: event, data: jsonEncode(data), id: id));

void main() {
  test('a snapshot before any transcript exists has an empty generation', () {
    final e = _parse('snapshot', {
      'provider': 'claude',
      'gen': '',
      'from_line': 0,
      'next_line': 0,
      'lines': <String>[],
    }, id: ':0');
    expect(e, isA<FeedSnapshot>());
    expect((e as FeedSnapshot).gen, '');
    expect(e.lines, isEmpty);
  });

  test('an append still needs a generation', () {
    expect(_parse('append', {'gen': '', 'line': 0, 'lines': ['x']}), isNull);
  });

  test('a status whose state has gone carries a null state', () {
    final e = _parse('status', {'state': null, 'since_ms': null, 'now_ms': 9});
    expect(e, isA<FeedStatus>());
    expect((e as FeedStatus).state, isNull);
    expect(e.nowMs, 9);
  });

  test('a status whose state is not text is skipped', () {
    expect(_parse('status', {'state': 3, 'now_ms': 9}), isNull);
  });
}
