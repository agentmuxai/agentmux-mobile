import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_repository.dart';

const _wsBase = String.fromEnvironment(
  'MUXBUS_WS_BASE',
  defaultValue: 'wss://muxbus-ws.agentmux.ai',
);

enum MuxbusEventType { injectAvailable, unknown }

class MuxbusEvent {
  const MuxbusEvent(this.type);
  final MuxbusEventType type;
}

// Singleton WebSocket connection; connects on foreground, disconnects on background.
// Broadcasts MuxbusEvent to all listeners.
class MuxbusSocket with WidgetsBindingObserver {
  MuxbusSocket(this._auth);

  final AuthRepository _auth;
  WebSocketChannel? _channel;
  final _controller = StreamController<MuxbusEvent>.broadcast();
  Timer? _pingTimer;
  bool _disposed = false;

  Stream<MuxbusEvent> get events => _controller.stream;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    _controller.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connect();
    } else if (state == AppLifecycleState.paused) {
      _disconnect();
    }
  }

  Future<void> _connect() async {
    if (_disposed || _channel != null) return;
    try {
      final token = await _auth.getValidIdToken();
      // No path suffix -- the ApiMapping for muxbus-ws.agentmux.ai has no
      // apiMappingKey, so the client connects at the domain root (matches
      // the desktop client, fixed for the same reason in agentmux#1955; see
      // muxbus-websocket.ts's own comment on this). A stray "/ws" here
      // silently failed every handshake (DOC-001, 2026-07-29 documentation
      // analyst).
      final uri = Uri.parse(_wsBase);
      // The token must go in the Authorization header -- ws-connect.ts's
      // $connect handler reads event.headers["authorization"], not the
      // Sec-WebSocket-Protocol header WebSocketChannel.connect's `protocols`
      // param would have set. IOWebSocketChannel (dart:io-backed, fine here
      // since this app has no web target) is what actually supports custom
      // handshake headers; the cross-platform WebSocketChannel.connect
      // factory does not.
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnect,
        onError: (_) => _onDisconnect(),
        cancelOnError: true,
      );

      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _channel?.sink.add(json.encode({'type': 'ping'}));
      });
    } catch (_) {
      // Auth failure or network error — retry on next foreground.
    }
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _onDisconnect() {
    _channel = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    // Reconnect after backoff when still in foreground.
    if (!_disposed) {
      Future.delayed(const Duration(seconds: 5), _connect);
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = json.decode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      if (type == 'inject_available') {
        _controller.add(const MuxbusEvent(MuxbusEventType.injectAvailable));
      }
    } catch (_) {}
  }
}
