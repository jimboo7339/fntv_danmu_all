import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/stream_response.dart';
import '../models/subtitle_data.dart';
import 'api_client.dart';

/// 软件字幕加载：从飞牛服务器提取内嵌字幕并解析为 SubtitleData。
class SubtitleService {
  final ApiClient api;

  SubtitleService(this.api);

  String get _base => '${api.baseUrl}/v';

  static const _fetchTimeout = Duration(seconds: 8);

  /// 自动加载默认字幕轨（并行请求，取最先成功）。
  Future<SubtitleData?> loadDefault({
    required String mediaGuid,
    String? subtitleGuid,
    String? videoGuid,
    List<SubtitleStreamInfo>? streams,
  }) async {
    final urls = <String>[];

    if (subtitleGuid != null && subtitleGuid.isNotEmpty) {
      urls.addAll(_rangeUrls(subtitleGuid));
    }

    if (streams != null && streams.isNotEmpty) {
      var idx = 0;
      for (var i = 0; i < streams.length; i++) {
        final s = streams[i];
        if (subtitleGuid != null && s.guid == subtitleGuid) idx = i;
      }
      urls.addAll(_urlsForStream(
        mediaGuid: mediaGuid,
        streamIndex: idx,
        stream: streams[idx],
        subtitleGuid: subtitleGuid,
        videoGuid: videoGuid,
      ));
    }

    return _fetchFirstSuccess(urls);
  }

  /// 按 stream 列表索引加载指定字幕轨。
  Future<SubtitleData?> loadByStreamIndex({
    required String mediaGuid,
    required int streamIndex,
    SubtitleStreamInfo? stream,
    String? subtitleGuid,
    String? videoGuid,
  }) async {
    final urls = _urlsForStream(
      mediaGuid: mediaGuid,
      streamIndex: streamIndex,
      stream: stream,
      subtitleGuid: subtitleGuid,
      videoGuid: videoGuid,
    );
    return _fetchFirstSuccess(urls);
  }

  List<String> _urlsForStream({
    required String mediaGuid,
    required int streamIndex,
    SubtitleStreamInfo? stream,
    String? subtitleGuid,
    String? videoGuid,
  }) {
    final idx = stream?.index ?? streamIndex;
    final streamGuid = stream?.guid;

    return <String>[
      if (streamGuid != null && streamGuid.isNotEmpty) ..._rangeUrls(streamGuid),
      if (subtitleGuid != null && subtitleGuid.isNotEmpty) ..._rangeUrls(subtitleGuid),
      '$_base/api/v1/media/subtitle/$mediaGuid/$idx',
      '$_base/api/v1/media/subtitle/$mediaGuid/$idx/srt',
      '$_base/api/v1/media/subtitle/$mediaGuid?stream_index=$idx',
      '$_base/api/v1/subtitle/$mediaGuid/$idx',
      '$_base/api/v1/subtitle/$mediaGuid/$idx/stream',
      '$_base/api/v1/subtitle/extract/$mediaGuid?index=$idx',
      ..._rangeUrls(mediaGuid, {'stream_index': idx}),
      ..._rangeUrls(mediaGuid, {'stream_index': idx, 'format': 'srt'}),
      ..._rangeUrls(mediaGuid, {'stream': 'subtitle', 'stream_index': idx}),
      ..._rangeUrls(mediaGuid, {'stream_type': 'subtitle', 'stream_index': idx}),
      ..._rangeUrls(mediaGuid, {'codec_type': 'subtitle', 'index': idx}),
      ..._rangeUrls(mediaGuid, {'subtitle_index': idx}),
      ..._rangeUrls(mediaGuid, {'type': 3, 'index': idx}),
      if (videoGuid != null && videoGuid.isNotEmpty)
        ..._rangeUrls(videoGuid, {'stream_index': idx}),
    ];
  }

  List<String> _rangeUrls(String guid, [Map<String, dynamic>? query]) {
    final q = query ?? const {};
    if (q.isEmpty) return ['$_base/api/v1/media/range/$guid'];
    final qs = q.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
        .join('&');
    return ['$_base/api/v1/media/range/$guid?$qs'];
  }

  Future<SubtitleData?> _fetchFirstSuccess(List<String> urls) async {
    if (urls.isEmpty) return null;
    final seen = <String>{};
    final unique = urls.where(seen.add).toList();

    try {
      return await Future.any(unique.map((url) async {
        final data = await _fetchUrl(url, label: url);
        if (data == null) throw _SubtitleMiss();
        return data;
      }));
    } on _SubtitleMiss {
      return null;
    } catch (_) {
      for (final url in unique) {
        final data = await _fetchUrl(url, label: url);
        if (data != null) return data;
      }
      return null;
    }
  }

  Future<SubtitleData?> _fetchUrl(String url, {String? label}) async {
    try {
      final resp = await api.dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: _fetchTimeout,
          sendTimeout: _fetchTimeout,
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
      if (_looksLikeBinary(content)) return null;

      final data = SubtitleData.parseAuto(content);
      if (data != null && data.isNotEmpty) {
        debugPrint('✅ Subtitle loaded (${data.entries.length} entries)');
        return data;
      }
    } catch (e) {
      debugPrint('Subtitle fetch error: $e');
    }
    return null;
  }

  bool _looksLikeBinary(String content) {
    if (content.length < 4) return false;
    final b0 = content.codeUnitAt(0);
    final b1 = content.codeUnitAt(1);
    final b2 = content.codeUnitAt(2);
    final b3 = content.codeUnitAt(3);
    // MKV / common binary signatures
    if (b0 == 0x1A && b1 == 0x45 && b2 == 0xDF && b3 == 0xA3) return true;
    return false;
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

class _SubtitleMiss implements Exception {}
