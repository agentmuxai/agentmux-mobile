import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settings.dart';
import '../rpc/rpc_types.dart';
import 'connection_provider.dart';

/// App settings from the connected backend.
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  final connState = ref.watch(rpcConnectionStateProvider);
  if (connState.value != RpcConnectionState.connected) {
    return const AppSettings();
  }

  final client = ref.read(rpcClientProvider);
  final config = await client.getFullConfig();
  final settingsMap = config['settings'] as Map<String, dynamic>? ?? {};
  return AppSettings.fromSettingsMap(settingsMap);
});

/// Update a single setting on the backend.
final updateSettingProvider =
    Provider<Future<void> Function(String key, dynamic value)>((ref) {
  return (String key, dynamic value) async {
    final client = ref.read(rpcClientProvider);
    await client.setConfig({key: value});
    ref.invalidate(appSettingsProvider);
  };
});
