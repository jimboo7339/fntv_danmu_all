import 'package:flutter/services.dart';

/// Minimal ijkplayer bridge via method channel.
class IjkPlayer {
  static const _channel = MethodChannel('fntv_ijkplayer');

  int _textureId = -1;
  int get textureId => _textureId;
  bool _disposed = false;

  // State callbacks
  void Function(int positionMs, int durationMs)? onPosition;
  void Function()? onCompleted;

  IjkPlayer() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<int> create() async {
    final result = await _channel.invokeMethod('create');
    _textureId = result['textureId'] as int;
    return _textureId;
  }

  Future<void> setDataSource(String url, {Map<String, String>? headers, int seekMs = 0}) async {
    await _channel.invokeMethod('setDataSource', {
      'url': url,
      'headers': headers ?? {},
      'seekMs': seekMs,
    });
  }

  Future<void> play() => _channel.invokeMethod('play');
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> seekTo(int ms) => _channel.invokeMethod('seekTo', {'positionMs': ms});
  Future<void> setSpeed(double speed) => _channel.invokeMethod('setSpeed', {'speed': speed});

  Future<int> getPosition() async =>
      (await _channel.invokeMethod('getPosition') as int?) ?? 0;
  Future<int> getDuration() async =>
      (await _channel.invokeMethod('getDuration') as int?) ?? 0;
  Future<bool> getIsPlaying() async =>
      (await _channel.invokeMethod('isPlaying') as bool?) ?? false;

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case 'onPosition':
        final args = call.arguments as Map;
        onPosition?.call(args['position'] as int, args['duration'] as int);
      case 'onCompleted':
        onCompleted?.call();
    }
  }

  Future<void> release() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {}
  }
}
