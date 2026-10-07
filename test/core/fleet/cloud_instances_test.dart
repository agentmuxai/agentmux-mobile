import 'dart:convert';
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
      'instance_public_key': 'AAAA',
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
      'sig': 'BBBB',
      'received_at_ms': 1791352494000,
      ...extra,
    };

/// Answers every request with [status] and [body].
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = const {}]);
  final int status;
  final Object body;
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
}
