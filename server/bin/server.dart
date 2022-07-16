import 'dart:io';

import 'package:redis/redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _clients = <WebSocketChannel>[];
late final RedisConnection _redisConnection;
late final Command _redisCommand;

late final RedisConnection _pubSubConnection;
late final Command _pubSubCommand;
late final PubSub _pubSub;

// Configure routes.
final _router = Router()
  ..get('/', _rootHandler)
  ..get('/ws', webSocketHandler(_webSocketHandler));

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

void _webSocketHandler(WebSocketChannel webSocket) {
  stdout.writeln('[CONNECTED]');

  _clients.add(webSocket);
  _redisCommand.send_object(['GET', 'counter']).then((value) {
    webSocket.sink.add(value.toString());
  });

  webSocket.stream.listen((message) async {
    stdout.writeln('[CHANNEL] $message');

    if (message == 'increment') {
      final newValue = await _redisCommand.send_object(['INCR', 'counter']);
      _redisCommand.send_object(['PUBLISH', 'counterUpdate', 'counter']);

      for (final client in _clients) {
        client.sink.add(newValue.toString());
      }
    }
  }, onDone: () {
    _clients.remove(webSocket);
  });
}

void main(List<String> args) async {
  _redisConnection = RedisConnection();
  _redisCommand = await _redisConnection.connect('localhost', 8080);

  _pubSubConnection = RedisConnection();
  _pubSubCommand = await _pubSubConnection.connect('localhost', 8080);
  _pubSub = PubSub(_pubSubCommand);
  _pubSub.subscribe(['counterUpdate']);

  _pubSub.getStream().handleError((e) => stderr.writeln('error $e')).listen(
    (message) async {
      stdout.writeln(message.toString());
      final newValue = _redisCommand.send_object(['GET', 'counter']);
      for (final client in _clients) {
        client.sink.add(newValue.toString());
      }
    },
  );

  final ip = InternetAddress.anyIPv4;
  final handler = Pipeline().addHandler(_router);

  final port = int.parse(Platform.environment['PORT'] ?? '6379');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
