import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/stream_response.dart';
import '../models/subtitle_data.dart';
import 'api_client.dart';

/// ExoPlayer 软件字幕加载：从飞牛服务器提取内嵌字幕并解析为 SubtitleData。
class SubtitleService {
  final ApiClient api;

  SubtitleService(this.api);

  /// 自动加载默认字幕轨（优先 play/info 的 subtitle_guid，否则逐条尝试字幕流）。
  Future<SubtitleData?> loadDefault({
    required String mediaGuid,
    String? subtitleGuid,
    List<SubtitleStreamInfo>? streams,
  }) async {
    if (subtitleGuid != null && subtitleGuid.isNotEmpty) {
      final byGuid = await _fetchAndParse(
        path: 'api/v1/media/range/$subtitleGuid',
        label: 'subtitle_guid',
      );
      if (byGuid != null) return byGuid;
    }

    if (streams != null) {
      for (var i = 0; i < streams.length; i++) {
        final data = await loadByStreamIndex(
          mediaGuid: mediaGuid,
          streamIndex: i,
          stream: streams[i],
        );
        if (data != null) return data;
      }
    }

    return _fetchAndParse(
      path: 'api/v1/media/subtitle/$mediaGuid',
      label: 'media/subtitle',
    );
  }

  /// 按 stream 列表索引加载指定字幕轨。
  Future<SubtitleData?> loadByStreamIndex({
    required String mediaGuid,
    required int streamIndex,
    SubtitleStreamInfo? stream,
  }) async {
    final idx = stream?.index ?? streamIndex;
    final candidates = <_SubtitleRequest>[
      _SubtitleRequest('api/v1/media/range/$mediaGuid', {'stream_index': idx}),
      _SubtitleRequest('api/v1/media/range/$mediaGuid', {'subtitle_index': idx}),
      _SubtitleRequest('api/v1/media/subtitle/$mediaGuid', {'stream_index': idx}),
      _SubtitleRequest('api/v1/subtitle/$mediaGuid', {'stream_index': idx}),
    ];

    for (final req in candidates) {
      final data = await _fetchAndParse(path: req.path, query: req.query, label: req.path);
      if (data != null) return data;
    }
    return null;
  }

  Future<SubtitleData?> _fetchAndParse({
    required String path,
    Map<String, dynamic>? query,
    String? label,
  }) async {
    try {
      final resp = await api.dio.get(
        path,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );
      if (resp.statusCode != 200 || resp.data == null) return null;

      final bytes = resp.data as List<int>;
      if (bytes.isEmpty) return null;

      final content = _decodeBytes(bytes);
      if (content.trim().isEmpty) return null;

      final data = SubtitleData.parseAuto(content);
      if (data != null && data.isNotEmpty) {
        debugPrint('✅ Subtitle loaded (${data.entries.length} entries) from $label');
        return data;
      }
    } catch (e) {
      debugPrint('Subtitle fetch $label error: $e');
    }
    return null;
  }

  String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

class _SubtitleRequest {
  final String path;
  final Map<String, dynamic>? query;
  _SubtitleRequest(this.path, [this.query]);
}
