import 'dart:convert';
import 'dart:io';

import 'package:ip_tv_playlist/m3u/m3u_helper.dart';
import 'package:postgres/postgres.dart';

import 'channel.dart';
import 'm3u/m3u_entry.dart';

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

  Future<void> refreshChannels([
    List<M3uEntry> m3uEntries = const <M3uEntry>[],
  ]) async {
    await _connection.execute(
        'TRUNCATE public.channel_group, public.channel RESTART IDENTITY');

    final File initDataFile = File('assets/init_data.json');
    final Map<String, dynamic> initDataJson =
        jsonDecode(initDataFile.readAsStringSync());

    _extendChannelsDataJson(initDataJson['channels'], m3uEntries);

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

  void _extendChannelsDataJson(
    List<dynamic> channelsInitData,
    List<M3uEntry> m3uEntries,
  ) {
    final Set<M3uEntry> usedM3uEntries = <M3uEntry>{};

    for (final Map<String, dynamic> channelInitData in channelsInitData) {
      final String name = channelInitData['name'];
      final String namePattern = channelInitData['namePattern'];

      if (namePattern.isEmpty) {
        continue;
      }

      final RegExp nameRegExp = RegExp(
        namePattern,
        caseSensitive: false,
      );

      final List<M3uEntry> equalM3uEntries = m3uEntries.where(
        (M3uEntry m3uEntry) {
          String? m3uEntryInformation = m3uEntry.information;
          return m3uEntryInformation != null &&
              nameRegExp.hasMatch(m3uEntryInformation);
        },
      ).toList();

      final List<String> additionalSourceUrls = equalM3uEntries
          .map((M3uEntry m3uEntry) => m3uEntry.sourceUrl)
          .toSet()
          .toList();

      channelInitData['sourceUrls'] = <String>{
        ...additionalSourceUrls,
        ...channelInitData['sourceUrls']
      }.toList();

      usedM3uEntries.addAll(equalM3uEntries);

      if (additionalSourceUrls.isNotEmpty) {
        print(
            'Channel "$name" extended with: ${additionalSourceUrls.join(', ')}');
      }
    }

    final List<M3uEntry> unusedM3uEntries = m3uEntries
        .toSet()
        .difference(usedM3uEntries)
        .where((M3uEntry unusedM3uEntry) =>
            channelsInitData.every((dynamic channelInitData) {
              final List<String> sourceUrls =
                  List.castFrom(channelInitData['sourceUrls']);
              return !sourceUrls.contains(unusedM3uEntry.sourceUrl);
            }))
        .toList();

    for (final M3uEntry m3uEntry in unusedM3uEntries) {
      channelsInitData.add(<String, dynamic>{
        "name": M3uHelper.extractChannelName(m3uEntry.information ?? ''),
        "logoUrl": "",
        "channelGroupId": "9",
        "namePattern": "",
        "sourceUrls": [m3uEntry.sourceUrl]
      });
    }
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
        httpClient.connectionTimeout = const Duration(seconds: 10);
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
