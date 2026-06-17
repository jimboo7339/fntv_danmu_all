import 'package:flutter/material.dart';

/// 播放器内核类型（对齐 LinPlayer 双内核架构）
enum PlayerCoreType {
  mpv,
  exo,
}

extension PlayerCoreTypeLabel on PlayerCoreType {
  String get label => switch (this) {
        PlayerCoreType.mpv => 'MPV',
        PlayerCoreType.exo => 'ExoPlayer',
      };

  String get description => switch (this) {
        PlayerCoreType.mpv => '全格式、PGS/ASS 内嵌字幕，云直链推荐',
        PlayerCoreType.exo => 'Android 原生，轻量稳定，文本字幕',
      };
}

/// 播放器适配器抽象（LinPlayer PlayerAdapter 精简版）
abstract class PlayerAdapter {
  bool get isInitialized;
  bool get isPlaying;
  bool get isBuffering;
  Duration get position;
  Duration get duration;
  double get aspectRatio;
  double get playbackRate;
  bool get nativeSubtitleActive;

  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);

  Future<void> initialize({Duration? startAt, double initialSpeed = 1.0});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();

  Widget buildVideo({
    bool subtitleVisible = false,
    double subtitleSize = 18,
  });
}
