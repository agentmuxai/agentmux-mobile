import 'dart:convert';

import 'package:agentmux_mobile/core/viewer/paired_hosts_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'viewer_fakes.dart';

void main() {
  group('PairedHostsRepository', () {
    test('round-trips every field', () async {
      final store = InMemorySecureStore();
      final repo = PairedHostsRepository(store);
      final host = testPairedHost(invalid: true);
      await repo.save([host]);
      final loaded = (await repo.load()).single;
      expect(loaded.id, host.id);
      expect(loaded.token, host.token);
      expect(loaded.fingerprint, host.fingerprint);
      expect(loaded.host, host.host);
      expect(loaded.port, host.port);
      expect(loaded.hostname, host.hostname);
      expect(loaded.channel, host.channel);
      expect(loaded.installId, host.installId);
      expect(loaded.deviceId, host.deviceId);
      expect(loaded.pairedAt.millisecondsSinceEpoch,
          host.pairedAt.millisecondsSinceEpoch);
      expect(loaded.invalid, isTrue);
    });

    test('a malformed record is dropped, the rest kept', () async {
      final store = InMemorySecureStore()
        ..values[PairedHostsRepository.storageKey] = jsonEncode([
          {'id': 'broken'},
          testPairedHost(id: 'ok').toJson(),
        ]);
      final loaded = await PairedHostsRepository(store).load();
      expect(loaded.map((h) => h.id), ['ok']);
    });

    test('a record with a wrongly typed field is dropped, the rest kept',
        () async {
      final bad = testPairedHost(id: 'bad').toJson()..['fp'] = 123;
      final store = InMemorySecureStore()
        ..values[PairedHostsRepository.storageKey] = jsonEncode([
          bad,
          testPairedHost(id: 'ok').toJson(),
        ]);
      final loaded = await PairedHostsRepository(store).load();
      expect(loaded.map((h) => h.id), ['ok']);
    });

    test('unreadable storage reads as empty', () async {
      final store = InMemorySecureStore()
        ..values[PairedHostsRepository.storageKey] = '{not json';
      expect(await PairedHostsRepository(store).load(), isEmpty);
    });

    test('saving nothing deletes the key', () async {
      final store = InMemorySecureStore();
      final repo = PairedHostsRepository(store);
      await repo.save([testPairedHost()]);
      await repo.save(const []);
      expect(store.values, isEmpty);
    });
  });

  group('pairedHostsProvider', () {
    late InMemorySecureStore store;
    late ProviderContainer container;

    setUp(() {
      store = InMemorySecureStore();
      container = ProviderContainer(overrides: [
        secureStoreProvider.overrideWithValue(store),
      ]);
    });
    tearDown(() => container.dispose());

    PairedHostsNotifier notifier() => container.read(pairedHostsProvider.notifier);

    test('loads what was stored', () async {
      await PairedHostsRepository(store).save([testPairedHost()]);
      container.read(pairedHostsProvider);
      await notifier().ready;
      expect(container.read(pairedHostsProvider).single.id, 'p1');
    });

    test('a new pairing with the same install replaces the old one', () async {
      await notifier().add(testPairedHost(id: 'old'));
      await notifier().add(testPairedHost(id: 'other', installId: 'otherinstall'));
      await notifier().add(testPairedHost(id: 'new'));
      expect(container.read(pairedHostsProvider).map((h) => h.id),
          ['other', 'new']);
      final saved = await PairedHostsRepository(store).load();
      expect(saved.map((h) => h.id), ['other', 'new']);
    });

    test('without install ids, hostname and channel decide', () async {
      await notifier().add(testPairedHost(id: 'a', installId: null));
      await notifier()
          .add(testPairedHost(id: 'b', installId: null, channel: 'dev'));
      await notifier().add(testPairedHost(id: 'c', installId: null));
      expect(container.read(pairedHostsProvider).map((h) => h.id), ['b', 'c']);
    });

    test('unpair, mark invalid, and follow a move', () async {
      await notifier().add(testPairedHost(id: 'a'));
      await notifier()
          .add(testPairedHost(id: 'b', installId: 'otherinstall'));

      await notifier().markInvalid('a');
      await notifier().updateEndpoint('b', '198.51.100.21', 29801);
      var hosts = container.read(pairedHostsProvider);
      expect(hosts.firstWhere((h) => h.id == 'a').invalid, isTrue);
      final b = hosts.firstWhere((h) => h.id == 'b');
      expect((b.host, b.port), ('198.51.100.21', 29801));

      await notifier().remove('a');
      hosts = container.read(pairedHostsProvider);
      expect(hosts.map((h) => h.id), ['b']);
      final saved = await PairedHostsRepository(store).load();
      expect(saved.single.port, 29801);
    });
  });
}
