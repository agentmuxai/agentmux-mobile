import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agentmux_mobile/core/api/muxbus_client.dart';
import 'package:agentmux_mobile/core/auth/auth_repository.dart';
import 'package:agentmux_mobile/core/auth/token_storage.dart';
import 'package:agentmux_mobile/core/discovery/models/lan_instance.dart';
import 'package:agentmux_mobile/core/fleet/cloud_instances.dart';

Map<String, Object?> _record([Map<String, Object?> extra = const {}]) => {
      'v': 1,
      'instance_id': 'testinstallidtestinstallid',
      'hostname': 'narko',
      'channel': 'local-main-0a1b2c-5e6f7a8b',
      'os': 'windows',
      'version': '0.59.11',
      'channels_running': 3,
      'agents': [
        {'name': 'AgentX', 'kind': 'container'},
        {'name': 'Camper', 'kind': 'host'},
      ],
      'published_at_ms': 1791352493388,
      'received_at_ms': 1791352494000,
      ...extra,
    };

/// Answers every request with [status] and [body].
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = const {}, this.date]);
  final int status;
  final Object body;
  final String? date;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (date != null) 'date': [date!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('CloudInstance.tryParse', () {
    test('reads a record', () {
      final c = CloudInstance.tryParse(_record())!;
      expect(c.instanceId, 'testinstallidtestinstallid');
      expect(c.hostname, 'narko');
      expect(c.channel, 'local-main-0a1b2c-5e6f7a8b');
      expect(c.os, 'windows');
      expect(c.version, '0.59.11');
      expect(c.channelsRunning, 3);
      expect(c.agents.map((a) => a.name), ['AgentX', 'Camper']);
      expect(c.agents.map((a) => a.kind), [AgentKind.container, AgentKind.host]);
      expect(c.receivedAtMs, 1791352494000);
    });

    test('a record missing a required field is skipped', () {
      for (final key in [
        'instance_id',
        'hostname',
        'channel',
        'received_at_ms',
      ]) {
        final r = _record()..remove(key);
        expect(CloudInstance.tryParse(r), isNull, reason: key);
      }
    });

    test('control characters and oversized strings are refused', () {
      expect(CloudInstance.tryParse(_record({'hostname': 'nar\u0007ko'})),
          isNull);
      expect(CloudInstance.tryParse(_record({'channel': 'c' * 129})), isNull);
      final c = CloudInstance.tryParse(_record({
        'agents': [
          {'name': 'ok\nnot', 'kind': 'host'},
          {'name': 'Fine', 'kind': 'host'},
        ],
      }))!;
      expect(c.agents.map((a) => a.name), ['Fine']);
    });

    test('optional fields that are malformed are dropped', () {
      final c = CloudInstance.tryParse(_record({
        'os': 'Windows',
        'version': 'v' * 65,
        'channels_running': 'three',
        'agents': [
          {'name': 'AgentX', 'kind': 'vm'},
          {'name': 'agentx', 'kind': 'host'},
          'junk',
        ],
      }))!;
      expect(c.os, isNull);
      expect(c.version, '');
      expect(c.channelsRunning, isNull);
      // Unknown kind is no kind; a duplicate name (any case) is dropped.
      expect(c.agents.single.name, 'AgentX');
      expect(c.agents.single.kind, isNull);
    });

    test('at most 200 agents', () {
      final c = CloudInstance.tryParse(_record({
        'agents': [
          for (var i = 0; i < 300; i++) {'name': 'a$i', 'kind': 'host'},
        ],
      }))!;
      expect(c.agents, hasLength(CloudInstance.maxAgents));
    });
  });

  group('CloudInstance.parseList', () {
    test('skips bad records and keeps the newest per install', () {
      final list = CloudInstance.parseList({
        'instances': [
          _record(),
          _record({'received_at_ms': 1791352499999, 'version': '0.59.12'}),
          {'nonsense': true},
          _record({'instance_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbb'}),
        ],
      });
      expect(list, hasLength(2));
      final narko = list.firstWhere(
          (c) => c.instanceId == 'testinstallidtestinstallid');
      expect(narko.version, '0.59.12');
    });

    test('relay times move onto the device clock by the relay Date header', () {
      // The device clock runs 5 minutes ahead of the relay's.
      final relayNow = DateTime.fromMillisecondsSinceEpoch(1791352500000);
      final fetchedAt = relayNow.add(const Duration(minutes: 5));
      final list = CloudInstance.parseList(
        {
          'instances': [
            _record({
              'v': 2,
              'received_at_ms': 1791352490000,
              'agents': [
                {'name': 'Camper', 'kind': 'host', 'state': 'working'},
              ],
            }),
          ],
        },
        relayNow: relayNow,
        fetchedAt: fetchedAt,
      );
      final c = list.single;
      // 10 s old by the relay's clock, and still 10 s old on the device.
      expect(fetchedAt.millisecondsSinceEpoch - c.receivedAtMs, 10000);
      expect(fetchedAt.difference(c.agents.single.stateAsOf!),
          const Duration(seconds: 10));
    });

    test('without the relay clock the times are used as given', () {
      final list = CloudInstance.parseList({
        'instances': [_record()],
      });
      expect(list.single.receivedAtMs, 1791352494000);
    });

    test('a body that is not the list shape is empty', () {
      expect(CloudInstance.parseList(null), isEmpty);
      expect(CloudInstance.parseList({'instances': 'x'}), isEmpty);
      expect(CloudInstance.parseList(['x']), isEmpty);
    });
  });

  group('MuxbusClient.getInstances', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('reads GET /wan-instances', () async {
      final adapter = _Adapter(200, {
        'instances': [_record()],
      });
      final client = MuxbusClient(AuthRepository(TokenStorage()),
          httpClientAdapter: adapter);
      final list = await client.getInstances();
      expect(adapter.paths, ['/wan-instances']);
      expect(list.single.hostname, 'narko');
    });

    test('reads the relay clock from the Date header', () async {
      final adapter = _Adapter(
        200,
        {'instances': [_record()]},
        // received_at_ms is 1791352494000; the relay says it is 6 s later.
        HttpDate.format(DateTime.fromMillisecondsSinceEpoch(1791352500000)),
      );
      final client = MuxbusClient(AuthRepository(TokenStorage()),
          httpClientAdapter: adapter);
      final fetched = DateTime.now();
      final c = (await client.getInstances()).single;
      final age = fetched.millisecondsSinceEpoch - c.receivedAtMs;
      expect(age, inInclusiveRange(5000, 8000),
          reason: 'about 6 s old, whatever this machine clock says');
    });

    test('a 404 (an older relay) is CloudInstancesUnsupported', () async {
      final client = MuxbusClient(AuthRepository(TokenStorage()),
          httpClientAdapter: _Adapter(404));
      await expectLater(
        client.getInstances(),
        throwsA(isA<CloudInstancesUnsupported>()),
      );
    });

    test('any other failure is rethrown as is', () async {
      final client = MuxbusClient(AuthRepository(TokenStorage()),
          httpClientAdapter: _Adapter(500));
      await expectLater(client.getInstances(), throwsA(isA<DioException>()));
    });
  });

  group('CloudInstance.tryParse agent states', () {
    Map<String, Object?> v2(List<Object?> agents) =>
        _record({'v': 2, 'agents': agents});

    test('a v2 record carries each state, as of its receive time', () {
      final c = CloudInstance.tryParse(v2([
        {'name': 'A', 'kind': 'host', 'state': 'working'},
        {'name': 'B', 'kind': 'host', 'state': 'waiting'},
        {'name': 'C', 'kind': 'host', 'state': 'idle'},
        {'name': 'D', 'kind': 'host', 'state': 'stopped'},
        {'name': 'E', 'kind': 'host', 'state': 'error'},
      ]))!;
      expect(c.agents.map((a) => a.state), [
        AgentState.working,
        AgentState.waiting,
        AgentState.idle,
        AgentState.stopped,
        AgentState.error,
      ]);
      for (final a in c.agents) {
        expect(a.stateAsOf,
            DateTime.fromMillisecondsSinceEpoch(1791352494000));
        // The cloud sends no since time.
        expect(a.stateSince, isNull);
      }
    });

    test('a v2 agent without a state, or with a bad one, has none', () {
      final c = CloudInstance.tryParse(v2([
        {'name': 'A', 'kind': 'host'},
        {'name': 'B', 'kind': 'host', 'state': 'busy'},
        {'name': 'C', 'kind': 'host', 'state': 7},
        {'name': 'D', 'kind': 'host', 'state': ''},
      ]))!;
      expect(c.agents.map((a) => a.name), ['A', 'B', 'C', 'D']);
      for (final a in c.agents) {
        expect(a.state, isNull, reason: a.name);
        expect(a.stateAsOf, isNull, reason: a.name);
      }
    });

    test('a v1 record has no states, even if one is present', () {
      final c = CloudInstance.tryParse(_record({
        'agents': [
          {'name': 'AgentX', 'kind': 'container', 'state': 'working'},
        ],
      }))!;
      expect(c.agents.single.kind, AgentKind.container);
      expect(c.agents.single.state, isNull);
      // A record with no `v` at all reads like v1.
      final none = CloudInstance.tryParse(_record({
        'v': null,
        'agents': [
          {'name': 'AgentX', 'state': 'working'},
        ],
      }))!;
      expect(none.agents.single.state, isNull);
    });
  });
}
