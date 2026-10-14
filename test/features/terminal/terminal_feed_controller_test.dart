import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:agentmux_mobile/core/viewer/terminal_events.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/terminal/terminal_feed_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Always the top of the backoff range, so waits are predictable.
class _MaxRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0.999;
  @override
  bool nextBool() => true;
}

/// A desktop's terminal route: each connection is a controller the test drives.
class _FakeFeed {
  final connects = <String?>[];
  final streams = <StreamController<TerminalEvent?>>[];
  Object? refuseWith;

  Stream<TerminalEvent?> open({String? lastEventId}) {
    connects.add(lastEventId);
    final refuse = refuseWith;
    if (refuse != null) return Stream.error(refuse);
    final c = StreamController<TerminalEvent?>();
    streams.add(c);
    return c.stream;
  }

  StreamController<TerminalEvent?> get last => streams.last;
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

TerminalSnapshot _snapshot(String text, {int offset = 0, int? rows, int? cols}) {
  final data = _bytes(text);
  return TerminalSnapshot(
    offset: offset,
    nextOffset: offset + data.length,
    data: data,
    rows: rows,
    cols: cols,
  );
}

/// What the terminal shows, one string per non-blank line.
List<String> _screen(TerminalFeedController c) => [
      for (final line in c.terminal!.buffer.getText().split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];

void main() {
  late _FakeFeed feed;
  var unauthorized = 0;

  TerminalFeedController controller() => TerminalFeedController(
        source: feed.open,
        onUnauthorized: () => unauthorized++,
        random: _MaxRandom(),
      );

  setUp(() {
    feed = _FakeFeed();
    unauthorized = 0;
  });

  test('a snapshot at the desktop\'s size, then each write once', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.terminal, isNull);
      feed.last
        ..add(null)
        ..add(_snapshot('\$ ls\r\na  b\r\n', rows: 30, cols: 100));
      async.flushMicrotasks();
      expect(c.connection, TerminalConnection.live);
      expect((c.terminal!.viewHeight, c.terminal!.viewWidth), (30, 100));
      expect(_screen(c), ['\$ ls', 'a  b']);
      expect(c.lastEventId, '12');

      feed.last
        ..add(TerminalAppend(offset: 12, data: _bytes('\x1b[32mok\x1b[0m\r\n')))
        // Already shown: skipped.
        ..add(TerminalAppend(offset: 6, data: _bytes('a  b\r\n')));
      async.flushMicrotasks();
      expect(_screen(c), ['\$ ls', 'a  b', 'ok'], reason: 'escapes are drawn, not shown');

      feed.last.add(const TerminalResize(rows: 40, cols: 120));
      async.flushMicrotasks();
      expect(c.size, (40, 120));
      expect(c.terminal!.viewWidth, 120);
      c.dispose();
    });
  });

  test('a character split across two writes is kept whole', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      final euro = utf8.encode('€'); // three bytes
      feed.last
        ..add(_snapshot(''))
        ..add(TerminalAppend(offset: 0, data: Uint8List.fromList(euro.sublist(0, 1))))
        ..add(TerminalAppend(offset: 1, data: Uint8List.fromList([...euro.sublist(1), 0x0d, 0x0a])));
      async.flushMicrotasks();
      expect(_screen(c), ['€']);
      c.dispose();
    });
  });

  test('a dropped stream resumes after the last byte; a gap gets a snapshot', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot('one\r\n'));
      async.flushMicrotasks();
      unawaited(feed.last.close());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(feed.connects, [null, '5']);

      // Bytes 5..9 never arrived.
      feed.last.add(TerminalAppend(offset: 9, data: _bytes('x')));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(feed.connects.last, isNull, reason: 'no resume point: a fresh snapshot');
      c.dispose();
    });
  });

  test('an event the parser refuses restarts from a snapshot, not the same place', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot('one\r\n'));
      async.flushMicrotasks();

      feed.last.addError(const FormatException('event-stream line exceeds the size limit'));
      async.flushMicrotasks();
      expect(c.connection, TerminalConnection.reconnecting);
      async.elapse(const Duration(seconds: 2));
      // Resuming at byte 5 would be sent the same oversize event again.
      expect(feed.connects, [null, null]);
      c.dispose();
    });
  });

  test('not shared, on connect or while watching, ends the feed', () {
    fakeAsync((async) {
      feed.refuseWith = const ViewerForbidden();
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.connection, TerminalConnection.notShared);
      async.elapse(const Duration(minutes: 1));
      expect(feed.connects, hasLength(1), reason: 'no retries');
      c.dispose();

      feed.refuseWith = null;
      final d = controller()..start();
      async.flushMicrotasks();
      feed.last
        ..add(_snapshot('x\r\n'))
        ..add(const TerminalReset('not_shared'));
      async.flushMicrotasks();
      expect(d.connection, TerminalConnection.notShared);
      expect(d.terminal, isNull);
      d.dispose();
    });
  });

  test('401 stops for good and reports it; 404 is not found', () {
    fakeAsync((async) {
      feed.refuseWith = const ViewerUnauthorized();
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.connection, TerminalConnection.unauthorized);
      expect(unauthorized, 1);
      c.dispose();
      feed.refuseWith = const ViewerNotFound();
      final d = controller()..start();
      async.flushMicrotasks();
      expect(d.connection, TerminalConnection.notFound);
      d.dispose();
    });
  });
}
