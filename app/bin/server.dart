import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ip_tv_playlist/channel.dart';
import 'package:ip_tv_playlist/database.dart';
import 'package:ip_tv_playlist/m3u/m3u_helper.dart';
import 'package:ip_tv_playlist/m3u/m3u_builder.dart';
import 'package:ip_tv_playlist/m3u/m3u_filter.dart';
import 'package:ip_tv_playlist/m3u/m3u_entry.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

final String dbHost = Platform.environment['DB_HOST'] ?? '127.0.0.1';
final int dbPort = int.parse(Platform.environment['DB_PORT'] ?? '5432');
final String dbName = Platform.environment['DB_NAME'] ?? 'test';
final String dbUser = Platform.environment['DB_USER'] ?? 'admin';
final String dbPassword = Platform.environment['DB_PASS'] ?? 'admin';

class _FilterRequest {
  final List<String> playlistUrls;
  final List<String> namesToRemove;
  final List<String> groupsToRemove;
  final List<String> sourceUrlsToRemove;
  final String minResolutionWidth;
  final String minResolutionHeight;

  _FilterRequest(Uri uri)
      : playlistUrls = uri.queryParametersAll['playlist_urls[]'] ?? <String>[],
        namesToRemove =
            uri.queryParametersAll['names_to_remove[]'] ?? <String>[],
        groupsToRemove =
            uri.queryParametersAll['groups_to_remove[]'] ?? <String>[],
        sourceUrlsToRemove =
            uri.queryParametersAll['source_urls_to_remove[]'] ?? <String>[],
        minResolutionWidth = uri.queryParameters['min_resolution_width'] ?? '',
        minResolutionHeight =
            uri.queryParameters['min_resolution_height'] ?? '';
}

final Router _router = Router()
  ..get('/ip_tv_playlist.m3u', _getIpTvPlaylistHandler)
  ..post('/refresh_channels', _refreshChannelsHandler)
  ..get('/filter_playlist', _filterPlaylistHandler);

Future<Response> _getIpTvPlaylistHandler(Request req) async {
  final Database database = await Database.connect(
    dbHost,
    dbPort,
    dbName,
    username: dbUser,
    password: dbPassword,
  );

  final List<Channel> channels = await database.getChannels();
  final String playlist = M3uBuilder.build(channels);

  return Response.ok(playlist);
}

Future<Response> _refreshChannelsHandler(Request req) async {
  String filteredPlaylist = '';

  if (req.url.queryParameters.containsKey('playlist_urls[]')) {
    final _FilterRequest filterRequest = _FilterRequest(req.url);

    List<String> playlistUrls = filterRequest.playlistUrls;

    final List<RegExp> namesToRemove = filterRequest.namesToRemove
        .map((String nameToRemove) => RegExp(nameToRemove))
        .toList();

    final List<RegExp> groupsToRemove = filterRequest.groupsToRemove
        .map((String groupToRemove) => RegExp(groupToRemove))
        .toList();

    final List<RegExp> sourceUrlsToRemove = filterRequest.sourceUrlsToRemove
        .map((String sourceUrlToRemove) => RegExp(sourceUrlToRemove))
        .toList();

    final int? minResolutionWidth =
        int.tryParse(filterRequest.minResolutionWidth);

    final int? minResolutionHeight =
        int.tryParse(filterRequest.minResolutionHeight);

    List<String> playlists = <String>[];

    for (final String playlistUrl in playlistUrls) {
      try {
        String playlist = await _fetch(playlistUrl);
        playlists.add(playlist);
      } catch (e, s) {
        print('Invalid url: $playlistUrl');
        print('Exception $e');
        print('StackTrace $s');
      }
    }

    String mergedPlaylist = M3uHelper.mergePlaylists(playlists);

    final M3uFilter m3uFilter = M3uFilter(
      namesToRemove: namesToRemove,
      groupsToRemove: groupsToRemove,
      sourceUrlsToRemove: sourceUrlsToRemove,
      minResolutionWidth: minResolutionWidth,
      minResolutionHeight: minResolutionHeight,
    );
    filteredPlaylist = await m3uFilter.filter(mergedPlaylist);
  }

  final List<List<String>> channels = M3uHelper.splitChannels(filteredPlaylist);
  final List<M3uEntry> m3uEntries = channels.map(M3uEntry.fromLines).toList();

  final Database database = await Database.connect(
    dbHost,
    dbPort,
    dbName,
    username: dbUser,
    password: dbPassword,
  );

  await database.refreshChannels(m3uEntries);

  return Response.ok('Succeeded');
}

Future<Response> _filterPlaylistHandler(Request req) async {
  if (!req.url.queryParameters.containsKey('playlist_urls[]')) {
    return Response.badRequest(body: 'playlist_urls[] is required');
  }
  final _FilterRequest filterRequest = _FilterRequest(req.url);

  List<String> playlistUrls = filterRequest.playlistUrls;

  final List<RegExp> namesToRemove = filterRequest.namesToRemove
      .map((String nameToRemove) => RegExp(nameToRemove))
      .toList();

  final List<RegExp> groupsToRemove = filterRequest.groupsToRemove
      .map((String groupToRemove) => RegExp(groupToRemove))
      .toList();

  final List<RegExp> sourceUrlsToRemove = filterRequest.sourceUrlsToRemove
      .map((String sourceUrlToRemove) => RegExp(sourceUrlToRemove))
      .toList();

  final int? minResolutionWidth =
      int.tryParse(filterRequest.minResolutionWidth);

  final int? minResolutionHeight =
      int.tryParse(filterRequest.minResolutionHeight);

  List<String> playlists = <String>[];

  for (final String playlistUrl in playlistUrls) {
    try {
      String playlist = await _fetch(playlistUrl);
      playlists.add(playlist);
    } catch (e, s) {
      print('Invalid url: $playlistUrl');
      print('Exception $e');
      print('StackTrace $s');
    }
  }

  String mergedPlaylist = M3uHelper.mergePlaylists(playlists);

  final M3uFilter m3uFilter = M3uFilter(
    namesToRemove: namesToRemove,
    groupsToRemove: groupsToRemove,
    sourceUrlsToRemove: sourceUrlsToRemove,
    minResolutionWidth: minResolutionWidth,
    minResolutionHeight: minResolutionHeight,
  );
  final String filteredPlaylist = await m3uFilter.filter(mergedPlaylist);

  return Response.ok(filteredPlaylist);
}

Future<String> _fetch(String url) async {
  final Uri uri = Uri.parse(url);
  final HttpClientRequest httpClientRequest = await HttpClient().getUrl(uri);
  final HttpClientResponse httpClientResponse = await httpClientRequest.close();

  final int statusCode = httpClientResponse.statusCode;
  if (statusCode != 200) {
    throw 'StatusCode $statusCode';
  }
  return await _readResponse(httpClientResponse);
}

Future<String> _readResponse(Stream<List<int>> response) {
  final Completer<String> completer = Completer<String>();
  final StringBuffer contents = StringBuffer();
  response.transform(utf8.decoder).listen(
        (String data) => contents.write(data),
        onDone: () => completer.complete(contents.toString()),
      );

  return completer.future;
}

void main(List<String> args) async {
  final InternetAddress ip = InternetAddress.anyIPv4;
  final handler = Pipeline().addMiddleware(logRequests()).addHandler(_router);
  final int port = int.parse(Platform.environment['PORT'] ?? '80');
  final HttpServer server = await serve(handler, ip, port);

  print('Server listening on port ${server.port}');
}
