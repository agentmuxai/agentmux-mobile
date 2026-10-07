import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'paired_host.dart';
import 'secure_store.dart';

/// Reads and writes the paired hosts, as one JSON list in secure storage
/// (the token is a bearer secret; nothing here goes anywhere else).
class PairedHostsRepository {
  PairedHostsRepository(this._store);

  final SecureStore _store;

  static const storageKey = 'viewer_paired_hosts_v1';

  /// A record that does not parse is dropped (its host only needs pairing
  /// again); a store that does not parse at all reads as empty.
  Future<List<PairedHost>> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded.map(PairedHost.fromJson).whereType<PairedHost>().toList();
  }

  Future<void> save(List<PairedHost> hosts) async {
    if (hosts.isEmpty) {
      await _store.delete(storageKey);
      return;
    }
    await _store.write(
      storageKey,
      jsonEncode([for (final h in hosts) h.toJson()]),
    );
  }
}

/// The platform keystore; overridden in tests.
final secureStoreProvider = Provider<SecureStore>((_) => FlutterSecureStore());

final pairedHostsRepositoryProvider = Provider<PairedHostsRepository>(
  (ref) => PairedHostsRepository(ref.watch(secureStoreProvider)),
);

final pairedHostsProvider =
    NotifierProvider<PairedHostsNotifier, List<PairedHost>>(
  PairedHostsNotifier.new,
);

/// The paired hosts, loaded from secure storage at start and written back on
/// every change. Empty until the first load finishes ([ready]).
class PairedHostsNotifier extends Notifier<List<PairedHost>> {
  /// Completes once the stored list has been read (or failed to be).
  late Future<void> ready;

  /// Writes run one after another, in the order the changes were made.
  Future<void> _writes = Future.value();

  PairedHostsRepository get _repo => ref.read(pairedHostsRepositoryProvider);

  @override
  List<PairedHost> build() {
    ready = _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final hosts = await _repo.load();
      if (hosts.isNotEmpty) state = hosts;
    } catch (e, st) {
      // No keystore (a unit test without a binding) or a broken one: the
      // device simply has no pairings this session.
      AppLogger.log('Could not read paired hosts',
          name: 'PairedHosts', error: e, stackTrace: st);
    }
  }

  /// Stores [host], replacing any earlier pairing with the same channel of
  /// the same install.
  Future<void> add(PairedHost host) => _mutate(
        (list) => [
          for (final h in list)
            if (!h.sameTarget(host)) h,
          host,
        ],
      );

  /// Unpair: forgets the record on this device. (The grant on the computer
  /// stays until revoked there.)
  Future<void> remove(String id) =>
      _mutate((list) => [for (final h in list) if (h.id != id) h]);

  /// The computer refused the token.
  Future<void> markInvalid(String id) => _mutate((list) => [
        for (final h in list) h.id == id ? h.copyWith(invalid: true) : h,
      ]);

  /// Discovery found the viewer listener somewhere else.
  Future<void> updateEndpoint(String id, String host, int port) =>
      _mutate((list) => [
            for (final h in list)
              h.id == id ? h.copyWith(host: host, port: port) : h,
          ]);

  Future<void> _mutate(
    List<PairedHost> Function(List<PairedHost>) change,
  ) async {
    await ready;
    final next = List<PairedHost>.unmodifiable(change(state));
    state = next;
    // A failed write is logged, not thrown: the change already holds for
    // this session, and the next change writes the whole list again.
    _writes = _writes
        .then((_) => _repo.save(next))
        .catchError((Object e, StackTrace st) {
      AppLogger.log('Could not save paired hosts',
          name: 'PairedHosts', error: e, stackTrace: st);
    });
    await _writes;
  }
}
