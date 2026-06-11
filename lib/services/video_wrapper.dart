import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Unified video controller wrapper supporting both ExoPlayer (video_player)
/// and MPV (media_kit) engines at runtime.
class VideoWrapper {
  final bool useMpv;
  final String url;

  // video_player (ExoPlayer) controller
  VideoPlayerController? _exoController;

  // media_kit (MPV) controllers
  Player? _mpvPlayer;
  VideoController? _mpvVideoController;

  // Polling timer for media_kit state → listener pattern
  Timer? _pollTimer;

  // Cached state for media_kit polling
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;

  // Listener list (mirrors video_player's addListener/removeListener)
  final List<VoidCallback> _listeners = [];

  VideoWrapper({
    required this.useMpv,
    required this.url,
  });

  // ── Public state getters ──────────────────────────────────────────────

  Duration get position =>
      useMpv ? _position : (_exoController?.value.position ?? Duration.zero);

  Duration get duration =>
      useMpv ? _duration : (_exoController?.value.duration ?? Duration.zero);

  double get aspectRatio =>
      useMpv ? _aspectRatio : (_exoController?.value.aspectRatio ?? 16 / 9);

  bool get isPlaying =>
      useMpv ? _isPlaying : (_exoController?.value.isPlaying ?? false);

  bool get isBuffering =>
      useMpv ? _isBuffering : (_exoController?.value.isBuffering ?? false);

  bool get isInitialized =>
      useMpv ? _isInitialized : (_exoController?.value.isInitialized ?? false);

  // ── Listener management ───────────────────────────────────────────────

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    // For exo, also register directly so we get immediate notifications
    if (!useMpv && _exoController != null) {
      _exoController!.addListener(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (!useMpv && _exoController != null) {
      _exoController!.removeListener(listener);
    }
  }

  void _notifyAll() {
    for (final l in _listeners) {
      l();
    }
  }

  // ── Initialization ────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (useMpv) {
      await _initMpv();
    } else {
      await _initExo();
    }
  }

  Future<void> _initExo() async {
    _exoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _exoController!.initialize();
    _isInitialized = true;
    // Register existing listeners on the exo controller
    for (final l in _listeners) {
      _exoController!.addListener(l);
    }
    _notifyAll();
  }

  Future<void> _initMpv() async {
    _mpvPlayer = Player(
      configuration: const PlayerConfiguration(
        // 增大demux缓存到128MB，减少倍速播放卡顿
        bufferSize: 128 * 1024 * 1024,
        // GPU硬件加速输出
        vo: 'gpu',
      ),
    );
    _mpvVideoController = VideoController(_mpvPlayer!);

    // Listen to streams and update cached state
    _mpvPlayer!.stream.playing.listen((playing) {
      _isPlaying = playing;
      _notifyAll();
    });
    _mpvPlayer!.stream.position.listen((pos) {
      _position = pos;
      _notifyAll();
    });
    _mpvPlayer!.stream.duration.listen((dur) {
      _duration = dur;
      _notifyAll();
    });
    _mpvPlayer!.stream.buffering.listen((buf) {
      _isBuffering = buf;
      _notifyAll();
    });
    // 监听视频宽高，动态更新比例
    _mpvPlayer!.stream.width.listen((w) {
      final h = _mpvPlayer?.state.height ?? 0;
      if (w != null && w > 0 && h > 0) {
        _aspectRatio = w / h;
        _notifyAll();
      }
    });
    _mpvPlayer!.stream.height.listen((h) {
      final w = _mpvPlayer?.state.width ?? 0;
      if (h != null && h > 0 && w > 0) {
        _aspectRatio = w / h;
        _notifyAll();
      }
    });

    // Open without auto-play so we can seek to resume position first
    await _mpvPlayer!.open(Media(url), play: false);
    _isInitialized = true;

    // MPV 性能优化：设置解码参数
    _tuneMpvPerformance();

    // 主动读取视频宽高（不等stream异步回调）
    _readVideoDimensions();

    _notifyAll();
  }

  /// MPV 性能优化：framedrop + 解码线程 + 音频同步
  void _tuneMpvPerformance() {
    try {
      final native = _mpvPlayer!.platform;
      if (native != null && native is NativePlayer) {
        // 允许解码器丢帧（网络不好时跳过卡住的帧）
        native.setProperty('framedrop', 'decoder');
        // 视频解码线程数
        native.setProperty('vd-lavc-threads', '4');
        // 音频同步校正
        native.setProperty('audio-sync', 'yes');
        // 显示同步模式
        native.setProperty('video-sync', 'audio');
        // 硬件解码
        native.setProperty('hwdec', 'auto');
        debugPrint('MPV performance tuning applied');
      }
    } catch (e) {
      debugPrint('MPV tuning error: $e');
    }
  }

  /// 主动读取视频宽高，避免初始1秒黑边
  void _readVideoDimensions() {
    // 多次尝试读取，MPV需要时间解码头帧
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_mpvPlayer == null) return false;
      final w = _mpvPlayer!.state.width;
      final h = _mpvPlayer!.state.height;
      if (w != null && h != null && w > 0 && h > 0) {
        final newRatio = w / h;
        if ((newRatio - _aspectRatio).abs() > 0.01) {
          _aspectRatio = newRatio;
          _notifyAll();
        }
        return false; // got dimensions, stop
      }
      return true; // keep trying
    });
    // 超时保护：最多试20次（2秒）
  }

  // ── Playback controls ─────────────────────────────────────────────────

  Future<void> play() async {
    if (useMpv) {
      await _mpvPlayer?.play();
    } else {
      await _exoController?.play();
    }
  }

  Future<void> pause() async {
    if (useMpv) {
      await _mpvPlayer?.pause();
    } else {
      await _exoController?.pause();
    }
  }

  Future<void> seekTo(Duration position) async {
    if (useMpv) {
      await _mpvPlayer?.seek(position);
    } else {
      await _exoController?.seekTo(position);
    }
  }

  Future<void> setSpeed(double speed) async {
    if (useMpv) {
      await _mpvPlayer?.setRate(speed);
    } else {
      await _exoController?.setPlaybackSpeed(speed);
    }
  }

  /// Switch audio track by index (0-based). Only works with mpv engine.
  Future<void> setAudioTrack(int index) async {
    if (useMpv && _mpvPlayer != null) {
      try {
        // mpv uses 1-based track IDs for embedded tracks
        final trackId = '${index + 1}';
        await _mpvPlayer!.setAudioTrack(AudioTrack(trackId, null, null));
      } catch (e) {
        debugPrint('setAudioTrack error: $e');
      }
    }
  }

  /// Switch subtitle track by index (0-based). Pass -1 to disable. Only works with mpv engine.
  Future<void> setSubtitleTrack(int index) async {
    if (useMpv && _mpvPlayer != null) {
      try {
        if (index < 0) {
          await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.no());
        } else {
          // mpv uses 1-based track IDs for embedded tracks
          final trackId = '${index + 1}';
          await _mpvPlayer!.setSubtitleTrack(SubtitleTrack(trackId, null, null));
        }
      } catch (e) {
        debugPrint('setSubtitleTrack error: $e');
      }
    }
  }

  // ── Widget builder ────────────────────────────────────────────────────

  Widget buildVideo({
    double subtitleSize = 18,
    double subtitleOutline = 1.5,
    bool subtitleBackground = false,
    Color subtitleColor = Colors.white,
    double subtitleWeight = 600,
  }) {
    // 将数值转为 FontWeight
    final fontWeight = FontWeight.values[
      ((subtitleWeight.clamp(100, 900) - 100) / 100).round().clamp(0, 8)
    ];
    if (useMpv) {
      return Video(
        controller: _mpvVideoController!,
        controls: (state) => const SizedBox.shrink(),
        subtitleViewConfiguration: SubtitleViewConfiguration(
          visible: true,
          textScaleFactor: subtitleSize / 18.0,
          style: TextStyle(
            color: subtitleColor,
            fontSize: subtitleSize,
            fontWeight: fontWeight,
            shadows: [
              Shadow(blurRadius: subtitleOutline, color: Colors.black),
              Shadow(blurRadius: subtitleOutline, color: Colors.black),
              Shadow(blurRadius: subtitleOutline, color: Colors.black),
            ],
            backgroundColor: subtitleBackground ? Colors.black54 : Colors.transparent,
          ),
        ),
      );
    } else {
      return VideoPlayer(_exoController!);
    }
  }

  // ── Disposal ──────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    if (useMpv) {
      await _mpvPlayer?.dispose();
      _mpvPlayer = null;
      _mpvVideoController = null;
    } else {
      // Remove registered listeners before disposing exo controller
      for (final l in _listeners) {
        _exoController?.removeListener(l);
      }
      await _exoController?.dispose();
      _exoController = null;
    }

    _listeners.clear();
  }
}
