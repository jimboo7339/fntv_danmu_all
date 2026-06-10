class WatchRecord {
  final String guid;
  final String title;
  final String? tvTitle;
  final int episodeNumber;
  final String? poster;
  final String? libraryName;
  final String? parentGuid;
  int ts;
  int duration;
  int updatedAt;

  WatchRecord({
    required this.guid,
    required this.title,
    this.tvTitle,
    this.episodeNumber = 0,
    this.poster,
    this.libraryName,
    this.parentGuid,
    this.ts = 0,
    this.duration = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  String get displayTitle {
    if (tvTitle != null && tvTitle!.isNotEmpty) {
      if (episodeNumber > 0) return "$tvTitle 第${episodeNumber}集";
      return tvTitle!;
    }
    return title;
  }

  String get dedupKey => (tvTitle != null && tvTitle!.isNotEmpty) ? tvTitle! : title;

  int get progressPercent => duration > 0 ? (ts * 100 ~/ duration) : 0;
  bool get isNearlyFinished => progressPercent >= 90;

  Map<String, dynamic> toJson() => {
    'guid': guid, 'title': title, 'tv_title': tvTitle,
    'episode_number': episodeNumber, 'poster': poster,
    'library_name': libraryName, 'parent_guid': parentGuid,
    'ts': ts, 'duration': duration, 'updated_at': updatedAt,
  };

  factory WatchRecord.fromJson(Map<String, dynamic> json) {
    return WatchRecord(
      guid: json['guid'] ?? '', title: json['title'] ?? '',
      tvTitle: json['tv_title'], episodeNumber: json['episode_number'] ?? 0,
      poster: json['poster'], libraryName: json['library_name'],
      parentGuid: json['parent_guid'],
      ts: (json['ts'] ?? 0).toInt(), duration: (json['duration'] ?? 0).toInt(),
      updatedAt: json['updated_at'],
    );
  }
}
