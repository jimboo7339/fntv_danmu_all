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

  /// 自动加载默认字幕轨。
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
    final streamGuid = stream?.guid;

    final candidates = <_SubtitleRequest>[
      if (streamGuid != null && streamGuid.isNotEmpty)
        _SubtitleRequest('api/v1/media/range/$streamGuid'),
      _SubtitleRequest('api/v1/media/range/$mediaGuid', {'stream_index': idx}),
      _SubtitleRequest('api/v1/media/range/$mediaGuid', {'subtitle_index': idx}),
      _SubtitleRequest('api/v1/media/range/$mediaGuid', {'stream_index': idx, 'format': 'srt'}),
      _SubtitleRequest('api/v1/media/subtitle/$mediaGuid', {'stream_index': idx}),
      _SubtitleRequest('api/v1/media/subtitle/$mediaGuid', {'index': idx}),
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
          headers: const {'Accept': 'text/plain, application/json, */*'},
        ),
      );
      if (resp.statusCode != 200 || resp.data == null) return null;

      final bytes = resp.data as List<int>;
      if (bytes.isEmpty) return null;

      final content = _extractText(bytes);
      if (content == null || content.trim().isEmpty) return null;

      final data = SubtitleData.parseAuto(content);
      if (data != null && data.isNotEmpty) {
        debugPrint('✅ Subtitle loaded (${data.entries.length} entries) from $label');
        return data;
      }
      debugPrint('⚠️ Subtitle response from $label could not be parsed (${content.length} chars)');
    } catch (e) {
      debugPrint('Subtitle fetch $label error: $e');
    }
    return null;
  }

  String? _extractText(List<int> bytes) {
    // UTF-8 BOM
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
      raw = raw.sublist(3);
    }

    String text;
    try {
      text = utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      text = latin1.decode(raw, allowInvalid: true);
    }

    text = text.trim();
    if (text.isEmpty) return null;

    // JSON 包装
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        final fromJson = _textFromJson(decoded);
        if (fromJson != null && fromJson.trim().isNotEmpty) return fromJson;
      } catch (_) {}
    }

    return text;
  }

  String? _textFromJson(dynamic decoded) {
    if (decoded is String) return decoded;
    if (decoded is List) {
      for (final item in decoded) {
        final t = _textFromJson(item);
        if (t != null && t.contains('-->')) return t;
      }
      return null;
    }
    if (decoded is! Map) return null;

    if (decoded['code'] != null && decoded['code'] != 0) return null;

    for (final key in ['data', 'content', 'subtitle', 'text', 'body']) {
      final v = decoded[key];
      if (v == null) continue;
      final t = _textFromJson(v);
      if (t != null && t.trim().isNotEmpty) return t;
    }
    return null;
  }
}

class _SubtitleRequest {
  final String path;
  final Map<String, dynamic>? query;
  _SubtitleRequest(this.path, [this.query]);
}
