class PlayListItem {
  final String guid;
  final String? title;
  final String? type;
  final String? poster;
  final String? tvTitle;
  final String? parentTitle;
  final String? parentGuid;
  final String? ancestorName;
  final String? ancestorCategory;
  final int watched;
  final int ts;
  final int duration;
  final int episodeNumber;
  final int seasonNumber;
  final String? voteAverage;
  final String? overview;
  final int runtime;
  final int isFavorite;
  final String? videoGuid;
  final String? audioGuid;
  final String? subtitleGuid;
  final String? mediaGuid;
  final String? singleChildGuid;
  final String? airDate;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final int localNumberOfSeasons;
  final int localNumberOfEpisodes;

  PlayListItem({
    required this.guid,
    this.title,
    this.type,
    this.poster,
    this.tvTitle,
    this.parentTitle,
    this.parentGuid,
    this.ancestorName,
    this.ancestorCategory,
    this.watched = 0,
    this.ts = 0,
    this.duration = 0,
    this.episodeNumber = 0,
    this.seasonNumber = 0,
    this.voteAverage,
    this.overview,
    this.runtime = 0,
    this.isFavorite = 0,
    this.videoGuid,
    this.audioGuid,
    this.subtitleGuid,
    this.mediaGuid,
    this.singleChildGuid,
    this.airDate,
    this.numberOfSeasons = 0,
    this.numberOfEpisodes = 0,
    this.localNumberOfSeasons = 0,
    this.localNumberOfEpisodes = 0,
  });

  bool get isFolder => type == 'Directory' || type == 'TV';
  bool get isPlayable => type == 'Episode' || type == 'Movie' || type == 'Video';

  String get categoryLabel {
    switch (type) {
      case 'TV': return '剧集';
      case 'Movie': return '电影';
      case 'Episode': return '剧集';
      case 'Directory': return '文件夹';
      case 'Video': return '视频';
      default: return type ?? '';
    }
  }

  factory PlayListItem.fromJson(Map<String, dynamic> json) {
    return PlayListItem(
      guid: json['guid'] ?? '',
      title: json['title'],
      type: json['type'],
      poster: json['poster'],
      tvTitle: json['tv_title'],
      parentTitle: json['parent_title'],
      parentGuid: json['parent_guid'],
      ancestorName: json['ancestor_name'],
      ancestorCategory: json['ancestor_category'],
      watched: json['watched'] ?? 0,
      ts: (json['ts'] ?? json['watched_ts'] ?? 0).toInt(),
      duration: (json['duration'] ?? 0).toInt(),
      episodeNumber: json['episode_number'] ?? 0,
      seasonNumber: json['season_number'] ?? 0,
      voteAverage: json['vote_average']?.toString(),
      overview: json['overview'],
      runtime: json['runtime'] ?? 0,
      isFavorite: json['is_favorite'] ?? 0,
      videoGuid: json['video_guid'],
      audioGuid: json['audio_guid'],
      subtitleGuid: json['subtitle_guid'],
      mediaGuid: json['media_guid'],
      singleChildGuid: json['single_child_guid'],
      airDate: json['air_date'],
      numberOfSeasons: json['number_of_seasons'] ?? 0,
      numberOfEpisodes: json['number_of_episodes'] ?? 0,
      localNumberOfSeasons: json['local_number_of_seasons'] ?? 0,
      localNumberOfEpisodes: json['local_number_of_episodes'] ?? 0,
    );
  }
}
