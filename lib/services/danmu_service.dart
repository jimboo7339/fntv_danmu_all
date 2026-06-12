import 'package:flutter/foundation.dart';
import '../models/danmu_comment.dart';
import '../providers/app_state.dart';
import 'api_client.dart';

/// 弹幕搜索、解析、缓存。
class DanmuService {
  final ApiClient api;
  final AppState appState;

  DanmuService({required this.api, required this.appState});

  /// 自动匹配并加载弹幕。
  Future<DanmuLoadResult?> loadAuto({
    required String matchName,
    required int episodeNumber,
  }) async {
    final danmuUrl = appState.danmuUrl;
    if (danmuUrl.isEmpty) {
      debugPrint('Danmu: no URL configured');
      return null;
    }

    final cached = appState.getDanmuSource(matchName);
    if (cached != null &&
        cached['episodeNumber'] == episodeNumber &&
        cached['episodeId'] != null) {
      final episodeId = cached['episodeId'] as int;
      debugPrint('Danmu: using cached source for "$matchName" ep=$episodeNumber');
      final comments = await _fetchComments(danmuUrl, episodeId);
      if (comments == null) return null;
      return DanmuLoadResult(
        comments: _postProcess(comments),
        source: Map<String, dynamic>.from(cached),
      );
    }

    return _searchAndLoad(danmuUrl, matchName, episodeNumber);
  }

  /// 从已选弹幕源加载。
  Future<DanmuLoadResult?> loadFromSource(Map<String, dynamic> source) async {
    final danmuUrl = appState.danmuUrl;
    if (danmuUrl.isEmpty) return null;
    final episodeId = source['episodeId'] as int? ?? 0;
    if (episodeId == 0) return null;

    final comments = await _fetchComments(danmuUrl, episodeId);
    if (comments == null) return null;
    return DanmuLoadResult(
      comments: _postProcess(comments),
      source: source,
    );
  }

  Future<DanmuLoadResult?> _searchAndLoad(
    String danmuUrl,
    String matchName,
    int episodeNumber,
  ) async {
    try {
      final searchResp = await api.dio.get(
        '$danmuUrl/api/v2/search/anime',
        queryParameters: {'keyword': matchName},
      );
      if (searchResp.statusCode != 200 || searchResp.data == null) return null;

      final results = _extractList(searchResp.data, const ['animes', 'data', 'bangumi']);
      if (results.isEmpty) return null;

      final first = results[0];
      final animeId = first['animeId'] ?? first['id'] ?? first['bangumiId'] ?? 0;
      final animeName = first['animeName'] ?? first['name'] ?? matchName;
      if (animeId == 0) return null;

      final bangumiResp = await api.dio.get('$danmuUrl/api/v2/bangumi/$animeId');
      if (bangumiResp.statusCode != 200 || bangumiResp.data == null) return null;

      final episodes = _extractEpisodes(bangumiResp.data);
      if (episodes.isEmpty) return null;

      int episodeId = 0;
      int commentCount = 0;
      if (episodeNumber > 0) {
        for (final ep in episodes) {
          final epIdx = _parseEpisodeNum(ep);
          if (epIdx == episodeNumber) {
            episodeId = ep['episodeId'] ?? ep['id'] ?? 0;
            commentCount = ep['commentCount'] ?? 0;
            break;
          }
        }
      }
      if (episodeId == 0) {
        episodeId = episodes[0]['episodeId'] ?? episodes[0]['id'] ?? 0;
        commentCount = episodes[0]['commentCount'] ?? 0;
      }
      if (episodeId == 0) return null;

      final comments = await _fetchComments(danmuUrl, episodeId);
      if (comments == null) return null;

      final sourceData = {
        'animeId': animeId,
        'animeName': animeName,
        'episodeId': episodeId,
        'episodeNumber': episodeNumber,
        'commentCount': commentCount > 0 ? commentCount : comments.length,
      };
      appState.setDanmuSource(matchName, sourceData);

      return DanmuLoadResult(
        comments: _postProcess(comments),
        source: sourceData,
      );
    } catch (e) {
      debugPrint('Danmu search error: $e');
      return null;
    }
  }

  Future<List<DanmuComment>?> _fetchComments(String danmuUrl, int episodeId) async {
    try {
      final resp = await api.dio.get(
        '$danmuUrl/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      if (resp.statusCode != 200 || resp.data == null) return null;

      final rawList = _extractList(resp.data, const ['comments', 'data']);
      return _parseComments(rawList);
    } catch (e) {
      debugPrint('Danmu fetch error: $e');
      return null;
    }
  }

  List<DanmuComment> _parseComments(List<dynamic> comments) {
    final danmuList = <DanmuComment>[];
    for (final c in comments) {
      if (c is! Map) continue;
      final parsed = _parseOneComment(c);
      if (parsed != null) danmuList.add(parsed);
    }
    danmuList.sort((a, b) => a.time.compareTo(b.time));
    return danmuList;
  }

  DanmuComment? _parseOneComment(Map c) {
    final text = c['m']?.toString() ?? c['text']?.toString() ?? c['content']?.toString() ?? '';
    if (text.isEmpty) return null;

    double time = 0;
    int type = 1;
    int color = 0xFFFFFFFF;

    final p = c['p'];
    if (p is String && p.contains(',')) {
      final parts = p.split(',');
      if (parts.isNotEmpty) time = double.tryParse(parts[0]) ?? 0;
      if (parts.length > 1) type = int.tryParse(parts[1]) ?? 1;
      if (parts.length > 2) color = int.tryParse(parts[2]) ?? 0xFFFFFFFF;
    } else if (p is num) {
      time = p.toDouble();
      if (c['c'] != null) color = _parseColor(c['c']);
    } else {
      time = (c['time'] ?? c['time_point'] ?? 0).toDouble();
      type = c['type'] ?? 1;
      if (c['color'] != null) color = _parseColor(c['color']);
    }

    if (color <= 0xFFFFFF) color |= 0xFF000000;
    return DanmuComment(text: text, time: time, color: color, type: type);
  }

  int _parseColor(dynamic cv) {
    if (cv is int) return cv;
    if (cv is String) {
      final s = cv.replaceAll('#', '');
      if (s.length == 6) return int.parse('FF$s', radix: 16);
      if (s.length == 8) return int.parse(s, radix: 16);
      return int.tryParse(cv.replaceAll('#', '0x')) ?? 0xFFFFFFFF;
    }
    return 0xFFFFFFFF;
  }

  List<DanmuComment> _postProcess(List<DanmuComment> danmuList) {
    if (!appState.danmuMergeDuplicates || danmuList.length <= 1) return danmuList;

    final merged = <DanmuComment>[];
    final recentTexts = <String, int>{};
    for (final c in danmuList) {
      final key = c.text;
      final existing = recentTexts[key];
      if (existing != null && (c.time - merged[existing].time).abs() < 2.0) {
        final count = (merged[existing].text.contains(' x ')
                ? int.tryParse(merged[existing].text.split(' x ').last) ?? 1
                : 1) +
            1;
        merged[existing] = DanmuComment(
          text: '$key x $count',
          time: merged[existing].time,
          color: merged[existing].color,
          type: merged[existing].type,
        );
      } else {
        recentTexts[key] = merged.length;
        merged.add(c);
      }
    }
    return merged;
  }

  List<dynamic> _extractList(dynamic raw, List<String> keys) {
    if (raw is List) return raw;
    if (raw is Map) {
      for (final k in keys) {
        if (raw[k] is List) return raw[k] as List;
      }
    }
    return [];
  }

  List<dynamic> _extractEpisodes(dynamic bData) {
    if (bData is! Map) return [];
    if (bData['bangumi'] is Map && bData['bangumi']['episodes'] is List) {
      return bData['bangumi']['episodes'] as List;
    }
    if (bData['episodes'] is List) return bData['episodes'] as List;
    if (bData['data'] is Map && bData['data']['episodes'] is List) {
      return bData['data']['episodes'] as List;
    }
    return [];
  }

  int _parseEpisodeNum(Map ep) {
    final rawNum = ep['episodeNumber'] ?? ep['episodeIndex'] ?? ep['ep'];
    if (rawNum is int) return rawNum;
    if (rawNum is String) return int.tryParse(rawNum) ?? 0;
    return 0;
  }
}

class DanmuLoadResult {
  final List<DanmuComment> comments;
  final Map<String, dynamic> source;

  DanmuLoadResult({required this.comments, required this.source});
}
