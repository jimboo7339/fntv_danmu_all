import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import '../models/mpv_player_settings.dart';
import '../models/stream_response.dart';
import 'player_adapter.dart';
import 'subtitle_track_matcher.dart';

/// MPV 播放器（参考 LinPlayer MpvPlayerAdapter 实现）
class VideoWrapper implements PlayerAdapter {
  static const _startupSeekAttempts = 8;
  static const _startupSeekRetry = Duration(milliseconds: 120);
  static const _startupSeekPoll = Duration(milliseconds: 40);
  static const _startupSeekTimeout = Duration(milliseconds: 800);
  static const _startupSeekTolerance = Duration(milliseconds: 750);

  final String url;
  final Map<String, String>? headers;
  final MpvPlayerSettings settings;

  Player? _mpvPlayer;
  VideoController? _mpvVideoController;
  Widget? _cachedVideoWidget;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  double _playbackRate = 1.0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _isSeeking = false;
  bool _mpvSubtitleActive = false;
  bool _deferResumePending = false;
  bool _initPropertiesApplied = false;
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastNotifiedPosition = Duration.zero;
  Timer? _networkSpeedTimer;

  final List<VoidCallback> _listeners = [];
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<int> networkSpeedBps = ValueNotifier(0);

  void Function(Duration lastStable)? onPositionRegression;

  VideoWrapper({
    required this.url,
    this.headers,
    MpvPlayerSettings? settings,
  }) : settings = settings ?? const MpvPlayerSettings();

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get aspectRatio => _aspectRatio;
  @override
  double get playbackRate => _playbackRate;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isBuffering => _isBuffering;
  @override
  bool get isInitialized => _isInitialized;
  bool get mpvSubtitleActive => _mpvSubtitleActive;
  @override
  bool get nativeSubtitleActive => _mpvSubtitleActive;

  bool get _isNetworkUrl =>
      url.startsWith('http://') || url.startsWith('https://');

  NativePlayer? get _native {
    final p = _mpvPlayer?.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyAll() {
    for (final l in _listeners) {
      l();
    }
  }

  void _invalidateVideoWidget() {
    _cachedVideoWidget = null;
  }

  @override
  Future<void> initialize({
    Duration? startAt,
    double initialSpeed = 1.0,
    bool deferSeek = false,
  }) async {
    _playbackRate = initialSpeed.clamp(0.25, 4.0);
    _initPropertiesApplied = false;
    _invalidateVideoWidget();
    _mpvSubtitleActive = false;
    _deferResumePending = deferSeek && startAt != null && startAt > Duration.zero;

    _mpvPlayer = Player(
      configuration: PlayerConfiguration(
        libass: true,
        vo: settings.vo,
        bufferSize: settings.bufferBytes,
        logLevel: MPVLogLevel.warn,
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

    final resume = (startAt != null && startAt > Duration.zero) ? startAt : null;
    await _openVideoSource(
      resumePosition: _deferResumePending ? null : resume,
    );
    if (resume == null && !_deferResumePending) {
      await _applyPlaybackRate();
    }

    _isInitialized = true;
    _position = _mpvPlayer?.state.position ?? Duration.zero;
    _startNetworkSpeedPolling();
    _notifyAll();
  }

  Future<void> _openVideoSource({Duration? resumePosition}) async {
    final native = _native;
    if (resumePosition != null && native != null) {
      try {
        await native.setProperty('start', '${resumePosition.inMilliseconds / 1000.0}');
      } catch (_) {}
    }

    await _mpvPlayer!.open(
      Media(url, httpHeaders: headers ?? const {}),
      play: false,
    );

    if (resumePosition != null) {
      await _applyStartupSeek(resumePosition);
      // 续播 seek 落位后再设倍速，避免 1.0x seek 后切 1.5x 导致音频超前
      await _applyPlaybackRate();
    }

    if (resumePosition != null && native != null) {
      try {
        await native.setProperty('start', 'none');
      } catch (_) {}
    }

    await _waitUntilPlayable();
    _readVideoDimensions();
  }

  Future<void> _applyInitProperties() async {
    if (_initPropertiesApplied) return;
    final native = _native;
    if (native == null) return;

    final hwdec = _isNetworkUrl ? 'auto-safe' : settings.hwdec;
    final syncMode = _playbackRate != 1.0 ? 'audio' : settings.videoSync;

    final props = <String, String>{
      'hr-seek': 'yes',
      'framedrop': 'no',
      'vd-lavc-threads': '0',
      'ad-lavc-threads': '0',
      'hwdec': hwdec,
      'hwdec-codecs': 'all',
      'opengl-pbo': 'yes',
      'interpolation': settings.interpolation ? 'yes' : 'no',
      'force-seekable': 'yes',
      'audio-buffer': '0.15',
      'video-sync': syncMode,
      'audio-pitch-correction': 'yes',
      'sub-visibility': 'yes',
      'secondary-sub-visibility': 'no',
      'sub-fix-timing': 'yes',
      'sub-delay': '0',
      'sub-ass-override': 'no',
    };

    if (_isNetworkUrl) {
      props.addAll({
        'cache': 'yes',
        'cache-pause': 'yes',
        'cache-pause-wait': '2.5',
        'cache-pause-initial': 'no',
        'cache-secs': '${settings.cacheSecs}',
        'demuxer-readahead-secs': '${settings.cacheSecs}',
        'demuxer-max-bytes': '${settings.bufferMb}MiB',
        'demuxer-seekable-cache': 'yes',
        'demuxer-cache-wait': 'no',
        'network-timeout': '30',
        'stream-buffer-size': '33554432',
        'prefetch-playlist': 'no',
      });
      try {
        final dir = await getTemporaryDirectory();
        props['cache-on-disk'] = 'yes';
        props['cache-dir'] = '${dir.path}/mpv_cache';
      } catch (_) {}
    } else {
      props.addAll({
        'cache': 'yes',
        'cache-secs': '${settings.cacheSecs}',
        'demuxer-max-bytes': '${settings.bufferMb}MiB',
      });
    }

    try {
      for (final e in props.entries) {
        await native.setProperty(e.key, e.value);
      }
      _initPropertiesApplied = true;
      debugPrint('MPV init (LinPlayer-style): hwdec=$hwdec, sync=$syncMode, net=$_isNetworkUrl');
    } catch (e) {
      debugPrint('MPV init props error: $e');
    }
  }

  Future<void> _applyStartupSeek(Duration target) async {
    for (var attempt = 1; attempt <= _startupSeekAttempts; attempt++) {
      try {
        _isSeeking = true;
        await _mpvPlayer!.seek(target);
      } catch (e) {
        debugPrint('startup seek attempt $attempt error: $e');
      } finally {
        _isSeeking = false;
      }

      if (await _waitForStartupSeekPosition(target)) {
        _position = _mpvPlayer!.state.position;
        positionNotifier.value = _position;
        debugPrint('✅ Startup seek ${target.inSeconds}s (attempt $attempt)');
        return;
      }
      if (attempt < _startupSeekAttempts) {
        await Future.delayed(_startupSeekRetry);
      }
    }
    debugPrint('⚠️ Startup seek missed ${target.inSeconds}s');
  }

  Future<bool> _waitForStartupSeekPosition(Duration target) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < _startupSeekTimeout) {
      final pos = _mpvPlayer?.state.position ?? Duration.zero;
      if ((pos - target).inMilliseconds.abs() <= _startupSeekTolerance.inMilliseconds) {
        return true;
      }
      await Future.delayed(_startupSeekPoll);
    }
    final pos = _mpvPlayer?.state.position ?? Duration.zero;
    return (pos - target).inMilliseconds.abs() <= _startupSeekTolerance.inMilliseconds;
  }

  Future<void> _waitUntilPlayable({int maxMs = 3000}) async {
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

  Future<void> _waitForMpvTracks({int attempts = 40}) async {
    for (var i = 0; i < attempts; i++) {
      final tracks = _mpvPlayer?.state.tracks;
      if (tracks != null && tracks.subtitle.length > 2) return;
      if (tracks != null && tracks.audio.length > 2 && i > 15) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  List<AudioTrack> get _embedAudioTracks => _mpvPlayer?.state.tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri)
          .toList(growable: false) ??
      const [];

  List<SubtitleTrack> get _embedSubtitleTracks =>
      _mpvPlayer?.state.tracks.subtitle
          .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri)
          .toList(growable: false) ??
      const [];

  AudioTrack? _resolveAudioTrack(int listIndex, AudioStreamInfo? info) {
    final tracks = _embedAudioTracks;
    if (tracks.isEmpty) return null;
    if (info != null) {
      for (final t in tracks) {
        if (SubtitleTrackMatcher.languagesMatch(info.language, t.language)) return t;
      }
      for (final t in tracks) {
        if (SubtitleTrackMatcher.titlesMatch(info.title, t.title)) return t;
      }
    }
    if (listIndex >= 0 && listIndex < tracks.length) return tracks[listIndex];
    return tracks.first;
  }

  SubtitleTrack? _resolveSubtitleTrack(int listIndex, SubtitleStreamInfo? info) {
    final tracks = _embedSubtitleTracks;
    if (tracks.isEmpty) return null;

    if (info != null) {
      final streamIdx = info.index;
      for (final t in tracks) {
        final tid = SubtitleTrackMatcher.streamIndexFromId(t.id);
        if (tid != null && tid == streamIdx) return t;
      }
      for (final t in tracks) {
        if (SubtitleTrackMatcher.languagesMatch(info.language, t.language)) return t;
      }
      for (final t in tracks) {
        if (SubtitleTrackMatcher.titlesMatch(info.title, t.title)) return t;
      }
    }

    if (listIndex >= 0 && listIndex < tracks.length) return tracks[listIndex];
    return tracks.first;
  }

  Future<bool> _ensureSubtitleSid(String sid) async {
    final native = _native;
    if (native == null) return false;
    for (var i = 0; i < 6; i++) {
      try {
        var current = await native.getProperty('sid');
        if (current != sid) {
          await native.setProperty('sid', sid);
          current = await native.getProperty('sid');
        }
        if (current == sid) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
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

  /// 等待首帧后再 seek / 设倍速，云直链续播更稳
  Future<void> waitUntilFirstFrame({int maxMs = 8000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: maxMs));
    while (DateTime.now().isBefore(deadline)) {
      final w = _mpvPlayer?.state.width;
      final h = _mpvPlayer?.state.height;
      if (w != null && h != null && w > 0 && h > 0) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 云直链：起播后再 seek，减少 HTTP 预 seek 导致的音画漂移
  Future<void> resumeAfterPlay(Duration target) async {
    if (_mpvPlayer == null || target <= Duration.zero) return;
    await waitUntilFirstFrame();
    await _applyStartupSeek(target);
    _deferResumePending = false;
    await _applyPlaybackRate();
  }

  Future<bool> selectEmbeddedSubtitleWhenReady({
    required int listIndex,
    SubtitleStreamInfo? info,
    Duration delay = const Duration(milliseconds: 600),
  }) async {
    if (_mpvPlayer == null) return false;
    await waitUntilFirstFrame();
    await Future.delayed(delay);
    for (var attempt = 1; attempt <= 3; attempt++) {
      final track = await setSubtitleTrackByInfo(listIndex: listIndex, info: info);
      if (track != null) {
        _invalidateVideoWidget();
        _notifyAll();
        return true;
      }
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<void> _applyPlaybackRate() async {
    final player = _mpvPlayer;
    if (player == null) return;
    final rate = _playbackRate.clamp(0.25, 4.0);
    try {
      final native = _native;
      if (native != null) {
        // 倍速时强制跟随音频时钟，避免云直链 HTTP seek 后音画漂移
        if (rate != 1.0) {
          await native.setProperty('video-sync', 'audio');
        } else {
          await native.setProperty('video-sync', settings.videoSync);
        }
        await native.setProperty('audio-pitch-correction', 'yes');
      }
      await player.setRate(rate);
      if (native != null) {
        await native.setProperty('speed', rate.toStringAsFixed(3));
      }
      debugPrint('MPV speed: ${rate}x (sync=${rate != 1.0 ? 'audio' : settings.videoSync})');
    } catch (e) {
      debugPrint('applyPlaybackRate error: $e');
    }
  }

  void _onPositionUpdate(Duration pos) {
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

  @override
  Future<void> play() async {
    await _mpvPlayer?.play();
    if (!_deferResumePending) {
      await _applyPlaybackRate();
    }
  }

  @override
  Future<void> pause() async => _mpvPlayer?.pause();

  @override
  Future<void> seekTo(Duration position) async {
    _isSeeking = true;
    try {
      await _mpvPlayer?.seek(position);
      _position = position;
      positionNotifier.value = position;
      _notifyAll();
    } finally {
      _isSeeking = false;
    }
    await _applyPlaybackRate();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _playbackRate = speed.clamp(0.25, 4.0);
    await _applyPlaybackRate();
  }

  Future<void> setAudioTrackByInfo({
    required int listIndex,
    AudioStreamInfo? info,
  }) async {
    if (_mpvPlayer == null) return;
    try {
      await _waitForMpvTracks();
      final track = _resolveAudioTrack(listIndex, info);
      if (track == null) return;
      debugPrint('setAudioTrack: list=$listIndex -> mpv aid=${track.id}');
      await _mpvPlayer!.setAudioTrack(track);
      // 切音轨后短暂等待再恢复倍速，减少时钟重置
      await Future.delayed(const Duration(milliseconds: 150));
      await _applyPlaybackRate();
    } catch (e) {
      debugPrint('setAudioTrack error: $e');
    }
  }

  Future<void> setSubtitleTrack(int listIndex) async {
    await setSubtitleTrackByInfo(listIndex: listIndex);
  }

  Future<SubtitleTrack?> setSubtitleTrackByInfo({
    required int listIndex,
    SubtitleStreamInfo? info,
  }) async {
    if (_mpvPlayer == null) return null;
    try {
      if (listIndex < 0) {
        await _mpvPlayer!.setSubtitleTrack(SubtitleTrack.no());
        final native = _native;
        if (native != null) await native.setProperty('sid', 'no');
        _mpvSubtitleActive = false;
        _invalidateVideoWidget();
        _notifyAll();
        return null;
      }

      await _waitForMpvTracks();
      final track = _resolveSubtitleTrack(listIndex, info);
      if (track == null) {
        debugPrint('setSubtitleTrack: no track list=$listIndex '
            '(available=${_embedSubtitleTracks.length})');
        return null;
      }

      debugPrint('setSubtitleTrack: list=$listIndex -> sid=${track.id}');
      await _mpvPlayer!.setSubtitleTrack(track);
      final sidOk = await _ensureSubtitleSid(track.id);
      _mpvSubtitleActive = true;
      final native = _native;
      if (native != null) {
        await native.setProperty('sub-visibility', 'yes');
        await native.setProperty('sub-delay', '0');
      }
      _invalidateVideoWidget();
      _notifyAll();
      if (!sidOk) {
        debugPrint('⚠️ sid verify failed for ${track.id}');
      }
      return track;
    } catch (e) {
      debugPrint('setSubtitleTrack error: $e');
      return null;
    }
  }

  @override
  Widget buildVideo({
    bool subtitleVisible = false,
    double subtitleSize = 18,
    double subtitleOutline = 1.5,
    bool subtitleBackground = false,
    Color subtitleColor = Colors.white,
    double subtitleWeight = 600,
  }) {
    if (_cachedVideoWidget != null) return _cachedVideoWidget!;

    final fontWeight = FontWeight.values[
      ((subtitleWeight.clamp(100, 900) - 100) / 100).round().clamp(0, 8)
    ];
    _cachedVideoWidget = Video(
      controller: _mpvVideoController!,
      controls: (state) => const SizedBox.shrink(),
      subtitleViewConfiguration: SubtitleViewConfiguration(
        visible: _mpvSubtitleActive,
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
          ],
          backgroundColor: subtitleBackground ? Colors.black54 : Colors.transparent,
        ),
      ),
    );
    return _cachedVideoWidget!;
  }

  @override
  Future<void> dispose() async {
    _networkSpeedTimer?.cancel();
    _invalidateVideoWidget();
    await _mpvPlayer?.dispose();
    _mpvPlayer = null;
    _mpvVideoController = null;
    positionNotifier.dispose();
    networkSpeedBps.dispose();
    _listeners.clear();
  }
}
