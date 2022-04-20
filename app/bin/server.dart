import 'dart:io';

import 'package:ip_tv_playlist/channel.dart';
import 'package:ip_tv_playlist/database.dart';
import 'package:ip_tv_playlist/m3u_builder.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

final String dbHost = Platform.environment['DB_HOST'] ?? '127.0.0.1';
final int dbPort = int.parse(Platform.environment['DB_PORT'] ?? '5432');
final String dbName = Platform.environment['DB_NAME'] ?? 'test';
final String dbUser = Platform.environment['DB_USER'] ?? 'admin';
final String dbPassword = Platform.environment['DB_PASS'] ?? 'admin';

final _router = Router()
  ..get('/ip_tv_playlist.m3u', _getIpTvPlaylistHandler)
  ..post('/refresh_channels', _refreshChannelsHandler);

Future<Response> _getIpTvPlaylistHandler(Request req) async {
  final Database database = await Database.connect(
    dbHost,
    dbPort,
    dbName,
    username: dbUser,
    password: dbPassword,
  );

  final List<Channel> channels = await database.getChannels();
  return Response.ok(M3UBuilder.build(channels));
}

Future<Response> _refreshChannelsHandler(Request req) async {
  final Database database = await Database.connect(
    dbHost,
    dbPort,
    dbName,
    username: dbUser,
    password: dbPassword,
  );

  await database.refreshChannels();

  return Response.ok('Succeeded');
}

void main(List<String> args) async {
  final InternetAddress ip = InternetAddress.anyIPv4;
  final handler = Pipeline().addMiddleware(logRequests()).addHandler(_router);
  final int port = int.parse(Platform.environment['PORT'] ?? '80');
  final HttpServer server = await serve(handler, ip, port);

  print('Server listening on port ${server.port}');
}
