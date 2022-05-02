import 'dart:async';
import 'dart:io';

import 'package:pool/pool.dart';

import 'm3u_helper.dart';
import 'm3u_entry.dart';
import '../stream_info.dart';

class M3uFilter {
  final List<RegExp> _namesToRemove;
  final List<RegExp> _groupsToRemove;
  final List<RegExp> _sourceUrlsToRemove;
  final int _minResolutionWidth;
  final int _minResolutionHeight;

  M3uFilter({
    List<RegExp>? namesToRemove,
    List<RegExp>? groupsToRemove,
    List<RegExp>? sourceUrlsToRemove,
    int? minResolutionWidth,
    int? minResolutionHeight,
  })  : _namesToRemove = namesToRemove ?? <RegExp>[],
        _groupsToRemove = groupsToRemove ?? <RegExp>[],
        _sourceUrlsToRemove = sourceUrlsToRemove ?? <RegExp>[],
        _minResolutionWidth = minResolutionWidth ?? 0,
        _minResolutionHeight = minResolutionHeight ?? 0;

  Future<String> filter(String m3uPlaylist) async {
    final List<List<String>> channels = M3uHelper.splitChannels(m3uPlaylist);
    final List<M3uEntry> m3uEntries = channels.map(M3uEntry.fromLines).toList();

    _filterEmptySourceUrls(m3uEntries);

    if (_namesToRemove.isNotEmpty) {
      _filterNames(m3uEntries);
    }

    if (_groupsToRemove.isNotEmpty) {
      _filterGroups(m3uEntries);
    }

    if (_sourceUrlsToRemove.isNotEmpty) {
      _filterSourceUrls(m3uEntries);
    }

    if (_minResolutionWidth != 0 || _minResolutionHeight != 0) {
      await _filterVideoStreamResolution(m3uEntries);
    }

    _filterDuplicates(m3uEntries);

    final StringBuffer stringBuffer = StringBuffer();
    stringBuffer.writeln('#EXTM3U');
    stringBuffer.write(m3uEntries.join('\n'));

    return stringBuffer.toString();
  }

  void _filterEmptySourceUrls(List<M3uEntry> m3uEntries) {
    int currentChannelIndex = 1;

    m3uEntries.removeWhere((M3uEntry m3uEntry) {
      final bool isEmptySourceUrl = m3uEntry.sourceUrl.isEmpty;
      if (isEmptySourceUrl) {
        print('Channel:');
        print(m3uEntry.toString());
        print('Removed due to empty source url');
      }

      print(
          'Filter by empty source url: $currentChannelIndex/${m3uEntries.length}');
      ++currentChannelIndex;

      return isEmptySourceUrl;
    });
  }

  void _filterNames(List<M3uEntry> m3uEntries) {
    int currentChannelIndex = 1;

    m3uEntries.removeWhere((M3uEntry m3uEntry) {
      final String name =
          M3uHelper.extractChannelName(m3uEntry.information ?? '');
      final bool isNameRestricted = name.isEmpty ||
          _namesToRemove.any(
            (RegExp nameToRemove) => nameToRemove.hasMatch(name),
          );

      if (isNameRestricted) {
        final RegExp regExp = _namesToRemove.firstWhere(
          (RegExp nameToRemove) => nameToRemove.hasMatch(name),
        );

        print('Channel:');
        print(m3uEntry.toString());
        print(
            'Removed due to restricted name: ${m3uEntry.group}. RegExp: $regExp');
      }

      print('Filter by name: $currentChannelIndex/${m3uEntries.length}');
      ++currentChannelIndex;

      return isNameRestricted;
    });
  }

  void _filterGroups(List<M3uEntry> m3uEntries) {
    int currentChannelIndex = 1;

    m3uEntries.removeWhere((M3uEntry m3uEntry) {
      final bool isGroupRestricted = m3uEntry.group != null &&
          _groupsToRemove.any(
            (RegExp groupToRemove) => groupToRemove.hasMatch(m3uEntry.group!),
          );

      if (isGroupRestricted) {
        final RegExp regExp = _groupsToRemove.firstWhere(
          (RegExp groupToRemove) => groupToRemove.hasMatch(m3uEntry.group!),
        );

        print('Channel:');
        print(m3uEntry.toString());
        print(
            'Removed due to restricted group: ${m3uEntry.group}. RegExp: $regExp');
      }

      print('Filter by group: $currentChannelIndex/${m3uEntries.length}');
      ++currentChannelIndex;

      return isGroupRestricted;
    });
  }

  void _filterSourceUrls(List<M3uEntry> m3uEntries) {
    int currentChannelIndex = 1;

    m3uEntries.removeWhere((M3uEntry m3uEntry) {
      final bool isSourceUrlRestricted = _sourceUrlsToRemove.any(
        (RegExp sourceUrlToRemove) =>
            sourceUrlToRemove.hasMatch(m3uEntry.sourceUrl),
      );

      if (isSourceUrlRestricted) {
        final RegExp regExp = _sourceUrlsToRemove.firstWhere(
          (RegExp sourceUrlToRemove) =>
              sourceUrlToRemove.hasMatch(m3uEntry.sourceUrl),
        );

        print('Channel:');
        print(m3uEntry.toString());
        print(
            'Removed due to restricted source url: ${m3uEntry.sourceUrl}. RegExp: $regExp');
      }

      print('Filter by source url: $currentChannelIndex/${m3uEntries.length}');
      ++currentChannelIndex;

      return isSourceUrlRestricted;
    });
  }

  Future<void> _filterVideoStreamResolution(List<M3uEntry> m3uEntries) async {
    int currentChannelIndex = 1;

    List<String> sourceUrlsToRemove = <String>[];

    final Pool pool = Pool(Platform.numberOfProcessors * 2);

    await Future.wait(
      m3uEntries.map(
        (M3uEntry m3uEntry) => pool.withResource(
          () async {
            final StreamInfo streamInfo = StreamInfo(m3uEntry.sourceUrl);
            final List<Map<String, dynamic>> streamsInfo = await streamInfo
                .streamsInfo
                .timeout(Duration(minutes: 1))
                .catchError((error) => <Map<String, dynamic>>[]);
            final Iterable<Map<String, dynamic>> videoStreamsInfo =
                streamsInfo.where((Map<String, dynamic> streamInfo) =>
                    streamInfo['codec_type'] == 'video');

            final bool hasVideoStreamRequiredResolution =
                videoStreamsInfo.any((Map<String, dynamic> videoStreamInfo) {
              final int videoStreamResolutionWidth = videoStreamInfo['width'];
              final int videoStreamResolutionHeight = videoStreamInfo['height'];

              return videoStreamResolutionWidth >= _minResolutionWidth &&
                  videoStreamResolutionHeight >= _minResolutionHeight;
            });

            List<String> videoStreamResolutions =
                videoStreamsInfo.map((Map<String, dynamic> videoStreamInfo) {
              final int videoStreamResolutionWidth = videoStreamInfo['width'];
              final int videoStreamResolutionHeight = videoStreamInfo['height'];

              return '${videoStreamResolutionWidth}x$videoStreamResolutionHeight';
            }).toList();

            if (!hasVideoStreamRequiredResolution) {
              sourceUrlsToRemove.add(m3uEntry.sourceUrl);

              print('Channel:');
              print(m3uEntry.toString());
              print(
                  'Removed due to low video stream resolutions: ${videoStreamResolutions.join(', ')}. Required minimum: ${_minResolutionWidth}x$_minResolutionHeight');
            }

            print(
                'Filter by video stream resolution: $currentChannelIndex/${m3uEntries.length}');
            ++currentChannelIndex;
          },
        ),
      ),
    );

    m3uEntries.removeWhere(
      (M3uEntry m3uEntry) => sourceUrlsToRemove.contains(m3uEntry.sourceUrl),
    );
  }

  void _filterDuplicates(List<M3uEntry> m3uEntries) {
    final int m3uEntryCount = m3uEntries.length;
    int currentChannelIndex = 1;

    for (int i = 0; i < m3uEntries.length; ++i) {
      final M3uEntry m3uEntry = m3uEntries[i];

      m3uEntries.removeWhere((M3uEntry e) {
        final bool isDuplicate = e != m3uEntry &&
            e.information == m3uEntry.information &&
            e.sourceUrl == m3uEntry.sourceUrl;

        if (isDuplicate) {
          print('Channel:');
          print(m3uEntry.toString());
          print('Removed due to duplicate');
          ++currentChannelIndex;
        }

        return isDuplicate;
      });

      print('Filter by duplicate: $currentChannelIndex/$m3uEntryCount');
      ++currentChannelIndex;
    }
  }
}
