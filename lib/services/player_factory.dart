import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import '../models/mpv_player_settings.dart';
import '../models/stream_response.dart';
import 'app_video_player.dart';
import 'exo_player_wrapper.dart';
import 'player_adapter.dart';
import 'video_wrapper.dart';

/// 播放器工厂 + 内核路由
class PlayerFactory {
  /// 云直链 / STRM 内嵌字幕场景需 MPV
  static bool needsMpvForEmbeddedSubtitles({
    required bool preferEmbedded,
    List<SubtitleStreamInfo>? subtitleStreams,
  }) {
    if (!preferEmbedded) return false;
    if (subtitleStreams == null || subtitleStreams.isEmpty) return false;
    for (final s in subtitleStreams) {
      final codec = (s.codecName ?? '').toLowerCase();
      if (codec.contains('pgs') ||
          codec.contains('hdmv') ||
          codec.contains('dvd_sub') ||
          codec.contains('dvb')) {
        return true;
      }
    }
    // STRM/云直链：飞牛字幕 API 不可用，内嵌字幕只能客户端 demux
    return true;
  }

  static PlayerCoreType resolveCore({
    required PlayerCoreType userPreference,
    required bool preferEmbedded,
    List<SubtitleStreamInfo>? subtitleStreams,
    bool forceMpv = false,
  }) {
    if (forceMpv || userPreference == PlayerCoreType.mpv) {
      return PlayerCoreType.mpv;
    }
    if (!ExoPlayerWrapper.isSupported) return PlayerCoreType.mpv;
    if (needsMpvForEmbeddedSubtitles(
      preferEmbedded: preferEmbedded,
      subtitleStreams: subtitleStreams,
    )) {
      return PlayerCoreType.mpv;
    }
    return PlayerCoreType.exo;
  }

  static AppVideoPlayer create({
    required PlayerCoreType core,
    required String url,
    Map<String, String>? headers,
    MpvPlayerSettings? mpvSettings,
  }) {
    if (core == PlayerCoreType.exo && ExoPlayerWrapper.isSupported) {
      return ExoPlayerWrapper(url: url, headers: headers);
    }
    return VideoWrapper(url: url, headers: headers, settings: mpvSettings);
  }
}
