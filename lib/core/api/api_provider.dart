import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'muxbus_client.dart';
import 'muxbus_socket.dart';

final muxbusClientProvider = Provider<MuxbusClient>((ref) {
  return MuxbusClient(ref.watch(authRepositoryProvider));
});

final muxbusSocketProvider = Provider<MuxbusSocket>((ref) {
  final socket = MuxbusSocket(ref.watch(authRepositoryProvider));
  socket.init();
  ref.onDispose(socket.dispose);
  return socket;
});
