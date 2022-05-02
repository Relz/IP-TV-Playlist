import 'package:collection/collection.dart';

class M3uEntry {
  final String? information;
  final String? group;
  final String sourceUrl;

  M3uEntry(this.information, this.group, this.sourceUrl);

  factory M3uEntry.fromLines(List<String> lines) {
    final String? channelInformation =
        lines.firstWhereOrNull((String line) => line.startsWith('#EXTINF:'));
    final String? channelGroup =
        lines.firstWhereOrNull((String line) => line.startsWith('#EXTGRP:'));
    final String? channelUrl =
        lines.firstWhereOrNull((String line) => !line.startsWith('#'));

    return M3uEntry(channelInformation, channelGroup, channelUrl ?? '');
  }

  @override
  String toString() {
    final StringBuffer stringBuffer = StringBuffer();

    final List<String> lines =
        <String?>[information, group, sourceUrl].whereNotNull().toList();

    lines.forEachIndexed((int index, String line) => index == lines.length - 1
        ? stringBuffer.write(line)
        : stringBuffer.writeln(line));

    return stringBuffer.toString();
  }
}
