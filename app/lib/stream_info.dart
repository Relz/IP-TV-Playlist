import 'dart:convert';
import 'dart:core';

import 'dart:io';

class StreamInfo {
  final String _streamUrl;

  String? _streamsInfoJsonString;

  StreamInfo(this._streamUrl);

  Future<List<Map<String, dynamic>>> get streamsInfo async {
    final String streamsInfoJsonString = _streamsInfoJsonString =
        _streamsInfoJsonString ?? await _getStreamsInfoPlain();
    final Map<String, dynamic> streamsInfoJson =
        jsonDecode(streamsInfoJsonString);

    return streamsInfoJson.isEmpty
        ? <Map<String, dynamic>>[]
        : List.castFrom(streamsInfoJson['streams']);
  }

  Future<String> _getStreamsInfoPlain() async {
    final ProcessResult processResult = await Process.run('ffprobe', [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_streams',
      '-of',
      'json=compact=1',
      '-max_reload',
      '1',
      '-m3u8_hold_counters',
      '1',
      _streamUrl,
    ]);

    return processResult.stdout;
  }
}
