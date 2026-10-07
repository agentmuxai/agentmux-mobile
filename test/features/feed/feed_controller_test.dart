import 'dart:async';
import 'dart:math';

import 'package:agentmux_mobile/core/viewer/feed_events.dart';
import 'package:agentmux_mobile/core/viewer/viewer_client.dart';
import 'package:agentmux_mobile/features/feed/feed_controller.dart';
import 'package:agentmux_mobile/features/feed/transcript.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'claude_fixtures.dart';

/// Always the top of the backoff range, so waits are predictable.
class _MaxRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0.999;
  @override
  bool nextBool() => true;
}

/// A desktop's feed route: each connection is a controller the test drives.
class _FakeFeed {
  final connects = <String?>[];
  final streams = <StreamController<FeedEvent?>>[];
  Object? refuseWith;

  Stream<FeedEvent?> open({String? lastEventId}) {
    connects.add(lastEventId);
    final refuse = refuseWith;
    if (refuse != null) return Stream.error(refuse);
    final c = StreamController<FeedEvent?>();
    streams.add(c);
    return c.stream;
  }

  StreamController<FeedEvent?> get last => streams.last;
}

FeedSnapshot _snapshot({String gen = '1', int next = 3, List<String>? lines}) =>
    FeedSnapshot(
      provider: 'claude',
      gen: gen,
      fromLine: 0,
      nextLine: next,
      lines: lines ??
          [userPrompt('one'), assistantText('two'), assistantText('three')],
      id: '$gen:$next',
    );

List<String> _texts(FeedController c) => [
      for (final i in c.transcript!.items)
        switch (i) {
          PromptItem(:final text) => text,
          AssistantTextItem(:final text) => text,
          _ => i.runtimeType.toString(),
        },
    ];

void main() {
  late _FakeFeed feed;
  var unauthorized = 0;

  FeedController controller() => FeedController(
        source: feed.open,
        onUnauthorized: () => unauthorized++,
        random: _MaxRandom(),
      );

  setUp(() {
    feed = _FakeFeed();
    unauthorized = 0;
  });

  test('snapshot, then appends in order', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.connecting);
      expect(c.transcript, isNull);

      feed.last
        ..add(null)
        ..add(_snapshot());
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.live);
      expect(_texts(c), ['one', 'two', 'three']);
      expect(c.lastEventId, '1:3');

      feed.last.add(FeedAppend(
          gen: '1', line: 3, lines: [assistantText('four')], id: '1:4'));
      async.flushMicrotasks();
      expect(_texts(c), ['one', 'two', 'three', 'four']);
      expect(c.lastEventId, '1:4');
      c.dispose();
    });
  });

  test('a dropped stream resumes with Last-Event-ID, without repeats', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot());
      async.flushMicrotasks();

      feed.last.addError(TimeoutException('silence'));
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.reconnecting);
      // First retry within 1 s (full jitter, attempt 0).
      async.elapse(const Duration(seconds: 1));
      expect(feed.connects, [null, '1:3']);
      // Content stays while reconnecting.
      expect(_texts(c), ['one', 'two', 'three']);

      // The resumed stream overlaps by one line: it is not shown twice.
      feed.last
        ..add(null)
        ..add(FeedAppend(
          gen: '1',
          line: 2,
          lines: [assistantText('three'), assistantText('four')],
          id: '1:4',
        ));
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.live);
      expect(_texts(c), ['one', 'two', 'three', 'four']);
      c.dispose();
    });
  });

  test('backoff grows while the computer stays away', () {
    fakeAsync((async) {
      feed.refuseWith = TimeoutException('down');
      final c = controller()..start();
      async.flushMicrotasks();
      expect(feed.connects, hasLength(1));
      // Attempt 0 waits up to 1 s, attempt 1 up to 2 s, attempt 2 up to 4 s
      // (the fake random picks the top: 999, 1999, 3999 ms).
      async.elapse(const Duration(milliseconds: 998));
      expect(feed.connects, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(feed.connects, hasLength(2));
      async.elapse(const Duration(milliseconds: 1998));
      expect(feed.connects, hasLength(2));
      async.elapse(const Duration(milliseconds: 1));
      expect(feed.connects, hasLength(3));
      async.elapse(const Duration(milliseconds: 4000));
      expect(feed.connects, hasLength(4));
      expect(c.connection, FeedConnection.reconnecting);
      c.dispose();
    });
  });

  test('reset clears the screen; the next snapshot replaces it', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot());
      async.flushMicrotasks();

      feed.last.add(const FeedReset('replaced'));
      async.flushMicrotasks();
      expect(c.transcript, isNull);
      expect(c.lastEventId, isNull);

      feed.last.add(_snapshot(gen: '2', next: 1, lines: [userPrompt('new')]));
      async.flushMicrotasks();
      expect(_texts(c), ['new']);
      expect(c.lastEventId, '2:1');
      c.dispose();
    });
  });

  test('an append that does not follow on gets a fresh snapshot', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot());
      async.flushMicrotasks();

      // A gap: lines 3 and 4 never arrived.
      feed.last.add(FeedAppend(gen: '1', line: 5, lines: [assistantText('x')]));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      // Reconnected without a resume point, so the server sends a snapshot.
      expect(feed.connects, [null, null]);
      expect(_texts(c), ['one', 'two', 'three']);
      c.dispose();
    });
  });

  test('401: stops for good and reports it', () {
    fakeAsync((async) {
      feed.refuseWith = const ViewerUnauthorized();
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.unauthorized);
      expect(unauthorized, 1);
      async.elapse(const Duration(minutes: 5));
      expect(feed.connects, hasLength(1));
      c.dispose();
    });
  });

  test('404: the agent cannot be watched; no retries', () {
    fakeAsync((async) {
      feed.refuseWith = const ViewerNotFound();
      final c = controller()..start();
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.notFound);
      async.elapse(const Duration(minutes: 5));
      expect(feed.connects, hasLength(1));
      c.dispose();
    });
  });

  test('status is kept for the chip; heartbeats change nothing', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last
        ..add(_snapshot())
        ..add(const FeedStatus(state: 'working', sinceMs: 5, nowMs: 9))
        ..add(null);
      async.flushMicrotasks();
      expect(c.status?.state, 'working');
      expect(c.status?.sinceMs, 5);
      // Anchored at this device's clock when it arrived.
      expect(c.statusReceivedAt, clock.now());
      expect(_texts(c), ['one', 'two', 'three']);
      c.dispose();
    });
  });

  test('background stops the stream; foreground resumes where it left off', () {
    fakeAsync((async) {
      final c = controller()..start();
      async.flushMicrotasks();
      feed.last.add(_snapshot());
      async.flushMicrotasks();

      c.pause();
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.paused);
      expect(feed.last.hasListener, isFalse);
      async.elapse(const Duration(minutes: 10));
      expect(feed.connects, hasLength(1));

      c.resume();
      async.flushMicrotasks();
      expect(feed.connects, [null, '1:3']);
      feed.last.add(null);
      async.flushMicrotasks();
      expect(c.connection, FeedConnection.live);
      expect(_texts(c), ['one', 'two', 'three']);
      c.dispose();
    });
  });
}
