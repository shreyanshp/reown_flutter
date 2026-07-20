import 'dart:async';

import 'package:reown_core/models/basic_models.dart';
import 'package:reown_core/relay_client/websocket/i_websocket_handler.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketHandler implements IWebSocketHandler {
  String? _url;
  @override
  String? get url => _url;

  WebSocketChannel? _socket;

  @override
  int? get closeCode => _socket?.closeCode;
  @override
  String? get closeReason => _socket?.closeReason;

  StreamChannel<String>? _channel;
  @override
  StreamChannel<String>? get channel => _channel;

  StreamController<String>? _inputController;
  StreamController<String>? _outputController;
  StreamSubscription<String>? _socketSub;

  @override
  Future<void> setup({required String url}) async {
    _url = url;

    await close();
  }

  @override
  Future<void> connect() async {
    // print('connecting');
    try {
      _socket = WebSocketChannel.connect(
        Uri.parse('$url&useOnCloseEvent=true'),
      );
    } catch (e) {
      throw ReownCoreError(
        code: -1,
        message: 'No internet connection: ${e.toString()}',
      );
    }

    // Create a multi-subscription capable stream channel using stream splitting
    // This approach enables multiple listeners without broadcast streams
    _inputController = StreamController<String>.broadcast(sync: true);
    _outputController = StreamController<String>.broadcast(sync: true);

    // Split the incoming stream to support multiple listeners.
    // Guard every add against a closed/closing controller and keep the
    // subscription so close() can cancel the source — otherwise a socket event
    // arriving during/after close() hits an add-after-close and throws
    // "Bad state: Cannot add event after closing".
    _socketSub = _socket!.stream.cast<String>().listen(
      (data) {
        final c = _inputController;
        if (c != null && !c.isClosed) c.add(data);
      },
      onError: (error) {
        final c = _inputController;
        if (c != null && !c.isClosed) c.addError(error);
      },
      onDone: () {
        final c = _inputController;
        if (c != null && !c.isClosed) c.close();
      },
    );

    // Route outgoing messages through the output controller. The underlying
    // socket sink is a web_socket_channel _GuaranteeSink that may already be
    // closed when a queued message is delivered here, so add/addError/close are
    // wrapped — an add-after-close would otherwise crash.
    _outputController!.stream.listen(
      (data) {
        try {
          _socket?.sink.add(data);
        } catch (_) {}
      },
      onError: (error) {
        try {
          _socket?.sink.addError(error);
        } catch (_) {}
      },
      onDone: () {
        try {
          _socket?.sink.close();
        } catch (_) {}
      },
    );

    _channel = StreamChannel(_inputController!.stream, _outputController!.sink);

    if (_channel == null) {
      // print('Socket channel is null, waiting...');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_channel == null) {
        // print('Socket channel is still null, throwing ');
        throw Exception('Socket channel is null');
      }
    }

    await _socket?.ready;

    // Check if the request was successful (status code 200)
    // try {} catch (e) {
    //   throw ReownCoreError(
    //     code: 400,
    //     message: 'WebSocket connection failed, missing or invalid project id.',
    //   );
    // }
  }

  @override
  Future<void> close() async {
    // Cancel the socket subscription BEFORE closing controllers so no inbound
    // event can fire an add-after-close during teardown.
    try {
      await _socketSub?.cancel();
    } catch (_) {}
    _socketSub = null;

    try {
      await _socket?.sink.close();
    } catch (_) {}

    // Close the controllers to prevent further messages and race conditions
    try {
      await _inputController?.close();
    } catch (_) {}
    try {
      await _outputController?.close();
    } catch (_) {}

    _inputController = null;
    _outputController = null;
    _channel = null;
    _socket = null;
  }

  @override
  String toString() {
    return 'WebSocketHandler{url: $url, _socket: $_socket, _channel: $_channel}';
  }
}
