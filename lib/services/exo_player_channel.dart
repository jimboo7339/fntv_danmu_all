import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android ExoPlayer 原生通道
class ExoPlayerChannel {
  static const _method = MethodChannel('com.fntv.fnos_tv_all/exo_player');

  static int _nextId = 1;

  static int allocateId() => _nextId++;

  static Future<void> create(int playerId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _method.invokeMethod('create', {'playerId': playerId});
  }

  static Future<void> setSource({
    required int playerId,
    required String url,
    Map<String, String>? headers,
    int startMs = 0,
  }) async {
    await _method.invokeMethod('setSource', {
      'playerId': playerId,
      'url': url,
      'headers': headers ?? {},
      'startMs': startMs,
    });
  }

  static Future<void> play(int playerId) async =>
      _method.invokeMethod('play', {'playerId': playerId});

  static Future<void> pause(int playerId) async =>
      _method.invokeMethod('pause', {'playerId': playerId});

  static Future<void> seek(int playerId, int positionMs) async =>
      _method.invokeMethod('seek', {'playerId': playerId, 'positionMs': positionMs});

  static Future<void> setSpeed(int playerId, double speed) async =>
      _method.invokeMethod('setSpeed', {'playerId': playerId, 'speed': speed});

  static Future<void> setSubtitleTrack(int playerId, int trackIndex) async =>
      _method.invokeMethod('setSubtitleTrack', {
        'playerId': playerId,
        'trackIndex': trackIndex,
      });

  static Future<void> setAudioTrack(int playerId, int trackIndex) async =>
      _method.invokeMethod('setAudioTrack', {
        'playerId': playerId,
        'trackIndex': trackIndex,
      });

  static Future<Map<String, dynamic>> getState(int playerId) async {
    final raw = await _method.invokeMethod('getState', {'playerId': playerId});
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  static Future<void> dispose(int playerId) async {
    await _method.invokeMethod('dispose', {'playerId': playerId});
  }
}
