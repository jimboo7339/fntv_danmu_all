/// 字幕轨匹配（参考 LinPlayer SubtitleTrackMatcher）
class SubtitleTrackMatcher {
  static int? streamIndexFromId(String? id) {
    if (id == null || id.isEmpty) return null;
    return int.tryParse(id);
  }

  static bool titlesMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.contains(y) || y.contains(x);
  }

  static bool languagesMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    const zh = {'chi', 'zho', 'zh', 'cn', 'chs', 'cht', 'zh-cn', 'zh-hans', 'zh-hant'};
    if (zh.contains(x) && zh.contains(y)) return true;
    return false;
  }
}
