import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// MPV (libmpv) 视频控制器封装。
class VideoWrapper {
  final String url;
  final Map<String, String>? headers;
  /// 'hardware' or 'software'
  final String decoderMode;

  Player? _mpvPlayer;
  VideoController? _mpvVideoController;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastNotifiedPosition = Duration.zero;

  final List<VoidCallback> _listeners = [];
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

  VideoWrapper({
    required this.url,
    this.headers,
    this.decoderMode = 'hardware',
  });

  Duration get position => _position;
  Duration get duration => _duration;
  double get aspectRatio => _aspectRatio;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isInitialized => _isInitialized;

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyAll() {
    for (final l in _listeners) {
      l();
    }
  }

  Future<void> initialize({Duration? startAt}) async {
    _mpvPlayer = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 192 * 1024 * 1024,
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
      positionNotifier.value = pos;
      _throttledNotify(pos);
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

    await _mpvPlayer!.open(
      Media(url, httpHeaders: headers ?? const {}),
      play: false,
    );
    _tuneMpvPerformance();
    await _waitForMetadata();
    _readVideoDimensions();

    if (startAt != null && startAt > Duration.zero) {
      await _accurateSeek(startAt);
    }

    _isInitialized = true;
    _notifyAll();
  }

  void _tuneMpvPerformance() {
    try {
      final native = _mpvPlayer!.platform;
      if (native == null || native is! NativePlayer) return;

      final hwdec = decoderMode == 'software' ? 'no' : 'auto-safe';
      final props = <String, String>{
        'cache': 'yes',
        'cache-pause': 'no',
        'demuxer-readahead-secs': '25',
        'hr-seek': 'yes',
        'framedrop': 'decoder',
        'vd-lavc-threads': '0',
        'audio-sync': 'yes',
        'video-sync': 'audio',
        'hwdec': hwdec,
        'hwdec-codecs': 'all',
        'opengl-pbo': 'yes',
        'interpolation': 'no',
        'network-timeout': '30',
      };
      for (final e in props.entries) {
        native.setProperty(e.key, e.value);
      }
      debugPrint('MPV tuning applied (hwdec=$hwdec)');
    } catch (e) {
      debugPrint('MPV tuning error: $e');
    }
  }

  Future<void> _waitForMetadata() async {
    for (var i = 0; i < 150; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final dur = _mpvPlayer?.state.duration ?? Duration.zero;
      if (dur.inMilliseconds > 0) {
        _duration = dur;
        return;
      }
    }
  }

  Future<void> _accurateSeek(Duration target) async {
    if (_mpvPlayer == null) return;
    final native = _mpvPlayer!.platform;
    if (native is NativePlayer) {
      native.setProperty('hr-seek', 'yes');
    }

    final dur = _duration.inMilliseconds > 0 ? _duration : (_mpvPlayer!.state.duration);
    final maxMs = dur.inMilliseconds > 1000 ? dur.inMilliseconds - 500 : target.inMilliseconds;
    final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs));

    await _mpvPlayer!.seek(clamped);

    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 80));
      final pos = _mpvPlayer!.state.position;
      if ((pos - clamped).inMilliseconds.abs() < 1500) {
        _position = pos;
        positionNotifier.value = pos;
        _notifyAll();
        return;
      }
      if (pos.inMilliseconds > 1000) {
        _position = pos;
        positionNotifier.value = pos;
        _notifyAll();
        return;
      }
    }
  }

  void _throttledNotify(Duration pos) {
    final now = DateTime.now();
    if (now.difference(_lastPositionNotify).inMilliseconds >= 100 ||
        pos.inSeconds != _lastNotifiedPosition.inSeconds) {
      _lastPositionNotify = now;
      _lastNotifiedPosition = pos;
      _notifyAll();
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

  Future<void> play() async => _mpvPlayer?.play();

  Future<void> pause() async => _mpvPlayer?.pause();

  Future<void> seekTo(Duration position) async {
    await _accurateSeek(position);
  }

  Future<void> setSpeed(double speed) async => _mpvPlayer?.setRate(speed);

  Future<void> setAudioTrack(int index) async {
    if (_mpvPlayer == null) return;
    try {
      await _mpvPlayer!.setAudioTrack(AudioTrack('${index + 1}', null, null));
    } catch (e) {
      debugPrint('setAudioTrack error: $e');
    }
  }

  /// [listIndex] 为字幕列表序号，-1 关闭。
  Future<void> setSubtitleTrack(int listIndex) async {
    if (_mpvPlayer == null) return;
    try {
      if (listIndex < 0) {
        await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.auto());
      await Future.delayed(const Duration(milliseconds: 300));
      await _mpvPlayer!.setSubtitleTrack(SubtitleTrack('${listIndex + 1}', null, null));
    } catch (e) {
      debugPrint('setSubtitleTrack error: $e');
    }
  }

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
  }

  Future<void> dispose() async {
    await _mpvPlayer?.dispose();
    _mpvPlayer = null;
    _mpvVideoController = null;
    positionNotifier.dispose();
    _listeners.clear();
  }
}
