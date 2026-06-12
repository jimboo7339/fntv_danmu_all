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

  /// 自动检测格式并解析
  static SubtitleData? parseAuto(String content, {String language = ''}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('WEBVTT')) return parseVtt(content, language: language);
    if (trimmed.contains('[Script Info]') || trimmed.contains('Dialogue:')) {
      return parseAss(content, language: language);
    }
    if (trimmed.contains('-->')) return parseSrt(content, language: language);
    return null;
  }

  /// 解析 ASS/SSA 格式字幕（提取 Dialogue 行）
  static SubtitleData parseAss(String assContent, {String language = ''}) {
    final entries = <SubtitleEntry>[];
    int index = 0;
    for (final line in assContent.split('\n')) {
      if (!line.startsWith('Dialogue:')) continue;
      final parts = line.split(',');
      if (parts.length < 10) continue;
      final start = _parseAssTime(parts[1].trim());
      final end = _parseAssTime(parts[2].trim());
      if (start == null || end == null) continue;
      final text = _cleanSrtTags(parts.sublist(9).join(',').trim());
      if (text.isEmpty) continue;
      index++;
      entries.add(SubtitleEntry(index: index, start: start, end: end, text: text));
    }
    return SubtitleData(entries: entries, language: language, codecName: 'ass');
  }

  static Duration? _parseAssTime(String t) {
    // H:MM:SS.cc
    final m = RegExp(r'^(\d+):(\d{2}):(\d{2})\.(\d{2})$').firstMatch(t);
    if (m == null) return null;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
      milliseconds: int.parse(m.group(4)! ) * 10,
    );
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
      final timeMatch = _matchTime(lines[1]);
      if (timeMatch == null) continue;

      final start = _durationFromMatch(timeMatch, 1);
      final end = _durationFromMatch(timeMatch, 5);

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

      final timeMatch = _matchTime(lines[timeLineIdx]);
      if (timeMatch == null) continue;

      final start = _durationFromMatch(timeMatch, 1);
      final end = _durationFromMatch(timeMatch, 5);

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

  static RegExpMatch? _matchTime(String line) {
    return RegExp(r'(.+?)\s*-->\s*(.+)').firstMatch(line.trim());
  }

  static Duration _durationFromMatch(RegExpMatch m, int side) {
    final token = side == 1 ? m.group(1)! : m.group(2)!;
    return _parseTimeToken(token.trim());
  }

  static Duration _parseTimeToken(String token) {
    final parts = token.split(':');
    if (parts.length == 3) {
      final secParts = parts[2].split(RegExp(r'[.,]'));
      return Duration(
        hours: int.parse(parts[0]),
        minutes: int.parse(parts[1]),
        seconds: int.parse(secParts[0]),
        milliseconds: secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0,
      );
    }
    if (parts.length == 2) {
      final secParts = parts[1].split(RegExp(r'[.,]'));
      return Duration(
        minutes: int.parse(parts[0]),
        seconds: int.parse(secParts[0]),
        milliseconds: secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0,
      );
    }
    return Duration.zero;
  }
}
