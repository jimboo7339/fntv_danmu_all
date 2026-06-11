class StreamResponse {
  final List<DirectLinkQuality>? directLinkQualities;
  final VideoStreamInfo? videoStream;
  final List<AudioStreamInfo>? audioStreams;
  final List<SubtitleStreamInfo>? subtitleStreams;
  final FileStreamInfo? fileStream;

  StreamResponse({
    this.directLinkQualities,
    this.videoStream,
    this.audioStreams,
    this.subtitleStreams,
    this.fileStream,
  });

  factory StreamResponse.fromJson(Map<String, dynamic> json) {
    return StreamResponse(
      directLinkQualities: json['direct_link_qualities'] != null
          ? (json['direct_link_qualities'] as List).map((e) => DirectLinkQuality.fromJson(e)).toList()
          : null,
      videoStream: json['video_stream'] != null ? VideoStreamInfo.fromJson(json['video_stream']) : null,
      audioStreams: json['audio_streams'] != null
          ? (json['audio_streams'] as List).map((e) => AudioStreamInfo.fromJson(e)).toList()
          : null,
      subtitleStreams: json['subtitle_streams'] != null
          ? (json['subtitle_streams'] as List).map((e) => SubtitleStreamInfo.fromJson(e)).toList()
          : null,
      fileStream: json['file_stream'] != null ? FileStreamInfo.fromJson(json['file_stream']) : null,
    );
  }
}

class DirectLinkQuality {
  final int bitrate;
  final String? resolution;
  final bool progressive;
  final String? url;
  final bool isM3u8;

  DirectLinkQuality({this.bitrate = 0, this.resolution, this.progressive = false, this.url, this.isM3u8 = false});

  factory DirectLinkQuality.fromJson(Map<String, dynamic> json) {
    return DirectLinkQuality(
      bitrate: json['bitrate'] ?? 0,
      resolution: json['resolution'],
      progressive: json['progressive'] ?? false,
      url: json['url'],
      isM3u8: json['is_m3u8'] ?? false,
    );
  }
}

class VideoStreamInfo {
  final int width, height, bps, bitDepth;
  final String? codecName, profile, rFrameRate, colorSpace, colorTransfer, pixFmt;
  final int dvProfile;
  final int duration;

  VideoStreamInfo({
    this.width = 0, this.height = 0, this.bps = 0, this.bitDepth = 0,
    this.codecName, this.profile, this.rFrameRate, this.colorSpace,
    this.colorTransfer, this.pixFmt, this.dvProfile = 0, this.duration = 0,
  });

  factory VideoStreamInfo.fromJson(Map<String, dynamic> json) {
    return VideoStreamInfo(
      width: json['width'] ?? 0, height: json['height'] ?? 0,
      bps: json['bps'] ?? 0, bitDepth: json['bit_depth'] ?? 0,
      codecName: json['codec_name'], profile: json['profile'],
      rFrameRate: json['r_frame_rate'], colorSpace: json['color_space'],
      colorTransfer: json['color_transfer'], pixFmt: json['pix_fmt'],
      dvProfile: json['dv_profile'] ?? 0, duration: json['duration'] ?? 0,
    );
  }
}

class AudioStreamInfo {
  final String? codecName, language, title;
  final int channels, bitrate, index;

  AudioStreamInfo({this.codecName, this.language, this.title, this.channels = 0, this.bitrate = 0, this.index = 0});

  factory AudioStreamInfo.fromJson(Map<String, dynamic> json) {
    return AudioStreamInfo(
      codecName: json['codec_name'], language: json['language'], title: json['title'],
      channels: json['channels'] ?? 0, bitrate: json['bitrate'] ?? 0,
      index: json['index'] ?? 0,
    );
  }
}

class SubtitleStreamInfo {
  final String? codecName, language, title;
  final int index;

  SubtitleStreamInfo({this.codecName, this.language, this.title, this.index = 0});

  factory SubtitleStreamInfo.fromJson(Map<String, dynamic> json) {
    return SubtitleStreamInfo(
      codecName: json['codec_name'],
      language: json['language'],
      title: json['title'],
      index: json['index'] ?? 0,
    );
  }
}

class FileStreamInfo {
  final String? fileName, path;
  final int size, duration;

  FileStreamInfo({this.fileName, this.path, this.size = 0, this.duration = 0});

  factory FileStreamInfo.fromJson(Map<String, dynamic> json) {
    return FileStreamInfo(
      fileName: json['file_name'], path: json['path'],
      size: (json['size'] ?? 0).toInt(), duration: json['duration'] ?? 0,
    );
  }
}
