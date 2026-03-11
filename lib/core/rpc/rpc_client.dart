import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'rpc_types.dart';

/// WebSocket RPC client that speaks the agentmuxsrv-rs protocol.
///
/// This mirrors the desktop frontend's WshRpcEngine — same command names,
/// same JSON wire format, same event subscription model.
class AgentMuxRpcClient {
  WebSocketChannel? _channel;
  final Map<String, Completer<dynamic>> _pendingRequests = {};
  final Map<String, StreamController<dynamic>> _eventControllers = {};
  final StreamController<RpcConnectionState> _connectionState =
      StreamController<RpcConnectionState>.broadcast();
  int _nextReqId = 1;
  Timer? _pingTimer;

  /// Stream of connection state changes.
  Stream<RpcConnectionState> get connectionState => _connectionState.stream;

  /// Connect to an agentmuxsrv-rs backend.
  Future<void> connect(String host, int port, String authKey,
      {bool useTls = false}) async {
    final scheme = useTls ? 'wss' : 'ws';
    final uri = Uri.parse(
        '$scheme://$host:$port/ws?authkey=${Uri.encodeComponent(authKey)}');

    _connectionState.add(RpcConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _connectionState.add(RpcConnectionState.connected);
      _startPingTimer();
      _listenForMessages();
    } catch (e) {
      _connectionState.add(RpcConnectionState.error);
      rethrow;
    }
  }

  /// Disconnect from the backend.
  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connectionState.add(RpcConnectionState.disconnected);

    // Fail all pending requests.
    for (final completer in _pendingRequests.values) {
      completer.completeError(RpcDisconnectedException());
    }
    _pendingRequests.clear();

    // Close all event streams.
    for (final controller in _eventControllers.values) {
      controller.close();
    }
    _eventControllers.clear();
  }

  /// Send an RPC command and await the response.
  Future<T> call<T>(String command, [dynamic data]) async {
    _ensureConnected();
    final reqId = 'req-${_nextReqId++}';
    final completer = Completer<T>();
    _pendingRequests[reqId] = completer;

    _send(RpcMessage(
      command: command,
      reqId: reqId,
      data: data,
    ));

    return completer.future;
  }

  /// Send a fire-and-forget command (no response expected).
  void fireAndForget(String command, [dynamic data]) {
    _ensureConnected();
    _send(RpcMessage(
      command: command,
      reqId: '',
      data: data,
    ));
  }

  /// Subscribe to backend events. Returns a broadcast stream.
  Stream<dynamic> subscribe(String eventType, {List<String>? scopes}) {
    final controller =
        StreamController<dynamic>.broadcast(onCancel: () {
      _eventControllers.remove(eventType);
      // Unsubscribe on the backend.
      fireAndForget('eventunsub', {'event': eventType});
    });

    _eventControllers[eventType] = controller;

    // Send subscription request to backend.
    fireAndForget('eventsub', {
      'event': eventType,
      if (scopes != null) 'scopes': scopes,
    });

    return controller.stream;
  }

  /// Send terminal input to a block's PTY.
  void sendTerminalInput(String blockId, Uint8List data) {
    fireAndForget('controllerinput', {
      'blockid': blockId,
      'inputdata': {'inputdata': base64Encode(data)},
    });
  }

  /// Send terminal resize to a block's PTY.
  void sendTerminalResize(String blockId, int rows, int cols) {
    fireAndForget('controllerinput', {
      'blockid': blockId,
      'inputdata': {
        'signame': 'SIGWINCH',
        'termsize': {'rows': rows, 'cols': cols},
      },
    });
  }

  /// Resync a block controller (reconnect to existing PTY).
  Future<void> controllerResync(String blockId) async {
    await call('controllerresync', {'blockid': blockId});
  }

  // -- Convenience methods for common RPC calls --

  /// Get the full backend config (settings, widgets, presets).
  Future<Map<String, dynamic>> getFullConfig() async {
    return await call<Map<String, dynamic>>('getfullconfig');
  }

  /// Update a setting on the backend.
  Future<void> setConfig(Map<String, dynamic> settings) async {
    await call('setconfig', settings);
  }

  /// Get a Wave object by ORef (e.g., "block:uuid", "tab:uuid").
  Future<Map<String, dynamic>> getObject(String oref) async {
    return await call<Map<String, dynamic>>('object.GetObject', oref);
  }

  /// Create a new block.
  Future<Map<String, dynamic>> createBlock(Map<String, dynamic> blockDef,
      {Map<String, dynamic>? uiContext}) async {
    return await call<Map<String, dynamic>>('object.CreateBlock', {
      'blockdef': blockDef,
      if (uiContext != null) 'uicontext': uiContext,
    });
  }

  /// List workspaces.
  Future<List<dynamic>> listWorkspaces() async {
    return await call<List<dynamic>>('workspace.ListWorkspaces');
  }

  /// Get AI chat history for a block.
  Future<List<dynamic>> getAiChat(String blockId) async {
    return await call<List<dynamic>>('getwaveaichat', blockId);
  }

  /// Send an AI message (returns immediately; responses come via events).
  Future<void> sendAiMessage(Map<String, dynamic> messageData) async {
    await call('aisendmessage', messageData);
  }

  /// Approve an AI tool execution.
  Future<void> approveAiTool(String blockId) async {
    await call('waveaitoolapprove', blockId);
  }

  // -- Internal --

  void _ensureConnected() {
    if (_channel == null) {
      throw RpcDisconnectedException();
    }
  }

  void _send(RpcMessage message) {
    _channel?.sink.add(jsonEncode(message.toJson()));
  }

  void _listenForMessages() {
    _channel?.stream.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        _handleMessage(json);
      },
      onError: (error) {
        _connectionState.add(RpcConnectionState.error);
        disconnect();
      },
      onDone: () {
        _connectionState.add(RpcConnectionState.disconnected);
        disconnect();
      },
    );
  }

  void _handleMessage(Map<String, dynamic> json) {
    final reqId = json['reqid'] as String? ?? '';
    final command = json['command'] as String? ?? '';

    // Response to a pending request.
    if (reqId.isNotEmpty && _pendingRequests.containsKey(reqId)) {
      final completer = _pendingRequests.remove(reqId)!;
      if (json.containsKey('error')) {
        completer.completeError(
            RpcErrorException(json['error'] as String? ?? 'Unknown error'));
      } else {
        completer.complete(json['data']);
      }
      return;
    }

    // Event message.
    if (command == 'eventrecv') {
      final eventType = json['data']?['event'] as String? ?? '';
      _eventControllers[eventType]?.add(json['data']);
      return;
    }

    // Pong — ignore.
    if (command == 'pong') return;
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fireAndForget('ping');
    });
  }

  void dispose() {
    disconnect();
    _connectionState.close();
  }
}

class RpcDisconnectedException implements Exception {
  @override
  String toString() => 'RPC client is not connected';
}

class RpcErrorException implements Exception {
  final String message;
  RpcErrorException(this.message);

  @override
  String toString() => 'RPC error: $message';
}
