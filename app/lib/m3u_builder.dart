import 'channel.dart';

class M3UBuilder {
  static String build(List<Channel> channels) {
    final StringBuffer stringBuffer = StringBuffer('#EXTM3U\n');
    for (final Channel channel in channels) {
      stringBuffer.writeln(
          '#EXTINF:-1, tvg-name="${channel.name}" tvg-logo="${channel.logoUrl}", ${channel.name}');
      stringBuffer.writeln(
          '#EXTGRP:${channel.groupName}, group_id="${channel.groupId}" group-title="${channel.groupName}"');
      stringBuffer.writeln(channel.sourceUrl);
    }

    return stringBuffer.toString();
  }
}
