import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal AppSync GraphQL subscription client.
///
/// Hand-rolled instead of pulling in the full Amplify stack because
/// we only need ONE subscription (`onInspectionsForJockey`) and the
/// Amplify Dart packages drag in code-gen + auth categories we don't
/// otherwise use.
///
/// AppSync's WebSocket subprotocol (pure WS, not MQTT — the latter is
/// the older variant) requires:
///   1. Connect to `wss://{realtime-host}/graphql` with two
///      query params:
///        - `header`  : base64 of `{ host, x-api-key }`
///        - `payload` : base64 of `{}`  (subscription auth payload)
///      and the `Sec-WebSocket-Protocol: graphql-ws` subprotocol.
///   2. Send `{ type: "connection_init" }`.
///   3. Receive `{ type: "connection_ack" }`.
///   4. Send a `start` message per subscription:
///        {
///          id: "{uuid}",
///          type: "start",
///          payload: {
///            data: "{JSON string of query+variables}",
///            extensions: {
///              authorization: { host, "x-api-key" }
///            }
///          }
///        }
///   5. Receive `{ id, type: "data", payload: { data: {...} } }`
///      every time the publisher fires the matching mutation.
///   6. Send `{ id, type: "stop" }` to unsubscribe.
class AppsyncSubscription {
  AppsyncSubscription._(this._channel, this._sink, this._stream);

  final WebSocketChannel _channel;
  final Sink<dynamic> _sink;
  final Stream<dynamic> _stream;

  final Map<String, _Sub<dynamic>> _subs = {};
  bool _connected = false;
  Completer<void>? _ackCompleter;
  StreamSubscription<dynamic>? _wsSub;

  /// Opens a single shared WebSocket to AppSync. Subscriptions added
  /// via [subscribe] multiplex over this connection — one socket per
  /// app session, not one per stream.
  static Future<AppsyncSubscription> connect() async {
    final httpsUrl = dotenv.env['APPSYNC_HTTPS_URL'];
    final apiKey = dotenv.env['APPSYNC_API_KEY'];
    if (httpsUrl == null || apiKey == null) {
      throw StateError(
        'APPSYNC_HTTPS_URL / APPSYNC_API_KEY missing from .env',
      );
    }
    final host = Uri.parse(httpsUrl).host;
    final realtimeHost =
        host.replaceFirst('appsync-api', 'appsync-realtime-api');

    final header = base64UrlEncode(utf8.encode(jsonEncode({
      'host': host,
      'x-api-key': apiKey,
    })));
    final payload = base64UrlEncode(utf8.encode('{}'));

    final wsUrl = Uri.parse(
      'wss://$realtimeHost/graphql?header=$header&payload=$payload',
    );

    final channel = WebSocketChannel.connect(
      wsUrl,
      protocols: const ['graphql-ws'],
    );

    final stream = channel.stream.asBroadcastStream();
    final self = AppsyncSubscription._(channel, channel.sink, stream);
    await self._init();
    return self;
  }

  Future<void> _init() async {
    _ackCompleter = Completer<void>();
    _wsSub = _stream.listen(
      _onMessage,
      onError: (e, st) {
        debugPrint('[appsync] socket error: $e');
        _closeAllSubs(error: e);
      },
      onDone: () {
        debugPrint('[appsync] socket closed');
        _closeAllSubs();
      },
    );
    _sink.add(jsonEncode({'type': 'connection_init'}));
    // 8s ceiling — AppSync usually acks within a few hundred ms.
    await _ackCompleter!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('AppSync connection_ack timeout'),
    );
    _connected = true;
  }

  /// Subscribes to a GraphQL subscription. The returned stream emits
  /// the `data` field of each incoming event; close it (via
  /// `.cancel()`) to unsubscribe and free the AppSync slot.
  ///
  /// [operation] is the full subscription document
  /// (`subscription { … }`), [variables] is the JSON-encodable args
  /// object.
  Stream<Map<String, dynamic>> subscribe({
    required String operation,
    Map<String, dynamic> variables = const {},
  }) {
    if (!_connected) {
      return Stream.error(StateError('Subscribe before connect()'));
    }
    final id = _nextId();
    final controller = StreamController<Map<String, dynamic>>.broadcast(
      onCancel: () => _stop(id),
    );
    _subs[id] = _Sub<Map<String, dynamic>>(controller);

    final host = Uri.parse(dotenv.env['APPSYNC_HTTPS_URL']!).host;
    final apiKey = dotenv.env['APPSYNC_API_KEY']!;
    _sink.add(jsonEncode({
      'id': id,
      'type': 'start',
      'payload': {
        'data': jsonEncode({
          'query': operation,
          'variables': variables,
        }),
        'extensions': {
          'authorization': {
            'host': host,
            'x-api-key': apiKey,
          },
        },
      },
    }));
    return controller.stream;
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['type'] as String?;
    switch (type) {
      case 'connection_ack':
        _ackCompleter?.complete();
        _ackCompleter = null;
        break;
      case 'data':
        final id = msg['id'] as String?;
        final sub = id == null ? null : _subs[id];
        final data = (msg['payload'] as Map?)?['data'];
        if (sub != null && data is Map<String, dynamic>) {
          sub.controller.add(data);
        }
        break;
      case 'error':
      case 'connection_error':
        // Surface to subscribers too — silently swallowing means callers
        // think the stream is healthy when AppSync rejected the start
        // (auth, schema, filter). 'error' carries an id, 'connection_error'
        // doesn't.
        final id = msg['id'] as String?;
        debugPrint('[appsync] $type id=$id payload=${msg['payload']}');
        if (id != null) {
          _subs[id]?.controller.addError(
                StateError('AppSync error: ${msg['payload']}'),
              );
        }
        break;
      case 'complete':
        final id = msg['id'] as String?;
        if (id != null) _subs.remove(id)?.controller.close();
        break;
      case 'ka': // keep-alive ping
      default:
        break;
    }
  }

  void _stop(String id) {
    final sub = _subs.remove(id);
    if (sub == null) return;
    try {
      _sink.add(jsonEncode({'id': id, 'type': 'stop'}));
    } catch (_) {/* socket likely already closed */}
    sub.controller.close();
  }

  void _closeAllSubs({Object? error}) {
    for (final sub in _subs.values) {
      if (error != null) {
        sub.controller.addError(error);
      }
      sub.controller.close();
    }
    _subs.clear();
  }

  /// Closes the underlying socket — call from a top-level dispose
  /// (logout, app shutdown). Active subscriptions emit `done`.
  Future<void> dispose() async {
    _closeAllSubs();
    await _wsSub?.cancel();
    await _channel.sink.close();
  }

  int _idCounter = 0;
  String _nextId() => 'sub_${++_idCounter}';
}

class _Sub<T> {
  final StreamController<T> controller;
  _Sub(this.controller);
}
