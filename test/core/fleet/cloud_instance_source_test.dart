import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instance_source.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instances.dart';

const _instance = CloudInstance(
  instanceId: 'aaaa',
  hostname: 'atlas',
  channel: 'stable',
  version: '0.59.11',
  agents: [],
  receivedAtMs: 1,
);

void main() {
  late bool signedIn;
  late int fetches;
  late Object? Function() answer;
  late List<CloudUpdate> updates;

  setUp(() {
    signedIn = true;
    fetches = 0;
    answer = () => [_instance];
    updates = [];
  });

  CloudInstanceSource make() => CloudInstanceSource(
        isSignedIn: () async => signedIn,
        fetch: () async {
          fetches++;
          final a = answer();
          if (a is List<CloudInstance>) return a;
          throw a!;
        },
        onUpdate: updates.add,
      );

  test('signed out: nothing is fetched, and it says so', () {
    fakeAsync((async) {
      signedIn = false;
      final s = make()..start();
      async.elapse(const Duration(minutes: 2));
      expect(fetches, 0);
      expect(updates, isNotEmpty);
      expect(updates.every((u) => u is CloudSignedOut), isTrue);
      s.stop();
    });
  });

  test('a sign-in check that throws counts as signed out', () {
    fakeAsync((async) {
      final s = CloudInstanceSource(
        isSignedIn: () async => throw StateError('no token store'),
        fetch: () async {
          fetches++;
          return const [];
        },
        onUpdate: updates.add,
      )..start();
      async.flushMicrotasks();
      expect(fetches, 0);
      expect(updates.single, isA<CloudSignedOut>());
      s.stop();
    });
  });

  test('signed in: fetches on start, then every 30 s', () {
    fakeAsync((async) {
      final s = make()..start();
      async.flushMicrotasks();
      expect(fetches, 1);
      expect((updates.single as CloudFetched).instances.single.hostname,
          'atlas');
      async.elapse(const Duration(seconds: 29));
      expect(fetches, 1);
      async.elapse(const Duration(seconds: 1));
      expect(fetches, 2);
      s.stop();
    });
  });

  test('signing in is noticed at the next cycle', () {
    fakeAsync((async) {
      signedIn = false;
      final s = make()..start();
      async.flushMicrotasks();
      signedIn = true;
      async.elapse(const Duration(seconds: 30));
      expect(fetches, 1);
      expect(updates.last, isA<CloudFetched>());
      s.stop();
    });
  });

  test('a 404 is reported quietly and asked again only after 10 min', () {
    fakeAsync((async) {
      answer = () => const CloudInstancesUnsupported();
      final s = make()..start();
      async.flushMicrotasks();
      expect(updates.single, isA<CloudUnsupported>());
      async.elapse(const Duration(minutes: 9));
      expect(fetches, 1);
      async.elapse(const Duration(minutes: 1));
      expect(fetches, 2);
      s.stop();
    });
  });

  test('a failure is reported as unavailable and retried at the next tick',
      () {
    fakeAsync((async) {
      answer = () => DioException(
            requestOptions: RequestOptions(path: '/wan-instances'),
            type: DioExceptionType.connectionError,
          );
      final s = make()..start();
      async.flushMicrotasks();
      expect(updates.single, isA<CloudUnavailable>());
      answer = () => [_instance];
      async.elapse(const Duration(seconds: 30));
      expect(updates.last, isA<CloudFetched>());
      s.stop();
    });
  });

  test('refresh fetches at once and completes after that fetch', () {
    fakeAsync((async) {
      final s = make()..start();
      async.flushMicrotasks();
      var done = false;
      s.refresh().then((_) => done = true);
      async.flushMicrotasks();
      expect(fetches, 2);
      expect(done, isTrue);
      s.stop();
    });
  });

  test('stop ends it: no more fetches, no timers, no reports', () {
    fakeAsync((async) {
      final s = make()..start();
      async.flushMicrotasks();
      s.stop();
      async.elapse(const Duration(minutes: 5));
      expect(fetches, 1);
      expect(updates, hasLength(1));
      expect(async.pendingTimers, isEmpty);
      // Refreshing a stopped source is a no-op.
      var done = false;
      s.refresh().then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(fetches, 1);
    });
  });
}
