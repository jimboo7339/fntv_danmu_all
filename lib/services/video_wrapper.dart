import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/mpv_player_settings.dart';
import '../models/stream_response.dart';

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
  double _playbackRate = 1.0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _isSeeking = false;
  bool _mpvSubtitleActive = false;
  bool _initPropertiesApplied = false;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastNotifiedPosition = Duration.zero;
  Timer? _networkSpeedTimer;

  final List<VoidCallback> _listeners = [];
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<int> networkSpeedBps = ValueNotifier(0);

  /// 播放进度意外回退时回调（仅记录，不再自动 seek 以免加剧音画不同步）
  void Function(Duration lastStable)? onPositionRegression;

  VideoWrapper({
    required this.url,
    this.headers,
    MpvPlayerSettings? settings,
  }) : settings = settings ?? const MpvPlayerSettings();

  Duration get position => _position;
  Duration get duration => _duration;
  double get aspectRatio => _aspectRatio;
  double get playbackRate => _playbackRate;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isInitialized => _isInitialized;
  bool get mpvSubtitleActive => _mpvSubtitleActive;

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyAll() {
    for (final l in _listeners) {
      l();
    }
  }

  NativePlayer? get _native {
    final p = _mpvPlayer?.platform;
    return p is NativePlayer ? p : null;
  }

  Future<void> initialize({Duration? startAt}) async {
    _playbackRate = 1.0;
    _initPropertiesApplied = false;
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
      if (dur.inMilliseconds > 0) {
        _duration = dur;
        _notifyAll();
      }
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

    await _applyInitProperties();
    await _lockSubtitleDecoderOff();

    await _mpvPlayer!.open(
      Media(url, httpHeaders: headers ?? const {}),
      play: false,
    );

    await _waitUntilPlayable();
    _readVideoDimensions();

    if (startAt != null && startAt > Duration.zero) {
      await _fastSeek(startAt);
    }

    _isInitialized = true;
    _lastStablePosition = _position;
    _startNetworkSpeedPolling();
    _notifyAll();
  }

  Future<void> _lockSubtitleDecoderOff() async {
    final native = _native;
    if (native == null) return;
    try {
      for (final e in const {
        'sid': 'no',
        'sub-visibility': 'no',
        'sub-auto': 'no',
        'subs-fallback': 'no',
        'sub-forced-only': 'no',
      }.entries) {
        await native.setProperty(e.key, e.value);
      }
      _mpvSubtitleActive = false;
    } catch (e) {
      debugPrint('lockSubtitleDecoderOff error: $e');
    }
  }

  /// 多音轨/字幕容器：默认关闭 MPV 字幕解码，软件字幕层单独渲染。
  Future<void> _disableEmbeddedSubtitles() async {
    if (_mpvPlayer == null) return;
    try {
      await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.no());
      await _lockSubtitleDecoderOff();
    } catch (e) {
      debugPrint('disableEmbeddedSubtitles error: $e');
    }
  }

  Future<void> prepareCleanPlayback() => _disableEmbeddedSubtitles();

  Future<void> _waitForMpvTracks({int attempts = 30}) async {
    for (var i = 0; i < attempts; i++) {
      final tracks = _mpvPlayer?.state.tracks;
      if (tracks != null &&
          (tracks.audio.length > 2 || tracks.subtitle.length > 2 || i > 12)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  /// 尽快达到可播放状态，不等待完整轨列表。
  Future<void> _waitUntilPlayable({int maxMs = 2500}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
    while (DateTime.now().isBefore(deadline)) {
      final player = _mpvPlayer;
      if (player == null) return;
      final dur = player.state.duration;
      final w = player.state.width;
      final h = player.state.height;
      if (dur.inMilliseconds > 0 || (w != null && w > 0 && h != null && h > 0)) {
        if (dur.inMilliseconds > 0) _duration = dur;
        return;
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
  }

  List<AudioTrack> get _embedAudioTracks => _mpvPlayer?.state.tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri)
          .toList(growable: false) ??
      const [];

  List<SubtitleTrack> get _embedSubtitleTracks =>
      _mpvPlayer?.state.tracks.subtitle
          .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
          .toList(growable: false) ??
      const [];

  AudioTrack? _resolveAudioTrack(int listIndex, AudioStreamInfo? info) {
    final tracks = _embedAudioTracks;
    if (tracks.isEmpty) return null;

    if (info != null) {
      final lang = info.language?.trim().toLowerCase();
      if (lang != null && lang.isNotEmpty) {
        for (final t in tracks) {
          final tl = t.language?.trim().toLowerCase();
          if (tl != null && tl == lang) return t;
        }
      }
      final title = info.title?.trim().toLowerCase();
      if (title != null && title.isNotEmpty) {
        for (final t in tracks) {
          final tt = t.title?.trim().toLowerCase();
          if (tt != null && (tt == title || tt.contains(title) || title.contains(tt))) {
            return t;
          }
        }
      }
    }

    if (listIndex >= 0 && listIndex < tracks.length) return tracks[listIndex];
    return tracks.first;
  }

  SubtitleTrack? _resolveSubtitleTrack(int listIndex, SubtitleStreamInfo? info) {
    final tracks = _embedSubtitleTracks;
    if (tracks.isEmpty) return null;

    if (info != null) {
      final lang = info.language?.trim().toLowerCase();
      if (lang != null && lang.isNotEmpty) {
        for (final t in tracks) {
          final tl = t.language?.trim().toLowerCase();
          if (tl != null && tl == lang) return t;
        }
      }
      final title = info.title?.trim().toLowerCase();
      if (title != null && title.isNotEmpty) {
        for (final t in tracks) {
          final tt = t.title?.trim().toLowerCase();
          if (tt != null && (tt == title || tt.contains(title) || title.contains(tt))) {
            return t;
          }
        }
      }
    }

    if (listIndex >= 0 && listIndex < tracks.length) return tracks[listIndex];
    return tracks.first;
  }

  Future<void> applyInitialAudioIfNeeded({
    List<AudioStreamInfo>? audioStreams,
    int preferredListIndex = 0,
  }) async {
    if (_mpvPlayer == null || audioStreams == null || audioStreams.length <= 1) return;
    await _waitForMpvTracks();
    final idx = preferredListIndex.clamp(0, audioStreams.length - 1);
    await setAudioTrackByInfo(listIndex: idx, info: audioStreams[idx]);
  }

  /// 仅在 open 前调用一次，避免播放中反复重置同步状态。
  Future<void> _applyInitProperties() async {
    if (_initPropertiesApplied) return;
    final native = _native;
    if (native == null) return;

    final syncMode = _playbackRate != 1.0 ? 'audio' : settings.videoSync;
    final props = <String, String>{
      'cache': 'yes',
      'cache-pause': 'yes',
      'cache-secs': '${settings.cacheSecs}',
      'demuxer-readahead-secs': '${settings.cacheSecs}',
      'demuxer-max-bytes': '${settings.bufferMb}MiB',
      'demuxer-thread': 'yes',
      'hr-seek': 'yes',
      'framedrop': 'no',
      'vd-lavc-threads': '0',
      'hwdec': settings.hwdec,
      'hwdec-codecs': 'all',
      'opengl-pbo': 'yes',
      'interpolation': settings.interpolation ? 'yes' : 'no',
      'network-timeout': '60',
      'stream-buffer-size': '8MiB',
      'force-seekable': 'yes',
      'audio-buffer': '0.15',
      'video-latency-hacks': 'yes',
      'untimed': 'no',
      'video-sync': syncMode,
      'video-sync-max-video-change': '5',
      'video-sync-max-audio-change': '0.125',
      'audio-pitch-correction': 'yes',
      'sub-fix-timing': 'yes',
      'sub-delay': '0',
      'sub-ass-override': 'no',
      'sub-auto': 'no',
      'subs-fallback': 'no',
      'mkv-subtitle-preroll': 'no',
    };
    try {
      for (final e in props.entries) {
        await native.setProperty(e.key, e.value);
      }
      _initPropertiesApplied = true;
      debugPrint('MPV init: hwdec=${settings.hwdec}, vo=${settings.vo}, sync=$syncMode');
    } catch (e) {
      debugPrint('MPV init props error: $e');
    }
  }

  Future<void> _applyPlaybackRate() async {
    final player = _mpvPlayer;
    if (player == null) return;
    final rate = _playbackRate.clamp(0.25, 4.0);
    try {
      await player.setRate(rate);
      final native = _native;
      if (native != null) {
        await native.setProperty('speed', rate.toStringAsFixed(3));
        if (rate != 1.0) {
          await native.setProperty('video-sync', 'audio');
        }
      }
      debugPrint('MPV speed: ${rate}x');
    } catch (e) {
      debugPrint('applyPlaybackRate error: $e');
    }
  }

  void _onPositionUpdate(Duration pos) {
    if (_isInitialized &&
        !_isSeeking &&
        _isPlaying &&
        !_isBuffering &&
        _playbackRate == 1.0 &&
        _lastStablePosition > const Duration(seconds: 20) &&
        pos + const Duration(seconds: 8) < _lastStablePosition) {
      debugPrint('⚠️ Position regression ${pos.inSeconds}s (stable ${_lastStablePosition.inSeconds}s)');
      onPositionRegression?.call(_lastStablePosition);
    }

    if (!_isSeeking && pos > _lastStablePosition) {
      _lastStablePosition = pos;
    } else if (!_isSeeking && !_isBuffering && pos.inMilliseconds > 0) {
      final drift = (_lastStablePosition - pos).inMilliseconds.abs();
      if (drift < 3000) _lastStablePosition = pos;
    }

    _position = pos;
    positionNotifier.value = pos;
    _throttledNotify(pos);
  }

  void _startNetworkSpeedPolling() {
    _networkSpeedTimer?.cancel();
    _networkSpeedTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_mpvPlayer == null) return;
      try {
        final native = _native;
        if (native == null) return;
        final raw = await native.getProperty('cache-speed', waitForInitialization: false);
        final speed = double.tryParse(raw.trim()) ?? 0;
        final bps = speed.round().clamp(0, 999999999);
        if (networkSpeedBps.value != bps) {
          networkSpeedBps.value = bps;
        }
      } catch (_) {}
    });
  }

  Future<void> _fastSeek(Duration target) async {
    if (_mpvPlayer == null) return;
    _isSeeking = true;
    try {
      final dur = _duration.inMilliseconds > 0 ? _duration : (_mpvPlayer!.state.duration);
      final maxMs = dur.inMilliseconds > 1000 ? dur.inMilliseconds - 500 : target.inMilliseconds;
      final clamped = Duration(milliseconds: target.inMilliseconds.clamp(0, maxMs));

      await _mpvPlayer!.seek(clamped);

      for (var i = 0; i < 8; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        final pos = _mpvPlayer!.state.position;
        if ((pos - clamped).inMilliseconds.abs() < 2000 || pos >= clamped) {
          _position = pos;
          _lastStablePosition = pos;
          positionNotifier.value = pos;
          _notifyAll();
          return;
        }
      }
      _position = clamped;
      _lastStablePosition = clamped;
      positionNotifier.value = clamped;
      _notifyAll();
    } finally {
      _isSeeking = false;
    }
  }

  Future<void> _accurateSeek(Duration target) => _fastSeek(target);

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

  Future<void> play() async {
    await _mpvPlayer?.play();
    await _applyPlaybackRate();
  }

  Future<void> pause() async => _mpvPlayer?.pause();

  Future<void> seekTo(Duration position) async {
    await _accurateSeek(position);
    _lastStablePosition = _position;
    await _applyPlaybackRate();
  }

  Future<void> setSpeed(double speed) async {
    _playbackRate = speed.clamp(0.25, 4.0);
    await _applyPlaybackRate();
  }

  Future<void> setAudioTrack(int index) async {
    await setAudioTrackByInfo(listIndex: index);
  }

  Future<void> setAudioTrackByInfo({
    required int listIndex,
    AudioStreamInfo? info,
  }) async {
    if (_mpvPlayer == null) return;
    try {
      await _waitForMpvTracks();
      final track = _resolveAudioTrack(listIndex, info);
      if (track == null) {
        debugPrint('setAudioTrack: no MPV track for listIndex=$listIndex');
        return;
      }
      debugPrint('setAudioTrack: list=$listIndex -> mpv aid=${track.id}');
      await _mpvPlayer!.setAudioTrack(track);
      await _applyPlaybackRate();
    } catch (e) {
      debugPrint('setAudioTrack error: $e');
    }
  }

  Future<void> setSubtitleTrack(int listIndex) async {
    await setSubtitleTrackByInfo(listIndex: listIndex);
  }

  Future<void> setSubtitleTrackByInfo({
    required int listIndex,
    SubtitleStreamInfo? info,
  }) async {
    if (_mpvPlayer == null) return;
    try {
      if (listIndex < 0) {
        await _disableEmbeddedSubtitles();
        return;
      }
      await _waitForMpvTracks();
      final track = _resolveSubtitleTrack(listIndex, info);
      if (track == null) {
        debugPrint('setSubtitleTrack: no MPV track for listIndex=$listIndex');
        return;
      }
      debugPrint('setSubtitleTrack: list=$listIndex -> mpv sid=${track.id}');
      await _mpvPlayer!.setSubtitleTrack(track);
      _mpvSubtitleActive = true;
      final native = _native;
      if (native != null) {
        await native.setProperty('sub-visibility', 'yes');
        await native.setProperty('sub-delay', '0');
      }
      await _applyPlaybackRate();
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
    bool subtitleVisible = false,
  }) {
    final fontWeight = FontWeight.values[
      ((subtitleWeight.clamp(100, 900) - 100) / 100).round().clamp(0, 8)
    ];
    return Video(
      controller: _mpvVideoController!,
      controls: (state) => const SizedBox.shrink(),
      subtitleViewConfiguration: SubtitleViewConfiguration(
        visible: subtitleVisible && _mpvSubtitleActive,
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
