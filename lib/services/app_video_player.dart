import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/stream_response.dart';
import 'player_adapter.dart';

/// 播放页统一视频控制器（MPV / Exo 共用接口）
abstract class AppVideoPlayer implements PlayerAdapter {
  ValueNotifier<Duration> get positionNotifier;
  ValueNotifier<int> get networkSpeedBps;

  PlayerCoreType get coreType;
  bool get mpvSubtitleActive;

  void Function(Duration lastStable)? onPositionRegression;

  Future<void> resumeAfterPlay(Duration target);
  Future<void> applyInitialAudioIfNeeded({
    List<AudioStreamInfo>? audioStreams,
    int preferredListIndex,
  });
  Future<void> setAudioTrackByInfo({
    required int listIndex,
    AudioStreamInfo? info,
  });
  Future<void> setSubtitleTrack(int listIndex);
  Future<bool> enableEmbeddedSubtitleDeferred({
    required int listIndex,
    SubtitleStreamInfo? info,
    Duration delay,
  });

  Widget buildVideo({
    bool subtitleVisible,
    double subtitleSize,
    double subtitleOutline,
    bool subtitleBackground,
    Color subtitleColor,
    double subtitleWeight,
  });
}
