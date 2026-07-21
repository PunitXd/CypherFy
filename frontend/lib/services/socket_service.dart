import 'package:socket_io_client/socket_io_client.dart' as io;

/// Thin wrapper around socket_io_client.
///
/// Owns a single connection for the app's lifetime. Account users pass their
/// access token in the handshake auth; guests connect anonymously. Screens
/// subscribe to server events via [on] and emit client events via [emit].
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  /// This client's own socket id (null until connected). Used to ignore
  /// self-referential signalling in group calls.
  String? get id => _socket?.id;

  /// Connect (or reconnect) to the server. Safe to call repeatedly — an
  /// existing connection is torn down first so the auth token stays current.
  void connect(String url, {String? accessToken}) {
    disconnect();

    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth(accessToken != null ? {'token': accessToken} : {})
          .build(),
    );

    _socket!
      ..onConnect((_) => print('Socket connected: ${_socket!.id}'))
      ..onDisconnect((_) => print('Socket disconnected'))
      ..onConnectError((e) => print('Socket connect error: $e'))
      ..connect();
  }

  /// Listen for a server → client event.
  void on(String event, void Function(dynamic data) handler) {
    _socket?.on(event, handler);
  }

  /// Run [handler] every time the socket connects — including automatic
  /// reconnects. Use this to (re)join rooms so membership survives a drop.
  void onConnect(void Function() handler) {
    _socket?.onConnect((_) => handler());
  }

  /// Remove a specific listener (or all listeners for an event).
  void off(String event, [dynamic Function(dynamic)? handler]) {
    _socket?.off(event, handler);
  }

  /// Emit a client → server event, optionally with an acknowledgement callback.
  void emit(String event, [dynamic data, void Function(dynamic ack)? ack]) {
    if (ack != null) {
      _socket?.emitWithAck(event, data ?? {}, ack: ack);
    } else {
      _socket?.emit(event, data ?? {});
    }
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
