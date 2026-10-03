import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/channel_session.dart';
import 'package:agentmux_mobile/core/fleet/fleet_snapshot.dart';
import 'package:agentmux_mobile/core/fleet/fleet_transport.dart';

FleetSnapshot _snap(int rev, List<String> agents, {String epoch = 'e1'}) =>
    FleetSnapshot(
      epoch: epoch,
      rev: rev,
      hostname: 'narko',
      version: '0.59.7',
      channel: 'local-main',
      agents: agents,
    );

DioException _status(int code) {
  final req = RequestOptions(path: '/agentmux/fleet');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: code),
    type: DioExceptionType.badResponse,
  );
}

class _FakeTransport implements FleetTransport {
  final streams = <StreamController<FleetSnapshot?>>[];
  final lastEventIds = <String?>[];
  Object? eventsError;
  final polls = <Object>[];
  final etags = <String?>[];
  var legacyCalls = 0;

  @override
  Stream<FleetSnapshot?> events({String? lastEventId}) {
    lastEventIds.add(lastEventId);
    final error = eventsError;
    if (error != null) return Stream.error(error);
    final c = StreamController<FleetSnapshot?>();
    streams.add(c);
    return c.stream;
  }

  @override
  Future<FleetPoll> poll({String? etag}) async {
    etags.add(etag);
    final r = polls.isNotEmpty ? polls.removeAt(0) : const FleetNotModified();
    if (r is FleetPoll) return r;
    throw r;
  }

  @override
  Future<LegacyFleetInfo> legacy() async {
    legacyCalls++;
    return (
      hostname: 'charlie',
      version: '0.59.5',
      channel: null,
      agents: const [LanAgent(name: 'Opaz')],
    );
  }
}

void main() {
  group('fullJitterBackoff', () {
    test('stays within min(cap, base * 2^attempt)', () {
      final r = Random(1);
      for (var attempt = 0; attempt < 30; attempt++) {
        for (var i = 0; i < 50; i++) {
          final d = fullJitterBackoff(attempt, r);
          final ceiling = min(60000, 1000 * pow(2, min(attempt, 16)).toInt());
          expect(d.inMilliseconds, lessThan(max(ceiling, 1)));
          expect(d.isNegative, isFalse);
        }
      }
    });
  });

  group('ChannelSession', () {
    late _FakeTransport t;
    late List<SessionUpdate> updates;
    late ChannelSession session;

    ChannelSession make({SessionMode mode = SessionMode.stream}) =>
        ChannelSession(
          transport: t,
          onUpdate: updates.add,
          startMode: mode,
          random: Random(7),
        );

    setUp(() {
      t = _FakeTransport();
      updates = [];
    });

    test('a stream event becomes a contact with agents; a heartbeat without',
        () {
      fakeAsync((async) {
        session = make()..start();
        async.flushMicrotasks();
        t.streams.single.add(null);
        t.streams.single.add(_snap(1, ['Clamk', 'AgentY']));
        async.flushMicrotasks();
        final contacts = updates.whereType<SessionContact>().toList();
        expect(contacts.first.agents, isNull);
        expect(contacts.last.agents!.map((a) => a.name), ['Clamk', 'AgentY']);
        expect(contacts.last.epoch, 'e1');
        expect(contacts.last.rev, 1);
        session.stop();
      });
    });

    test('reconnects after a drop, resuming from the last event id', () {
      fakeAsync((async) {
        session = make()..start();
        async.flushMicrotasks();
        t.streams.single.add(_snap(3, ['A']));
        async.flushMicrotasks();
        t.streams.single.addError(TimeoutException('silence'));
        async.flushMicrotasks();
        // First retry: attempt 0, so under a second.
        async.elapse(const Duration(seconds: 1));
        expect(t.streams, hasLength(2));
        expect(t.lastEventIds, [null, 'e1:3']);
        session.stop();
      });
    });

    test('an older srv without the stream falls back to polling with ETag', () {
      fakeAsync((async) {
        t.eventsError = const FleetFeedUnsupported('fleet/events');
        t.polls.add(FleetFetched(_snap(2, ['A'])));
        session = make()..start();
        async.flushMicrotasks();
        expect(session.mode, SessionMode.poll);
        expect(t.etags, [null]);
        // The first fetch was a change, so the next poll comes within ~3 s.
        async.elapse(const Duration(milliseconds: 3600));
        expect(t.etags, [null, 'e1:2']);
        expect(updates.whereType<SessionContact>(), hasLength(2));
        session.stop();
      });
    });

    test('an srv without the fleet routes falls back to the legacy routes', () {
      fakeAsync((async) {
        t.eventsError = const FleetFeedUnsupported('fleet/events');
        t.polls.add(const FleetFeedUnsupported('fleet'));
        session = make()..start();
        async.flushMicrotasks();
        expect(session.mode, SessionMode.legacy);
        expect(t.legacyCalls, 1);
        final c = updates.whereType<SessionContact>().single;
        expect(c.agents!.single.name, 'Opaz');
        expect(c.hostname, 'charlie');
        session.stop();
      });
    });

    test('a full-key session starts on the legacy routes', () {
      fakeAsync((async) {
        session = make(mode: SessionMode.legacy)..start();
        async.flushMicrotasks();
        expect(t.streams, isEmpty);
        expect(t.legacyCalls, 1);
        session.stop();
      });
    });

    test('quiet polling slows to about 10 s', () {
      fakeAsync((async) {
        session = make(mode: SessionMode.legacy)..start();
        async.flushMicrotasks();
        // The first answer is a change; after a minute of no change it is quiet.
        async.elapse(const Duration(minutes: 2));
        final before = t.legacyCalls;
        async.elapse(const Duration(seconds: 30));
        final perHalfMinute = t.legacyCalls - before;
        expect(perHalfMinute, inInclusiveRange(2, 4));
        session.stop();
      });
    });

    test('a 401 is reported as unauthorized and retried slowly', () {
      fakeAsync((async) {
        t.eventsError = _status(401);
        session = make()..start();
        async.flushMicrotasks();
        expect(updates.single, isA<SessionFailure>());
        expect((updates.single as SessionFailure).error,
            ChannelError.unauthorized);
        async.elapse(const Duration(seconds: 59));
        expect(t.lastEventIds, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(t.lastEventIds, hasLength(2));
        session.stop();
      });
    });

    test('a network error is reported as unreachable and backs off', () {
      fakeAsync((async) {
        t.eventsError = _status(500);
        session = make()..start();
        async.flushMicrotasks();
        expect((updates.first as SessionFailure).error, ChannelError.unreachable);
        // Ten failures in a row stay within the summed backoff ceilings.
        async.elapse(const Duration(minutes: 3));
        expect(t.lastEventIds.length, greaterThan(3));
        expect(t.lastEventIds.length, lessThan(40));
        session.stop();
      });
    });

    test('stop() ends the session: no further updates or timers', () {
      fakeAsync((async) {
        session = make()..start();
        async.flushMicrotasks();
        session.stop();
        async.flushMicrotasks();
        expect(t.streams.single.hasListener, isFalse);
        final count = updates.length;
        async.elapse(const Duration(minutes: 5));
        expect(updates.length, count);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('resync() skips a pending wait', () {
      fakeAsync((async) {
        session = make(mode: SessionMode.legacy)..start();
        async.flushMicrotasks();
        expect(t.legacyCalls, 1);
        session.resync();
        async.flushMicrotasks();
        expect(t.legacyCalls, 2);
        session.stop();
      });
    });
  });
}
