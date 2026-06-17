import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/stream_response.dart';
import 'app_video_player.dart';
import 'exo_player_channel.dart';
import 'player_adapter.dart';

/// Android ExoPlayer 封装
class ExoPlayerWrapper extends AppVideoPlayer {
  final String url;
  final Map<String, String>? headers;

  final int _playerId = ExoPlayerChannel.allocateId();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;
  double _playbackRate = 1.0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _subtitleActive = false;

  void Function(Duration lastStable)? onPositionRegression;

  Timer? _pollTimer;

  final List<VoidCallback> _listeners = [];
  @override
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);
  @override
  final ValueNotifier<int> networkSpeedBps = ValueNotifier(0);

  ExoPlayerWrapper({required this.url, this.headers});

  @override
  PlayerCoreType get coreType => PlayerCoreType.exo;

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
  @override
  bool get mpvSubtitleActive => _subtitleActive;
  @override
  bool get nativeSubtitleActive => _subtitleActive;

  static bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || Platform.isAndroid);

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyAll() {
    for (final l in _listeners) {
      l();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      try {
        final e = await ExoPlayerChannel.getState(_playerId);
        _applyState(e);
      } catch (_) {}
    });
  }

  void _applyState(Map<String, dynamic> e) {
    _position = Duration(milliseconds: (e['positionMs'] as num?)?.round() ?? 0);
    _duration = Duration(milliseconds: (e['durationMs'] as num?)?.round() ?? 0);
    _isPlaying = e['isPlaying'] == true;
    _isBuffering = e['isBuffering'] == true;
    final w = (e['videoWidth'] as num?)?.toInt() ?? 0;
    final h = (e['videoHeight'] as num?)?.toInt() ?? 0;
    if (w > 0 && h > 0) _aspectRatio = w / h;
    positionNotifier.value = _position;
    _notifyAll();
  }

  @override
  Future<void> initialize({
    Duration? startAt,
    double initialSpeed = 1.0,
    bool deferSeek = false,
  }) async {
    if (!isSupported) throw UnsupportedError('ExoPlayer only on Android');
    _playbackRate = initialSpeed.clamp(0.25, 4.0);
    await ExoPlayerChannel.create(_playerId);
    _startPolling();
    final startMs = (!deferSeek && startAt != null && startAt > Duration.zero)
        ? startAt.inMilliseconds
        : 0;
    await ExoPlayerChannel.setSource(
      playerId: _playerId,
      url: url,
      headers: headers,
      startMs: startMs,
    );
    await ExoPlayerChannel.setSpeed(_playerId, _playbackRate);
    _isInitialized = true;
    _notifyAll();
  }

  @override
  Future<void> resumeAfterPlay(Duration target) async {
    if (target <= Duration.zero) return;
    await ExoPlayerChannel.seek(_playerId, target.inMilliseconds);
    await ExoPlayerChannel.setSpeed(_playerId, _playbackRate);
  }

  @override
  Future<void> play() async => ExoPlayerChannel.play(_playerId);

  @override
  Future<void> pause() async => ExoPlayerChannel.pause(_playerId);

  @override
  Future<void> seekTo(Duration position) async {
    await ExoPlayerChannel.seek(_playerId, position.inMilliseconds.clamp(0, 1 << 31));
    _position = position;
    positionNotifier.value = position;
    _notifyAll();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _playbackRate = speed.clamp(0.25, 4.0);
    await ExoPlayerChannel.setSpeed(_playerId, _playbackRate);
    _notifyAll();
  }

  @override
  Future<void> setAudioTrackByInfo({
    required int listIndex,
    AudioStreamInfo? info,
  }) async {
    await ExoPlayerChannel.setAudioTrack(_playerId, listIndex);
  }

  @override
  Future<void> applyInitialAudioIfNeeded({
    List<AudioStreamInfo>? audioStreams,
    int preferredListIndex = 0,
  }) async {
    if (audioStreams == null || audioStreams.length <= 1) return;
    await setAudioTrackByInfo(
      listIndex: preferredListIndex.clamp(0, audioStreams.length - 1),
      info: audioStreams[preferredListIndex.clamp(0, audioStreams.length - 1)],
    );
  }

  @override
  Future<void> setSubtitleTrack(int listIndex) async {
    if (listIndex < 0) {
      await ExoPlayerChannel.setSubtitleTrack(_playerId, -1);
      _subtitleActive = false;
      _notifyAll();
      return;
    }
    await ExoPlayerChannel.setSubtitleTrack(_playerId, listIndex);
    _subtitleActive = true;
    _notifyAll();
  }

  @override
  Future<bool> enableEmbeddedSubtitleDeferred({
    required int listIndex,
    SubtitleStreamInfo? info,
    Duration delay = const Duration(seconds: 1),
  }) async {
    await Future.delayed(delay);
    try {
      await setSubtitleTrack(listIndex);
      final state = await ExoPlayerChannel.getState(_playerId);
      final tracks = state['textTracks'] as List?;
      if (tracks == null || tracks.isEmpty) return false;
      return _subtitleActive;
    } catch (e) {
      debugPrint('Exo embedded subtitle error: $e');
      return false;
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
    return AndroidView(
      viewType: 'exo_player_view',
      creationParams: {'playerId': _playerId},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    await ExoPlayerChannel.dispose(_playerId);
    positionNotifier.dispose();
    networkSpeedBps.dispose();
    _listeners.clear();
  }
}
