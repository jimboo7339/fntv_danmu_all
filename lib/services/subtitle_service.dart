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

  String get _base => '${api.baseUrl}/v';

  /// 自动加载默认字幕轨。
  Future<SubtitleData?> loadDefault({
    required String mediaGuid,
    String? subtitleGuid,
    String? videoGuid,
    List<SubtitleStreamInfo>? streams,
  }) async {
    if (subtitleGuid != null && subtitleGuid.isNotEmpty) {
      for (final url in _rangeUrls(subtitleGuid)) {
        final byGuid = await _fetchUrl(url, label: 'subtitle_guid');
        if (byGuid != null) return byGuid;
      }
    }

    if (streams != null) {
      for (var i = 0; i < streams.length; i++) {
        final data = await loadByStreamIndex(
          mediaGuid: mediaGuid,
          streamIndex: i,
          stream: streams[i],
          subtitleGuid: subtitleGuid,
          videoGuid: videoGuid,
        );
        if (data != null) return data;
      }
    }

    return null;
  }

  /// 按 stream 列表索引加载指定字幕轨。
  Future<SubtitleData?> loadByStreamIndex({
    required String mediaGuid,
    required int streamIndex,
    SubtitleStreamInfo? stream,
    String? subtitleGuid,
    String? videoGuid,
  }) async {
    final idx = stream?.index ?? streamIndex;
    final streamGuid = stream?.guid;

    final urls = <String>[
      if (streamGuid != null && streamGuid.isNotEmpty) ..._rangeUrls(streamGuid),
      if (subtitleGuid != null && subtitleGuid.isNotEmpty) ..._rangeUrls(subtitleGuid),
      ..._rangeUrls(mediaGuid, {
        'stream_index': idx,
      }),
      ..._rangeUrls(mediaGuid, {
        'stream_index': idx,
        'format': 'srt',
      }),
      ..._rangeUrls(mediaGuid, {
        'stream': 'subtitle',
        'stream_index': idx,
      }),
      ..._rangeUrls(mediaGuid, {
        'subtitle_index': idx,
      }),
      ..._rangeUrls(mediaGuid, {
        'type': 3,
        'index': idx,
      }),
      if (videoGuid != null && videoGuid.isNotEmpty) ..._rangeUrls(videoGuid, {
        'stream_index': idx,
      }),
    ];

    for (final url in urls) {
      final data = await _fetchUrl(url, label: url);
      if (data != null) return data;
    }
    return null;
  }

  List<String> _rangeUrls(String guid, [Map<String, dynamic>? query]) {
    final q = query ?? const {};
    if (q.isEmpty) return ['$_base/api/v1/media/range/$guid'];
    final qs = q.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}').join('&');
    return ['$_base/api/v1/media/range/$guid?$qs'];
  }

  Future<SubtitleData?> _fetchUrl(String url, {String? label}) async {
    try {
      final resp = await api.dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          extra: const {'noContentType': true},
          headers: const {
            'Accept': 'text/plain, application/x-subrip, text/vtt, application/json, */*',
          },
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code != 200 && code != 206) {
        if (code >= 400) {
          debugPrint('Subtitle $label HTTP $code');
        }
        return null;
      }

      final raw = resp.data;
      if (raw == null) return null;

      String content;
      if (raw is String) {
        content = raw;
      } else if (raw is List<int>) {
        content = _decodeBytes(raw);
      } else {
        content = raw.toString();
      }

      if (content.trim().isEmpty) return null;

      final data = SubtitleData.parseAuto(content);
      if (data != null && data.isNotEmpty) {
        debugPrint('✅ Subtitle loaded (${data.entries.length} entries) from $label');
        return data;
      }
      debugPrint('⚠️ Subtitle from $label not parseable (${content.length} chars, HTTP $code)');
    } catch (e) {
      debugPrint('Subtitle fetch $label error: $e');
    }
    return null;
  }

  String _decodeBytes(List<int> bytes) {
    var raw = bytes;
    if (raw.length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) {
      raw = raw.sublist(3);
    }
    try {
      return utf8.decode(raw, allowMalformed: true);
    } catch (_) {
      return latin1.decode(raw, allowInvalid: true);
    }
  }
}
