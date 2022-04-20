import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

import 'channel.dart';

class Database {
  static const String _sourceIsUnreachableUrl =
      'https://user-images.githubusercontent.com/15068331/163717494-6cf6b0fe-6264-4d6d-99d7-97bf27bfb925.mp4';

  late PostgreSQLConnection _connection;

  static Future<Database> connect(
    String host,
    int port,
    String databaseName, {
    String? username,
    String? password,
  }) async {
    Database db = Database._();
    db._connection = PostgreSQLConnection(
      host,
      port,
      databaseName,
      username: username,
      password: password,
    );
    await db._connection.open();
    await db._initTables();

    return db;
  }

  Database._();

  Future<List<Channel>> getChannels() async {
    try {
      final PostgreSQLResult channelsResult = await _connection.query('''
        SELECT channel.name, source_url, logo_url, channel_group.id_channel_group, channel_group.name
        FROM public.channel
        LEFT JOIN public.channel_group ON channel.id_channel_group = channel_group.id_channel_group
		    ORDER BY id_channel
        ''');

      return channelsResult
          .map((e) => Channel(e[0], e[1], e[2], e[3], e[4]))
          .toList();
    } catch (e, s) {
      print('Exception $e');
      print('StackTrace $s');
      return [];
    }
  }

  Future<void> refreshChannels() async {
    await _connection.execute(
        'TRUNCATE public.channel_group, public.channel RESTART IDENTITY');

    final File initDataFile = File('assets/init_data.json');
    final Map<String, dynamic> initDataJson =
        jsonDecode(initDataFile.readAsStringSync());

    await _fillChannelGroups(initDataJson['channel_groups']);
    await _fillChannels(initDataJson['channels']);
  }

  Future<void> _initTables() async {
    await _initChannelGroupTable();
    await _initChannelTable();
    if (await _isEmpty()) {
      await refreshChannels();
    }
  }

  Future<void> _initChannelGroupTable() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS public.channel_group
      (
          id_channel_group SERIAL,
          name text COLLATE pg_catalog."default" NOT NULL,
          CONSTRAINT channel_group_pkey PRIMARY KEY (id_channel_group)
      )''');
  }

  Future<void> _initChannelTable() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS public.channel
      (
          id_channel SERIAL,
          name text COLLATE pg_catalog."default" NOT NULL,
          source_url text COLLATE pg_catalog."default" NOT NULL,
          logo_url text COLLATE pg_catalog."default" NOT NULL,
          id_channel_group integer NOT NULL,
          CONSTRAINT channel_pkey PRIMARY KEY (id_channel),
          CONSTRAINT channel_id_channel_group_fkey FOREIGN KEY (id_channel_group)
              REFERENCES public.channel_group (id_channel_group) MATCH SIMPLE
              ON UPDATE NO ACTION
              ON DELETE NO ACTION
      )''');
  }

  Future<bool> _isEmpty() async {
    final PostgreSQLResult channelCountResult =
        await _connection.query('SELECT COUNT(*) FROM public.channel');
    final PostgreSQLResultRow channelCountRow = channelCountResult.single;
    final int channelCount = channelCountRow[0];

    return channelCount == 0;
  }

  Future<void> _fillChannelGroups(List<dynamic> channelGroupsInitData) async {
    for (Map<String, dynamic> channelGroupInitData in channelGroupsInitData) {
      await _connection.execute(
        '''INSERT INTO public.channel_group(id_channel_group, name) VALUES (@id, @name)''',
        substitutionValues: {
          'id': channelGroupInitData['id'],
          'name': channelGroupInitData['name'],
        },
      );
    }
  }

  Future<void> _fillChannels(List<dynamic> channelsInitData) async {
    for (int i = 0; i < channelsInitData.length; ++i) {
      final int id = i + 1;
      final Map<String, dynamic> channelInitData = channelsInitData[i];

      final List<dynamic> sourceUrls = channelInitData['sourceUrls'];

      if (sourceUrls.isEmpty) {
        continue;
      }

      String? validSourceUrl;

      for (final String sourceUrl in sourceUrls) {
        final HttpClient httpClient = HttpClient();
        try {
          final Uri uri = Uri.parse(sourceUrl);
          final HttpClientRequest httpClientRequest =
              await httpClient.getUrl(uri);
          final HttpClientResponse httpClientResponse =
              await httpClientRequest.close();
          final int statusCode = httpClientResponse.statusCode;
          if (statusCode != 200) {
            throw 'StatusCode $statusCode';
          }
          validSourceUrl = sourceUrl;
          break;
        } catch (e, s) {
          print('Invalid url: $sourceUrl');
          print('Exception $e');
          print('StackTrace $s');
        }
      }

      await _connection.execute(
        '''
      INSERT INTO public.channel(
        id_channel,
        name,
        source_url,
        logo_url,
        id_channel_group
      ) VALUES (
        @id,
        @name,
        @sourceUrl,
        @logoUrl,
        @channelGroupId
      )''',
        substitutionValues: {
          'id': id,
          'name': channelInitData['name'],
          'sourceUrl': validSourceUrl ?? _sourceIsUnreachableUrl,
          'logoUrl': channelInitData['logoUrl'],
          'channelGroupId': channelInitData['channelGroupId'],
        },
      );
    }
  }
}
