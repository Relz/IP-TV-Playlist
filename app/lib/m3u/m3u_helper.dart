import 'dart:convert';

class M3uHelper {
  M3uHelper._();

  static final RegExp _channelNameRegExp = RegExp('#EXTINF:.*,(.*)');

  static List<List<String>> splitChannels(String m3uPlaylist) {
    if (m3uPlaylist.isEmpty) {
      return <List<String>>[];
    }

    final List<List<String>> result = <List<String>>[];

    final LineSplitter lineSplitter = LineSplitter();
    final List<String> lines = lineSplitter.convert(m3uPlaylist);

    if (lines.first.startsWith('#EXTM3U')) {
      lines.removeAt(0);
    }

    for (final String line in lines) {
      if (line.startsWith('#EXTINF:')) {
        result.add(<String>[]);
      }
      result.last.add(line);
    }

    return result;
  }

  static String mergePlaylists(List<String> playlists) => playlists
      .map((String playlist) => playlist.replaceFirst('^#EXTM3U\n', ''))
      .join();

  static String extractChannelName(String string) =>
      _channelNameRegExp.firstMatch(string)?.group(1) ?? '';
}
