class PlayInfoResponse {
  final String? guid;
  final String? type;
  final String? parentGuid;
  final String? mediaGuid;
  final String? videoGuid;
  final String? audioGuid;
  final String? subtitleGuid;
  final int ts;
  final ItemInfo? item;

  PlayInfoResponse({
    this.guid,
    this.type,
    this.parentGuid,
    this.mediaGuid,
    this.videoGuid,
    this.audioGuid,
    this.subtitleGuid,
    this.ts = 0,
    this.item,
  });

  String? get posterPath => item?.poster;
  String? get backdropPath => item?.backdrops;

  factory PlayInfoResponse.fromJson(Map<String, dynamic> json) {
    return PlayInfoResponse(
      guid: json['guid'],
      type: json['type'],
      parentGuid: json['parent_guid'],
      mediaGuid: json['media_guid'],
      videoGuid: json['video_guid'],
      audioGuid: json['audio_guid'],
      subtitleGuid: json['subtitle_guid'],
      ts: (json['ts'] ?? 0).toInt(),
      item: json['item'] != null ? ItemInfo.fromJson(json['item']) : null,
    );
  }
}

class ItemInfo {
  final String? guid;
  final String? title;
  final String? originalTitle;
  final String? tvTitle;
  final String? parentTitle;
  final String? overview;
  final String? poster;
  final String? backdrops;
  final String? stillPath;
  final String? logo;
  final String? voteAverage;
  final int runtime;
  final int duration;
  final int episodeNumber;
  final int seasonNumber;
  final int numberOfEpisodes;
  final int numberOfSeasons;
  final String? airDate;
  final String? releaseDate;
  final String? status;
  final int watched;
  final int isFavorite;
  final MediaStreamInfo? mediaStream;

  ItemInfo({
    this.guid,
    this.title,
    this.originalTitle,
    this.tvTitle,
    this.parentTitle,
    this.overview,
    this.poster,
    this.backdrops,
    this.stillPath,
    this.logo,
    this.voteAverage,
    this.runtime = 0,
    this.duration = 0,
    this.episodeNumber = 0,
    this.seasonNumber = 0,
    this.numberOfEpisodes = 0,
    this.numberOfSeasons = 0,
    this.airDate,
    this.releaseDate,
    this.status,
    this.watched = 0,
    this.isFavorite = 0,
    this.mediaStream,
  });

  factory ItemInfo.fromJson(Map<String, dynamic> json) {
    return ItemInfo(
      guid: json['guid'],
      title: json['title'],
      originalTitle: json['original_title'],
      tvTitle: json['tv_title'],
      parentTitle: json['parent_title'],
      overview: json['overview'],
      poster: json['poster'],
      backdrops: json['backdrops'],
      stillPath: json['still_path'],
      logo: json['logo'],
      voteAverage: json['vote_average']?.toString(),
      runtime: json['runtime'] ?? 0,
      duration: (json['duration'] ?? 0).toInt(),
      episodeNumber: json['episode_number'] ?? 0,
      seasonNumber: json['season_number'] ?? 0,
      numberOfEpisodes: json['number_of_episodes'] ?? 0,
      numberOfSeasons: json['number_of_seasons'] ?? 0,
      airDate: json['air_date'],
      releaseDate: json['release_date'],
      status: json['status'],
      watched: json['watched'] ?? 0,
      isFavorite: json['is_favorite'] ?? 0,
      mediaStream: json['media_stream'] != null
          ? MediaStreamInfo.fromJson(json['media_stream'])
          : null,
    );
  }
}

class MediaStreamInfo {
  final List<String>? resolutions;
  final List<String>? audioType;
  final List<String>? colorRangeType;

  MediaStreamInfo({this.resolutions, this.audioType, this.colorRangeType});

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) {
    return MediaStreamInfo(
      resolutions: json['resolutions'] != null ? List<String>.from(json['resolutions']) : null,
      audioType: json['audio_type'] != null ? List<String>.from(json['audio_type']) : null,
      colorRangeType: json['color_range_type'] != null ? List<String>.from(json['color_range_type']) : null,
    );
  }
}
