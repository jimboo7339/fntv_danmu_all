/// 软件字幕数据模型和 SRT 解析器
/// 用于 ExoPlayer 等不支持内嵌字幕的播放器
library;

class SubtitleEntry {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleEntry({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  @override
  String toString() => 'SubtitleEntry[$index] $start-$end: $text';
}

class SubtitleData {
  final List<SubtitleEntry> entries;
  final String language;
  final String codecName;

  const SubtitleData({
    required this.entries,
    this.language = '',
    this.codecName = '',
  });

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// 二分查找：获取当前时间点应显示的字幕
  SubtitleEntry? getEntryAt(Duration position) {
    final ms = position.inMilliseconds;
    int lo = 0, hi = entries.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final e = entries[mid];
      if (ms < e.start.inMilliseconds) {
        hi = mid - 1;
      } else if (ms > e.end.inMilliseconds) {
        lo = mid + 1;
      } else {
        return e;
      }
    }
    return null;
  }

  /// 解析 SRT 格式字幕
  static SubtitleData parseSrt(String srtContent, {String language = ''}) {
    final entries = <SubtitleEntry>[];
    final blocks = srtContent.split(RegExp(r'\r?\n\r?\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      // 第一行：序号
      final index = int.tryParse(lines[0].trim());
      if (index == null) continue;

      // 第二行：时间码 00:00:01,000 --> 00:00:04,000
      final timeMatch = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})',
      ).firstMatch(lines[1]);
      if (timeMatch == null) continue;

      final start = Duration(
        hours: int.parse(timeMatch.group(1)!),
        minutes: int.parse(timeMatch.group(2)!),
        seconds: int.parse(timeMatch.group(3)!),
        milliseconds: int.parse(timeMatch.group(4)!),
      );
      final end = Duration(
        hours: int.parse(timeMatch.group(5)!),
        minutes: int.parse(timeMatch.group(6)!),
        seconds: int.parse(timeMatch.group(7)!),
        milliseconds: int.parse(timeMatch.group(8)!),
      );

      // 剩余行：字幕文本
      final text = lines.sublist(2).join('\n').trim();
      if (text.isNotEmpty) {
        entries.add(SubtitleEntry(
          index: index,
          start: start,
          end: end,
          text: _cleanSrtTags(text),
        ));
      }
    }

    return SubtitleData(entries: entries, language: language);
  }

  /// 解析 WebVTT 格式字幕
  static SubtitleData parseVtt(String vttContent, {String language = ''}) {
    final entries = <SubtitleEntry>[];
    // 去掉 WEBVTT 头部
    final content = vttContent.replaceFirst(RegExp(r'^WEBVTT.*?\n\n', dotAll: true), '');
    final blocks = content.split(RegExp(r'\r?\n\r?\n'));

    int index = 0;
    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      // 找时间码行
      int timeLineIdx = 0;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIdx = i;
          break;
        }
      }

      final timeMatch = RegExp(
        r'(\d{2}):(\d{2}):(\d{2})[.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[.](\d{3})',
      ).firstMatch(lines[timeLineIdx]);
      if (timeMatch == null) continue;

      final start = Duration(
        hours: int.parse(timeMatch.group(1)!),
        minutes: int.parse(timeMatch.group(2)!),
        seconds: int.parse(timeMatch.group(3)!),
        milliseconds: int.parse(timeMatch.group(4)!),
      );
      final end = Duration(
        hours: int.parse(timeMatch.group(5)!),
        minutes: int.parse(timeMatch.group(6)!),
        seconds: int.parse(timeMatch.group(7)!),
        milliseconds: int.parse(timeMatch.group(8)!),
      );

      final text = lines.sublist(timeLineIdx + 1).join('\n').trim();
      if (text.isNotEmpty) {
        index++;
        entries.add(SubtitleEntry(
          index: index,
          start: start,
          end: end,
          text: _cleanSrtTags(text),
        ));
      }
    }

    return SubtitleData(entries: entries, language: language);
  }

  /// 清理 SRT/VTT 标签
  static String _cleanSrtTags(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '') // HTML tags
        .replaceAll(RegExp(r'\{[^}]+\}'), ''); // ASS tags
  }
}
