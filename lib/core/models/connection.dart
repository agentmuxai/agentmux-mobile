import 'package:freezed_annotation/freezed_annotation.dart';

part 'connection.freezed.dart';
part 'connection.g.dart';

/// A saved backend connection configuration.
@freezed
class ServerConnection with _$ServerConnection {
  const factory ServerConnection({
    required String id,
    required String name,
    required String host,
    @Default(1730) int port,
    required String authKey,
    @Default(false) bool useTls,
    DateTime? lastConnected,
  }) = _ServerConnection;

  factory ServerConnection.fromJson(Map<String, dynamic> json) =>
      _$ServerConnectionFromJson(json);
}

/// Real-time connection status.
@freezed
class ConnectionStatus with _$ConnectionStatus {
  const factory ConnectionStatus({
    required String connectionId,
    required ConnectionState state,
    String? error,
    @Default(0) int sessionCount,
  }) = _ConnectionStatus;

  factory ConnectionStatus.fromJson(Map<String, dynamic> json) =>
      _$ConnectionStatusFromJson(json);
}

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
