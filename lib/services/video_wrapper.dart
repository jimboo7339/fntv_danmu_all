import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/mpv_player_settings.dart';

/// MPV (libmpv) 视频控制器封装。
class VideoWrapper {
  final String url;
  final Map<String, String>? headers;
  final MpvPlayerSettings settings;

  Player? _mpvPlayer;
  VideoController? _mpvVideoController;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _lastStablePosition = Duration.zero;
  double _aspectRatio = 16 / 9;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _isSeeking = false;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastNotifiedPosition = Duration.zero;
  Timer? _networkSpeedTimer;
  int _regressionRecoveries = 0;

  final List<VoidCallback> _listeners = [];
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<int> networkSpeedBps = ValueNotifier(0);

  /// 播放进度意外回退时回调（已尝试自动恢复）
  void Function(Duration lastStable)? onPositionRegression;

  VideoWrapper({
    required this.url,
    this.headers,
    MpvPlayerSettings? settings,
  }) : settings = settings ?? const MpvPlayerSettings();

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
    _regressionRecoveries = 0;
    _mpvPlayer = Player(
      configuration: PlayerConfiguration(
        bufferSize: settings.bufferBytes,
        vo: settings.vo,
      ),
    );
    _mpvVideoController = VideoController(_mpvPlayer!);

    _mpvPlayer!.stream.playing.listen((playing) {
      _isPlaying = playing;
      _notifyAll();
    });
    _mpvPlayer!.stream.position.listen(_onPositionUpdate);
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
    await _applyMpvProperties();
    await _waitForMetadata();
    _readVideoDimensions();

    if (startAt != null && startAt > Duration.zero) {
      await _accurateSeek(startAt);
    }

    _isInitialized = true;
    _lastStablePosition = _position;
    _startNetworkSpeedPolling();
    _notifyAll();
  }

  Future<void> _applyMpvProperties() async {
    try {
      final native = _mpvPlayer!.platform;
      if (native == null || native is! NativePlayer) return;

      final props = <String, String>{
        'cache': 'yes',
        'cache-pause': 'yes',
        'demuxer-readahead-secs': '${settings.cacheSecs}',
        'demuxer-max-bytes': '${settings.bufferMb}MiB',
        'demuxer-thread': 'yes',
        'hr-seek': 'yes',
        'framedrop': 'no',
        'vd-lavc-threads': '0',
        'audio-sync': 'yes',
        'video-sync': 'audio',
        'hwdec': settings.hwdec,
        'hwdec-codecs': 'all',
        'opengl-pbo': 'yes',
        'interpolation': settings.interpolation ? 'yes' : 'no',
        'network-timeout': '60',
        'stream-buffer-size': '4MiB',
        'force-seekable': 'yes',
        'sub-fix-timing': 'yes',
        'sub-delay': '0',
        'sub-scale-with-window': 'yes',
        'audio-buffer': '0.25',
        'video-latency-hacks': 'yes',
      };
      for (final e in props.entries) {
        await native.setProperty(e.key, e.value);
      }
      debugPrint('MPV props: hwdec=${settings.hwdec}, vo=${settings.vo}, '
          'buffer=${settings.bufferMb}MB, cache=${settings.cacheSecs}s');
    } catch (e) {
      debugPrint('MPV tuning error: $e');
    }
  }

  void _onPositionUpdate(Duration pos) {
    if (_isInitialized &&
        !_isSeeking &&
        _isPlaying &&
        !_isBuffering &&
        _lastStablePosition > const Duration(seconds: 12) &&
        pos + const Duration(seconds: 4) < _lastStablePosition) {
      _handlePositionRegression(pos);
      return;
    }

    if (!_isSeeking && pos > _lastStablePosition) {
      _lastStablePosition = pos;
    } else if (!_isSeeking && !_isBuffering && pos.inMilliseconds > 0) {
      final drift = (_lastStablePosition - pos).inMilliseconds.abs();
      if (drift < 2000) _lastStablePosition = pos;
    }

    _position = pos;
    positionNotifier.value = pos;
    _throttledNotify(pos);
  }

  Future<void> _handlePositionRegression(Duration badPos) async {
    if (_regressionRecoveries >= 3) {
      debugPrint('⚠️ Position regression ignored after retries: ${badPos.inSeconds}s');
      return;
    }
    _regressionRecoveries++;
    final recover = _lastStablePosition;
    debugPrint('⚠️ Position regression ${badPos.inSeconds}s -> recover ${recover.inSeconds}s');
    onPositionRegression?.call(recover);
    try {
      _isSeeking = true;
      await _mpvPlayer?.seek(recover);
      _position = recover;
      positionNotifier.value = recover;
      _notifyAll();
    } catch (e) {
      debugPrint('Position recovery seek failed: $e');
    } finally {
      _isSeeking = false;
    }
  }

  void _startNetworkSpeedPolling() {
    _networkSpeedTimer?.cancel();
    _networkSpeedTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_mpvPlayer == null) return;
      try {
        final native = _mpvPlayer!.platform;
        if (native is! NativePlayer) return;
        final raw = await native.getProperty('cache-speed', waitForInitialization: false);
        final speed = double.tryParse(raw.trim()) ?? 0;
        final bps = speed.round().clamp(0, 999999999);
        if (networkSpeedBps.value != bps) {
          networkSpeedBps.value = bps;
        }
      } catch (_) {}
    });
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
    _isSeeking = true;
    try {
      final native = _mpvPlayer!.platform;
      if (native is NativePlayer) {
        await native.setProperty('hr-seek', 'yes');
      }

      final dur = _duration.inMilliseconds > 0 ? _duration : (_mpvPlayer!.state.duration);
      final maxMs = dur.inMilliseconds > 1000 ? dur.inMilliseconds - 500 : target.inMilliseconds;
      final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs));

      await _mpvPlayer!.seek(clamped);

      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        final pos = _mpvPlayer!.state.position;
        if ((pos - clamped).inMilliseconds.abs() < 1200) {
          _position = pos;
          _lastStablePosition = pos;
          positionNotifier.value = pos;
          _notifyAll();
          return;
        }
        if (pos.inMilliseconds > 1000 && pos >= clamped - const Duration(seconds: 2)) {
          _position = pos;
          _lastStablePosition = pos;
          positionNotifier.value = pos;
          _notifyAll();
          return;
        }
      }
    } finally {
      _isSeeking = false;
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
    _lastStablePosition = _position;
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
      await _mpvPlayer!.setSubtitleTrack(SubtitleTrack('${listIndex + 1}', null, null));
      await _syncSubtitleTiming();
    } catch (e) {
      debugPrint('setSubtitleTrack error: $e');
    }
  }

  Future<void> _syncSubtitleTiming() async {
    try {
      final native = _mpvPlayer?.platform;
      if (native is NativePlayer) {
        await native.setProperty('sub-delay', '0');
        await native.setProperty('sub-fix-timing', 'yes');
      }
    } catch (e) {
      debugPrint('subtitle sync error: $e');
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
        padding: EdgeInsets.zero,
        style: TextStyle(
          color: subtitleColor,
          fontSize: subtitleSize,
          fontWeight: fontWeight,
          height: 1.25,
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
    _networkSpeedTimer?.cancel();
    await _mpvPlayer?.dispose();
    _mpvPlayer = null;
    _mpvVideoController = null;
    positionNotifier.dispose();
    networkSpeedBps.dispose();
    _listeners.clear();
  }
}
