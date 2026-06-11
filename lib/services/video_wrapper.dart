import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Unified video controller wrapper supporting ExoPlayer and MPV engines.
class VideoWrapper {
  /// Engine type: 'mpv' or 'exo'
  final String engine;
  final String url;
  final Map<String, String>? headers;

  bool get useMpv => engine == 'mpv';
  bool get useExo => engine == 'exo';

  // video_player (ExoPlayer) controller
  VideoPlayerController? _exoController;

  // media_kit (MPV) controllers
  Player? _mpvPlayer;
  VideoController? _mpvVideoController;

  // Cached state
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;

  final List<VoidCallback> _listeners = [];

  VideoWrapper({
    required this.engine,
    required this.url,
    this.headers,
  });

  // ── Public state getters ──────────────────────────────────────────────

  Duration get position {
    if (useMpv) return _position;
    return _exoController?.value.position ?? Duration.zero;
  }

  Duration get duration {
    if (useMpv) return _duration;
    return _exoController?.value.duration ?? Duration.zero;
  }

  double get aspectRatio {
    if (useMpv) return _aspectRatio;
    return _exoController?.value.aspectRatio ?? 16 / 9;
  }

  bool get isPlaying {
    if (useMpv) return _isPlaying;
    return _exoController?.value.isPlaying ?? false;
  }

  bool get isBuffering {
    if (useMpv) return _isBuffering;
    return _exoController?.value.isBuffering ?? false;
  }

  bool get isInitialized {
    if (useMpv) return _isInitialized;
    return _exoController?.value.isInitialized ?? false;
  }

  // ── Listener management ───────────────────────────────────────────────

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (useExo && _exoController != null) {
      _exoController!.addListener(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (useExo && _exoController != null) {
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
    _exoController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? {},
    );
    await _exoController!.initialize();
    _isInitialized = true;
    for (final l in _listeners) {
      _exoController!.addListener(l);
    }
    _notifyAll();
  }

  Future<void> _initMpv() async {
    _mpvPlayer = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024,
        vo: 'gpu',
      ),
    );
    _mpvVideoController = VideoController(_mpvPlayer!);

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

    await _mpvPlayer!.open(Media(url), play: false);
    _isInitialized = true;
    _tuneMpvPerformance();
    _readVideoDimensions();
    _notifyAll();
  }

  /// MPV performance tuning
  void _tuneMpvPerformance() {
    try {
      final native = _mpvPlayer!.platform;
      if (native != null && native is NativePlayer) {
        native.setProperty('framedrop', 'decoder');
        native.setProperty('vd-lavc-threads', '4');
        native.setProperty('audio-sync', 'yes');
        native.setProperty('video-sync', 'audio');
        native.setProperty('hwdec', 'auto');
        debugPrint('MPV performance tuning applied');
      }
    } catch (e) {
      debugPrint('MPV tuning error: $e');
    }
  }

  void _readVideoDimensions() {
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
        return false;
      }
      return true;
    });
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

  /// Switch audio track (MPV only)
  Future<void> setAudioTrack(int index) async {
    if (useMpv && _mpvPlayer != null) {
      try {
        final trackId = '${index + 1}';
        await _mpvPlayer!.setAudioTrack(AudioTrack(trackId, null, null));
      } catch (e) {
        debugPrint('setAudioTrack error: $e');
      }
    }
  }

  /// Switch subtitle track (MPV only). Pass -1 to disable.
  Future<void> setSubtitleTrack(int index) async {
    if (useMpv && _mpvPlayer != null) {
      try {
        if (index < 0) {
          await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.no());
        } else {
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
    if (useMpv) {
      await _mpvPlayer?.dispose();
      _mpvPlayer = null;
      _mpvVideoController = null;
    } else {
      for (final l in _listeners) {
        _exoController?.removeListener(l);
      }
      await _exoController?.dispose();
      _exoController = null;
    }

    _listeners.clear();
  }
}
