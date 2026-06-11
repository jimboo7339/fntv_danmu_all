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
    _mpvPlayer = Player();
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

    // Open without auto-play so we can seek to resume position first
    await _mpvPlayer!.open(Media(url), play: false);
    _isInitialized = true;
    _notifyAll();
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

  Widget buildVideo() {
    if (useMpv) {
      return Video(
        controller: _mpvVideoController!,
        controls: (state) => const SizedBox.shrink(), // 禁用media_kit内置controls
        subtitleViewConfiguration: const SubtitleViewConfiguration(
          visible: true,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            shadows: [
              Shadow(blurRadius: 4, color: Colors.black),
              Shadow(blurRadius: 4, color: Colors.black),
            ],
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
