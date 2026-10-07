import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The few secure-storage calls the viewer code needs, behind an interface so
/// tests can use an in-memory fake.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// [SecureStore] over the platform keystore, configured like `TokenStorage`.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore();

  final _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _store.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _store.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _store.delete(key: key);
}
