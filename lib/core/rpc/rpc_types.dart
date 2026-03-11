/// Connection state for the RPC client.
enum RpcConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// A single RPC message on the wire.
class RpcMessage {
  final String command;
  final String reqId;
  final dynamic data;

  RpcMessage({
    required this.command,
    required this.reqId,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'command': command,
        if (reqId.isNotEmpty) 'reqid': reqId,
        if (data != null) 'data': data,
      };
}
