import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../models/play_info.dart';
import '../models/stream_response.dart';
import '../models/play_list_item.dart';
import '../models/danmu_comment.dart';
import '../models/subtitle_data.dart';
import '../models/watch_record.dart';
import '../utils/format.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/theme.dart';
import '../widgets/danmu_overlay.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/player_controls.dart';
import '../services/video_wrapper.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class PlayerScreen extends StatefulWidget {
  final String itemGuid;
  final String title;
  final String tvTitle;
  final int episodeNumber;
  final String poster;
  final String category;
  final int seekTs;
  final int duration;
  final String? parentGuid;

  const PlayerScreen({
    super.key,
    required this.itemGuid,
    required this.title,
    this.tvTitle = '',
    this.episodeNumber = 0,
    this.poster = '',
    this.category = '',
    this.seekTs = 0,
    this.duration = 0,
    this.parentGuid,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoWrapper? _videoCtrl;
  String _engine = 'mpv';
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isBuffering = false;
  bool _isInitialized = false;

  // Stream info
  String? _mediaGuid;
  String? _episodeGuid;   // play/info 返回的实际 episode GUID
  String? _videoGuid;
  String? _audioGuid;
  String? _subtitleGuid;
  String? _parentGuid;
  String _itemTitle = '';
  String _tvTitle = '';
  int _episodeNumber = 0;
  int _seasonNumber = 1;
  String _actualVideoDecoder = '';
  int _serverSeekTs = 0; // 从 play/info 服务端获取的续播位置（秒）

  // Stream details
  String _streamVCodec = '';
  int _streamVWidth = 0, _streamVHeight = 0;
  int _streamBitrate = 0;
  int _streamDuration = 0;

  // Audio/subtitle streams
  List<AudioStreamInfo>? _audioStreams;
  List<SubtitleStreamInfo>? _subtitleStreams;
  int _selectedAudioIndex = 0;
  int _selectedSubtitleIndex = -1; // -1 = off

  // 软件字幕（ExoPlayer 用）
  SubtitleData? _softwareSubtitle;

  // Direct link
  String _cloudDirectUrl = '';
  bool _cloudDirectMode = true;
  int _qualityIndex = 1;
  int _qualityCount = 0;
  List<String> _qualityLabels = [];
  List<String> _qualityUrls = [];
  bool _isStrmFile = false;

  // Episodes
  List<PlayListItem>? _episodeList;
  int _currentEpIndex = -1;

  // Danmu
  List<DanmuComment> _danmuItems = [];
  bool _danmuOn = true;
  Map<String, dynamic>? _danmuSource; // 当前弹幕源信息

  // Speed
  double _speed = 1.0;
  double _preLongPressSpeed = 1.0; // speed before long press
  bool _isLongPressing = false;

  // Gesture overlay state
  bool _showGestureOverlay = false;
  String _gestureOverlayIcon = '';
  String _gestureOverlayText = '';
  double _gestureOverlayProgress = 0.5; // 0-1
  Timer? _gestureOverlayTimer;

  // Gesture tracking
  double _gestureStartDx = 0;
  double _currentBrightness = 0.5;
  double _currentVolume = 0.5;
  Duration _seekStartPosition = Duration.zero;
  double _seekAccumulator = 0.0;

  Timer? _hideTimer;
  Timer? _progressTimer;
  Timer? _danmuTimer; // 驱动弹幕刷新的定时器

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>(); // Cache before dispose
    _itemTitle = widget.title;
    _tvTitle = widget.tvTitle;
    _episodeNumber = widget.episodeNumber;
    _parentGuid = widget.parentGuid;
    _danmuOn = _appState!.danmuOn;
    _engine = _appState!.playerEngine;
    // Initialize brightness and volume from system
    try {
      ScreenBrightness().current.then((v) { _currentBrightness = v; }).catchError((_) {});
    } catch (_) {}
    try {
      FlutterVolumeController.getVolume().then((v) { if (v != null) _currentVolume = v; }).catchError((_) {});
    } catch (_) {}
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadPlayInfo();
  }

  // Cached AppState reference (safe to use in dispose)
  AppState? _appState;
  AppState get _app => _appState!;

  String get _displayTitle {
    final buf = StringBuffer();
    if (_tvTitle.isNotEmpty) {
      buf.write(_tvTitle);
      if (_episodeNumber > 0) buf.write(' 第$_episodeNumber集');
    } else {
      buf.write(_itemTitle);
    }
    return buf.toString();
  }

  Future<void> _loadPlayInfo() async {
    // 加载保存的倍速
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSpeed = prefs.getDouble('play_speed') ?? 1.0;
      if (savedSpeed > 0) _speed = savedSpeed;
    } catch (_) {}
    try {
      final resp = await _app.api.getPlayInfo(widget.itemGuid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final info = PlayInfoResponse.fromJson(resp['data']);
        _mediaGuid = info.mediaGuid;
        _parentGuid = info.parentGuid ?? _parentGuid;
        _serverSeekTs = info.ts; // 存储服务端续播进度
        _episodeGuid = info.guid; // 存储实际 episode GUID
        _videoGuid = info.videoGuid;
        _audioGuid = info.audioGuid;
        _subtitleGuid = info.subtitleGuid;
        if (info.item != null) {
          if (info.item!.tvTitle != null) _tvTitle = info.item!.tvTitle!;
          _itemTitle = info.item!.title ?? _itemTitle;
          _seasonNumber = info.item!.seasonNumber > 0 ? info.item!.seasonNumber : 1;
          _episodeNumber = info.item!.episodeNumber;
        }
        // 尝试从缓存加载弹幕源信息
        final matchName = _tvTitle.isNotEmpty ? _tvTitle : _itemTitle;
        if (matchName.isNotEmpty) {
          final cached = _app.getDanmuSource(matchName);
          if (cached != null) _danmuSource = cached;
        }
        _loadDanmu();
        await _fetchStreamInfo();
        _startPlayback();
        if (_parentGuid != null && _parentGuid!.isNotEmpty) {
          _loadEpisodes();
        }
      }
    } catch (e) {
      debugPrint('loadPlayInfo error: $e');
    }
  }

  Future<void> _fetchStreamInfo() async {
    if (_mediaGuid == null) return;
    try {
      // ip = 账号的 MD5 哈希（32位十六进制），和原版 app 一致
      final account = _app.currentAccount?.user ?? 'video';
      final ipHash = _md5Hex(account);
      final body = <String, dynamic>{
        'header': {
          'User-Agent': ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36']
        },
        'level': 1,
        'media_guid': _mediaGuid,
        'ip': ipHash,
        'nonce': (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString(),
      };
      final resp = await _app.api.getStream(body);
      if (resp['code'] == 0 && resp['data'] != null) {
        final sd = StreamResponse.fromJson(resp['data']);
        if (sd.videoStream != null) {
          _streamBitrate = sd.videoStream!.bps;
          _streamVCodec = sd.videoStream!.codecName ?? '';
          _streamVWidth = sd.videoStream!.width;
          _streamVHeight = sd.videoStream!.height;
          _streamDuration = sd.videoStream!.duration;
        }
        if (sd.fileStream != null) {
          final fn = sd.fileStream!.fileName ?? '';
          final fp = sd.fileStream!.path ?? '';
          if (_streamDuration <= 0) _streamDuration = sd.fileStream!.duration;
          _isStrmFile = fp.toLowerCase().endsWith('.strm') || fn.toLowerCase().endsWith('.strm');
        }
        if (sd.directLinkQualities != null && sd.directLinkQualities!.isNotEmpty) {
          _qualityCount = sd.directLinkQualities!.length;
          _qualityLabels = sd.directLinkQualities!.map((q) => q.resolution ?? '画质').toList();
          _qualityUrls = sd.directLinkQualities!.map((q) => (q.url ?? '').replaceAll(r'\u0026', '&')).toList();
          if (_qualityIndex >= _qualityCount) _qualityIndex = 0;
          _cloudDirectUrl = _qualityUrls[_qualityIndex];
        }
        // Parse audio/subtitle streams
        if (sd.audioStreams != null && sd.audioStreams!.isNotEmpty) {
          _audioStreams = sd.audioStreams;
          _selectedAudioIndex = 0;
        }
        if (sd.subtitleStreams != null && sd.subtitleStreams!.isNotEmpty) {
          _subtitleStreams = sd.subtitleStreams;
          _selectedSubtitleIndex = -1; // default off
          // ExoPlayer: 尝试自动提取字幕
          if (_engine != 'mpv' && mounted) {
            _tryExtractSubtitle();
          }
        }
      }
    } catch (e) {
      debugPrint('fetchStreamInfo error: $e');
    }
  }

  /// ExoPlayer: 尝试从服务器自动提取字幕
  Future<void> _tryExtractSubtitle() async {
    if (_mediaGuid == null) return;
    try {
      // 尝试多种可能的字幕 API 路径
      final baseUrl = _app.api.baseUrl;
      final endpoints = [
        '$baseUrl/v/api/v1/subtitle/$_mediaGuid',
        '$baseUrl/v/api/v1/media/subtitle/$_mediaGuid',
        '$baseUrl/v/api/v1/media/range/$_mediaGuid?stream=subtitle',
      ];
      for (final url in endpoints) {
        try {
          final resp = await _app.api.dio.get(url,
            options: Options(responseType: ResponseType.plain, validateStatus: (s) => s != null && s < 500),
          );
          if (resp.statusCode == 200 && resp.data is String && resp.data.toString().isNotEmpty) {
            final content = resp.data.toString();
            // 检测格式并解析
            SubtitleData? data;
            if (content.contains('-->')) {
              if (content.trimLeft().startsWith('WEBVTT')) {
                data = SubtitleData.parseVtt(content);
              } else {
                data = SubtitleData.parseSrt(content);
              }
            }
            if (data != null && data.entries.isNotEmpty && mounted) {
              setState(() => _softwareSubtitle = data);
              debugPrint('✅ Auto-loaded ${data.entries.length} subtitle entries from $url');
              return;
            }
          }
        } catch (_) {}
      }
      debugPrint('ℹ️ No server subtitle endpoint found, user can load external SRT');
    } catch (e) {
      debugPrint('Subtitle extraction error: $e');
    }
  }

  /// 加载外部 SRT/VTT 字幕文件
  Future<void> _loadExternalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String? content;
      if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      }
      if (content == null || content.isEmpty) return;

      SubtitleData? data;
      final lower = file.name.toLowerCase();
      if (lower.endsWith('.vtt')) {
        data = SubtitleData.parseVtt(content);
      } else {
        data = SubtitleData.parseSrt(content);
      }

      if (data.entries.isNotEmpty && mounted) {
        setState(() => _softwareSubtitle = data);
        debugPrint('✅ Loaded ${data.entries.length} subtitle entries from ${file.name}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已加载 ${data.entries.length} 条字幕'), duration: const Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('Load subtitle error: $e');
    }
  }

  void _startPlayback() {
    if (_mediaGuid == null) return;
    String url;
    if (_cloudDirectUrl.isNotEmpty) {
      url = _cloudDirectUrl;
    } else if (_cloudDirectMode && _qualityCount > 0) {
      url = _app.api.getMediaUrlWithQuality(_mediaGuid!, _qualityIndex);
    } else {
      url = _app.api.getMediaUrl(_mediaGuid!);
    }
    debugPrint('Playing ($_engine): $url');
    _initVideo(url);
  }

  void _initVideo(String url) {
    _videoCtrl?.dispose();
    _videoCtrl = VideoWrapper(
      engine: _engine,
      url: url,
      headers: _app!.api.headers,
    );
    _videoCtrl!.addListener(_videoListener);
    _videoCtrl!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isInitialized = true);
      _videoCtrl!.setSpeed(_speed);
      // 优先使用 widget.seekTs（详情页传入），其次用 _serverSeekTs（play/info 获取）
      final seekTs = widget.seekTs > 0 ? widget.seekTs : _serverSeekTs;

      if (_engine == 'ijk') {
        // IJK: startIjkPlayback handles setDataSource + play + seek
        final seekMs = seekTs > 0 ? seekTs * 1000 : 0;
        _videoCtrl!.startIjkPlayback(seekMs: seekMs).catchError((e) {
          debugPrint('❌ IJK playback failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('IJK 播放失败: $e'), backgroundColor: Colors.red),
            );
          }
        });
        _isPlaying = true;
      } else {
        _videoCtrl!.play();
        _isPlaying = true;
        if (seekTs > 0) {
          final seekMs = seekTs * 1000;
          debugPrint('🎯 Will seek to ${seekTs}s (${seekMs}ms) — widget=${widget.seekTs}s, server=${_serverSeekTs}s');
          _performSeekWithRetry(seekMs, isMpv: _engine == 'mpv');
        } else {
          debugPrint('ℹ️ No seek needed: widget.seekTs=${widget.seekTs}s, _serverSeekTs=$_serverSeekTs');
        }
      }
      // 立即上报一次进度（不等5秒定时器）
      Future.delayed(const Duration(seconds: 2), () => _saveProgress());
      _startProgressTimer();
      _startDanmuTimer();
      _resetHideTimer();
    });
  }

  void _videoListener() {
    if (_videoCtrl == null || !mounted) return;
    final isBuffering = _videoCtrl!.isBuffering;
    final isPlaying = _videoCtrl!.isPlaying;
    if (isBuffering != _isBuffering || isPlaying != _isPlaying) {
      setState(() {
        _isBuffering = isBuffering;
        _isPlaying = isPlaying;
      });
    }
    // Check if ended
    if (_videoCtrl!.position >= _videoCtrl!.duration &&
        _videoCtrl!.duration.inSeconds > 0) {
      _onPlaybackComplete();
    }
  }

  /// 带重试的 seek — 解决 MPV 首次 seek 被忽略的问题
  void _performSeekWithRetry(int seekMs, {required bool isMpv, int attempt = 0}) {
    if (!mounted || _videoCtrl == null) return;
    const maxAttempts = 4;
    // MPV: 800ms / 2000ms / 4000ms / 6000ms
    // Exo: 200ms / 500ms / 1000ms
    final delays = isMpv ? [800, 2000, 4000, 6000] : [200, 500, 1000, 1500];
    if (attempt >= maxAttempts) {
      debugPrint('❌ Seek failed after $maxAttempts attempts (${seekMs}ms)');
      return;
    }

    Future.delayed(Duration(milliseconds: delays[attempt]), () {
      if (!mounted || _videoCtrl == null) return;
      final currentPosMs = _videoCtrl!.position.inMilliseconds;
      final durMs = _videoCtrl!.duration.inMilliseconds;
      final targetMs = durMs > 0 ? (seekMs.clamp(0, durMs - 1000)).toInt() : seekMs;

      debugPrint('🎯 Seek attempt #${attempt + 1}: target=${targetMs}ms, current=${currentPosMs}ms, dur=${durMs}ms');

      _videoCtrl!.seekTo(Duration(milliseconds: targetMs));

      // 验证 seek 是否生效（仅对 MPV 和后续重试）
      if (isMpv && attempt < maxAttempts - 1) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted || _videoCtrl == null) return;
          final posAfterSeek = _videoCtrl!.position.inMilliseconds;
          final tolerance = (seekMs * 0.1).round().clamp(3000, 10000).toInt(); // 10% tolerance, 3~10s
          final seekWorked = (posAfterSeek - seekMs).abs() < tolerance;
          debugPrint('🎯 Seek verify: posAfter=${posAfterSeek}ms, expected≈${seekMs}ms, worked=$seekWorked');
          if (!seekWorked && posAfterSeek < 5000) {
            // Seek 没生效（位置还在开头），重试
            _performSeekWithRetry(seekMs, isMpv: isMpv, attempt: attempt + 1);
          }
        });
      }
    });
  }

  void _onPlaybackComplete() {
    if (_episodeList != null && _currentEpIndex >= 0 && _currentEpIndex < _episodeList!.length - 1) {
      _playEpisode(_currentEpIndex + 1);
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  void _startDanmuTimer() {
    _danmuTimer?.cancel();
    _danmuTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isPlaying && _danmuOn) {
        setState(() {});
      }
    });
  }

  void _saveProgress({bool force = false}) {
    if (_videoCtrl == null) return;
    if (!force && !mounted) return;
    final pos = _videoCtrl!.position.inSeconds;
    final dur = _videoCtrl!.duration.inSeconds;
    if (dur > 0) {
      _app.addWatchRecord(WatchRecord(
        guid: widget.itemGuid,
        title: _itemTitle,
        tvTitle: _tvTitle,
        episodeNumber: _episodeNumber,
        poster: widget.poster,
        libraryName: widget.category,
        parentGuid: _parentGuid,
        ts: pos,
        duration: dur,
      ));
      // 同步上报服务端（用于继续观看列表）
      // 必须用 play/info 返回的实际 episode GUID，不能用 widget.itemGuid（可能是 TV/Season 的）
      final episodeGuid = _episodeGuid ?? widget.itemGuid;
      _app.api.recordPlayStatus({
        'item_guid': episodeGuid,
        'media_guid': _mediaGuid ?? '',
        'video_guid': _videoGuid ?? '',
        'audio_guid': _audioGuid ?? '',
        'subtitle_guid': _subtitleGuid ?? '',
        'resolution': '原画',
        'bitrate': 0,
        'ts': pos,
        'duration': dur,
      }).catchError((e) {
        debugPrint('❌ recordPlayStatus error: $e (item=$episodeGuid, media=${_mediaGuid ?? ""}, ts=$pos, dur=$dur)');
      });
    }
  }

  Future<void> _loadDanmu() async {
    final matchName = _tvTitle.isNotEmpty ? _tvTitle : _itemTitle;
    if (matchName.isEmpty) return;
    try {
      final danmuUrl = _app.danmuUrl;
      if (danmuUrl.isEmpty) {
        debugPrint('Danmu: no URL configured');
        return;
      }

      // 尝试从缓存读取弹幕源
      final cached = _app.getDanmuSource(matchName);
      int targetEpisodeId = 0;
      String cachedAnimeName = '';
      int cachedAnimeId = 0;
      if (cached != null && cached['episodeNumber'] == _episodeNumber && cached['episodeId'] != null) {
        targetEpisodeId = cached['episodeId'] as int;
        cachedAnimeName = cached['animeName']?.toString() ?? matchName;
        cachedAnimeId = cached['animeId'] as int? ?? 0;
        debugPrint('Danmu: using cached source for "$matchName" ep=$_episodeNumber, episodeId=$targetEpisodeId');
      }

      int episodeId = targetEpisodeId;
      String animeName = cachedAnimeName;
      int animeId = cachedAnimeId;
      int commentCount = 0;

      if (episodeId == 0) {
        // 没有缓存，走完整搜索流程
        String searchKw = matchName;
        int targetEp = _episodeNumber;
        debugPrint('Danmu: searching "$searchKw" ep=$targetEp from $danmuUrl');

        // 1. 搜索动画
        final searchResp = await _app.api.dio.get(
          '$danmuUrl/api/v2/search/anime',
          queryParameters: {'keyword': searchKw},
        );
        if (searchResp.statusCode != 200 || searchResp.data == null) {
          debugPrint('Danmu: search failed');
          return;
        }

        List<dynamic> results = [];
        final raw = searchResp.data;
        if (raw is List) {
          results = raw;
        } else if (raw is Map && raw['animes'] is List) {
          results = raw['animes'] as List;
        } else if (raw is Map && raw['data'] is List) {
          results = raw['data'] as List;
        } else if (raw is Map && raw['bangumi'] is List) {
          results = raw['bangumi'] as List;
        }
        if (results.isEmpty) {
          debugPrint('Danmu: no search results for "$searchKw"');
          return;
        }
        debugPrint('Danmu: found ${results.length} anime(s)');

        final first = results[0];
        animeId = first['animeId'] ?? first['id'] ?? first['bangumiId'] ?? 0;
        animeName = first['animeName'] ?? first['name'] ?? matchName;
        if (animeId == 0) {
          debugPrint('Danmu: no valid anime ID');
          return;
        }
        debugPrint('Danmu: found anime id=$animeId name=$animeName');

        // 2. 获取动画详情（含剧集列表）
        final bangumiResp = await _app.api.dio.get('$danmuUrl/api/v2/bangumi/$animeId');
        if (bangumiResp.statusCode != 200 || bangumiResp.data == null) {
          debugPrint('Danmu: bangumi fetch failed');
          return;
        }

        List<dynamic> episodes = [];
        final bData = bangumiResp.data;
        if (bData is Map) {
          if (bData['bangumi'] is Map && bData['bangumi']['episodes'] is List) {
            episodes = bData['bangumi']['episodes'] as List;
          } else if (bData['episodes'] is List) {
            episodes = bData['episodes'] as List;
          } else if (bData['data'] is Map && bData['data']['episodes'] is List) {
            episodes = bData['data']['episodes'] as List;
          }
        }
        if (episodes.isEmpty) {
          debugPrint('Danmu: no episodes found');
          return;
        }

        // 3. 匹配目标集数
        if (targetEp > 0) {
          for (final ep in episodes) {
            final rawNum = ep['episodeNumber'] ?? ep['episodeIndex'] ?? ep['ep'];
            int epIdx = 0;
            if (rawNum is int) {
              epIdx = rawNum;
            } else if (rawNum is String) {
              epIdx = int.tryParse(rawNum) ?? 0;
            }
            if (epIdx == targetEp) {
              episodeId = ep['episodeId'] ?? ep['id'] ?? 0;
              commentCount = ep['commentCount'] ?? 0;
              break;
            }
          }
        }
        if (episodeId == 0 && episodes.isNotEmpty) {
          episodeId = episodes[0]['episodeId'] ?? episodes[0]['id'] ?? 0;
          commentCount = episodes[0]['commentCount'] ?? 0;
        }
        if (episodeId == 0) {
          debugPrint('Danmu: no matching episode');
          return;
        }
        debugPrint('Danmu: matched episodeId=$episodeId');
      }

      // 4. 获取弹幕评论
      final commentResp = await _app.api.dio.get(
        '$danmuUrl/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      if (commentResp.statusCode != 200 || commentResp.data == null) {
        debugPrint('Danmu: comment fetch failed');
        return;
      }

      // 解析弹幕
      List<dynamic> comments = [];
      final cData = commentResp.data;
      if (cData is List) {
        comments = cData;
      } else if (cData is Map && cData['comments'] is List) {
        comments = cData['comments'] as List;
      } else if (cData is Map && cData['data'] is List) {
        comments = cData['data'] as List;
      }

      // 解析弹幕格式：m=文本, p="时间,模式,颜色,用户ID"
      var danmuList = <DanmuComment>[];
      for (final c in comments) {
        if (c is! Map) continue;
        final text = c['m']?.toString() ?? c['text']?.toString() ?? c['content']?.toString() ?? '';
        if (text.isEmpty) continue;

        double time = 0;
        int type = 1;
        int color = 0xFFFFFFFF;

        final p = c['p'];
        if (p is String && p.contains(',')) {
          // 标准格式: "12.5,1,16777215,uid123"
          final parts = p.split(',');
          if (parts.isNotEmpty) time = double.tryParse(parts[0]) ?? 0;
          if (parts.length > 1) type = int.tryParse(parts[1]) ?? 1;
          if (parts.length > 2) color = int.tryParse(parts[2]) ?? 0xFFFFFFFF;
        } else if (p is num) {
          time = p.toDouble();
          // 颜色可能在 c 字段
          if (c['c'] != null) {
            final cv = c['c'];
            if (cv is int) color = cv;
            else if (cv is String) color = int.tryParse(cv.replaceAll('#', '0x')) ?? 0xFFFFFFFF;
          }
        } else {
          // 回退到通用字段
          time = (c['time'] ?? c['time_point'] ?? 0).toDouble();
          type = c['type'] ?? 1;
          if (c['color'] != null) {
            final cv = c['color'];
            if (cv is int) color = cv;
            else if (cv is String) {
              final s = cv.replaceAll('#', '');
              if (s.length == 6) color = int.parse('FF$s', radix: 16);
              else if (s.length == 8) color = int.parse(s, radix: 16);
            }
          }
        }

        // 确保颜色有alpha通道（API返回的0xFFFFFF实际是0x00FFFFFF=透明）
        if (color <= 0xFFFFFF) color |= 0xFF000000;

        danmuList.add(DanmuComment(text: text, time: time, color: color, type: type));
      }

      debugPrint('Danmu: loaded ${danmuList.length} comments');
      if (commentCount == 0) commentCount = danmuList.length;
      // 缓存弹幕源信息
      final sourceData = {
        'animeId': animeId,
        'animeName': animeName,
        'episodeId': episodeId,
        'episodeNumber': _episodeNumber,
        'commentCount': commentCount,
      };
      _app.setDanmuSource(matchName, sourceData);
      if (mounted) setState(() => _danmuSource = sourceData);
      // 必须按时间排序，渲染器假设已排序（遇到未来时间会break）
      danmuList.sort((a, b) => a.time.compareTo(b.time));
      // 合并重复弹幕
      if (_app.danmuMergeDuplicates && danmuList.length > 1) {
        final merged = <DanmuComment>[];
        final Map<String, int> recentTexts = {}; // text -> index in merged
        for (final c in danmuList) {
          final key = c.text;
          final existing = recentTexts[key];
          if (existing != null && (c.time - merged[existing].time).abs() < 2.0) {
            // 合并：替换文本加上计数
            final count = (merged[existing].text.contains(' x ') 
                ? int.tryParse(merged[existing].text.split(' x ').last) ?? 1 
                : 1) + 1;
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
        debugPrint('Danmu: merged ${danmuList.length} -> ${merged.length}');
        danmuList = merged;
      }
      if (mounted && danmuList.isNotEmpty) {
        setState(() => _danmuItems = danmuList);
      }
    } catch (e) {
      debugPrint('loadDanmu error: $e');
    }
  }

  /// 从指定的弹幕源加载弹幕（手动选择后调用）
  Future<void> _loadDanmuFromSource(Map<String, dynamic> source) async {
    try {
      final danmuUrl = _app.danmuUrl;
      if (danmuUrl.isEmpty) return;
      final episodeId = source['episodeId'] as int? ?? 0;
      if (episodeId == 0) return;
      
      debugPrint('Danmu: loading from source episodeId=$episodeId');
      final commentResp = await _app.api.dio.get(
        '$danmuUrl/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      if (commentResp.statusCode != 200 || commentResp.data == null) return;

      List<dynamic> comments = [];
      final cData = commentResp.data;
      if (cData is List) {
        comments = cData;
      } else if (cData is Map && cData['comments'] is List) {
        comments = cData['comments'] as List;
      } else if (cData is Map && cData['data'] is List) {
        comments = cData['data'] as List;
      }

      var danmuList = <DanmuComment>[];
      for (final c in comments) {
        if (c is! Map) continue;
        final text = c['m']?.toString() ?? c['text']?.toString() ?? c['content']?.toString() ?? '';
        if (text.isEmpty) continue;

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
        } else {
          time = (c['time'] ?? c['time_point'] ?? 0).toDouble();
          type = c['type'] ?? 1;
        }

        if (color <= 0xFFFFFF) color |= 0xFF000000;
        danmuList.add(DanmuComment(text: text, time: time, color: color, type: type));
      }

      danmuList.sort((a, b) => a.time.compareTo(b.time));
      if (_app.danmuMergeDuplicates && danmuList.length > 1) {
        final merged = <DanmuComment>[];
        final Map<String, int> recentTexts = {};
        for (final c in danmuList) {
          final key = c.text;
          final existing = recentTexts[key];
          if (existing != null && (c.time - merged[existing].time).abs() < 2.0) {
            final count = (merged[existing].text.contains(' x ')
                ? int.tryParse(merged[existing].text.split(' x ').last) ?? 1
                : 1) + 1;
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
        danmuList = merged;
      }

      debugPrint('Danmu: loaded ${danmuList.length} from manual source');
      if (mounted && danmuList.isNotEmpty) {
        setState(() => _danmuItems = danmuList);
      }
    } catch (e) {
      debugPrint('loadDanmuFromSource error: $e');
    }
  }

  Future<void> _loadEpisodes() async {
    if (_parentGuid == null) return;
    try {
      final resp = await _app.api.getEpisodeList(_parentGuid!);
      if (resp['code'] == 0 && resp['data'] != null) {
        final list = (resp['data'] as List).map((e) => PlayListItem.fromJson(e)).toList();
        setState(() {
          _episodeList = list;
          _currentEpIndex = list.indexWhere((e) => e.guid == widget.itemGuid);
          if (_currentEpIndex < 0) {
            _currentEpIndex = list.indexWhere((e) => e.episodeNumber == _episodeNumber);
          }
        });
      }
    } catch (e) {
      debugPrint('loadEpisodes error: $e');
    }
  }

  void _playEpisode(int index) {
    if (_episodeList == null || index < 0 || index >= _episodeList!.length) return;
    final ep = _episodeList![index];
    setState(() {
      _currentEpIndex = index;
      _itemTitle = ep.title ?? '';
      _episodeNumber = ep.episodeNumber;
      _mediaGuid = null;
      _cloudDirectUrl = '';
      _isInitialized = false;
      _danmuItems.clear();
      _audioStreams = null;
      _subtitleStreams = null;
      _selectedAudioIndex = 0;
      _selectedSubtitleIndex = -1;
    });
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _loadPlayInfoForItem(ep.guid);
  }

  Future<void> _loadPlayInfoForItem(String guid) async {
    try {
      final resp = await _app.api.getPlayInfo(guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final info = PlayInfoResponse.fromJson(resp['data']);
        _mediaGuid = info.mediaGuid;
        _episodeGuid = info.guid;
        _videoGuid = info.videoGuid;
        _audioGuid = info.audioGuid;
        _subtitleGuid = info.subtitleGuid;
        await _fetchStreamInfo();
        _startPlayback();
        _loadDanmu();
      }
    } catch (e) {
      debugPrint('loadPlayInfoForItem error: $e');
    }
  }

  void _togglePlay() {
    if (_videoCtrl == null) return;
    if (_isPlaying) {
      _videoCtrl!.pause();
    } else {
      _videoCtrl!.play();
    }
  }

  void _seek(Duration offset) {
    if (_videoCtrl == null) return;
    final newPos = _videoCtrl!.position + offset;
    _videoCtrl!.seekTo(newPos);
  }

  void _setSpeed(double speed) {
    _speed = speed;
    _videoCtrl?.setSpeed(_speed);
    setState(() {});
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('play_speed', _speed);
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    setState(() => _showControls = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gestureOverlayTimer?.cancel();
    _progressTimer?.cancel();
    _saveProgress(force: true); // 退出时强制上报最终进度
    _danmuTimer?.cancel();
    _videoCtrl?.removeListener(_videoListener);
    _videoCtrl?.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _showGestureOverlayWith(String icon, String text, double progress) {
    _gestureOverlayTimer?.cancel();
    setState(() {
      _showGestureOverlay = true;
      _gestureOverlayIcon = icon;
      _gestureOverlayText = text;
      _gestureOverlayProgress = progress;
    });
  }

  void _hideGestureOverlay() {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // watch AppState so subtitle style changes trigger rebuild (real-time preview)
    final appState = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_isLocked) return;
          if (_showControls) {
            setState(() => _showControls = false);
          } else {
            _resetHideTimer();
          }
        },
        onDoubleTapDown: (details) {
          if (_isLocked) return;
          final w = MediaQuery.of(context).size.width;
          final dx = details.globalPosition.dx;
          if (dx < w / 3) {
            _seek(const Duration(seconds: -10));
          } else if (dx > w * 2 / 3) {
            _seek(const Duration(seconds: 10));
          } else {
            _togglePlay();
          }
        },
        onVerticalDragStart: (details) {
          if (_isLocked) return;
          _gestureStartDx = details.globalPosition.dx;
        },
        onVerticalDragUpdate: (details) {
          if (_isLocked) return;
          final screenW = MediaQuery.of(context).size.width;
          final isLeftSide = _gestureStartDx < screenW / 2;
          // Sensitivity: full screen height = 0-100%
          final delta = -details.delta.dy / 200; // positive = up
          if (isLeftSide) {
            _currentBrightness = (_currentBrightness + delta).clamp(0.0, 1.0);
            _showGestureOverlayWith(
              '☀', '${(_currentBrightness * 100).toInt()}%', _currentBrightness);
            try { ScreenBrightness().setScreenBrightness(_currentBrightness); } catch (_) {}
          } else {
            _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
            _showGestureOverlayWith(
              '🔊', '${(_currentVolume * 100).toInt()}%', _currentVolume);
            try { FlutterVolumeController.setVolume(_currentVolume); } catch (_) {}
          }
        },
        onVerticalDragEnd: (_) => _hideGestureOverlay(),
        onHorizontalDragStart: (details) {
          if (_isLocked) return;
          _seekStartPosition = _videoCtrl?.position ?? Duration.zero;
          _seekAccumulator = 0.0;
        },
        onHorizontalDragUpdate: (details) {
          if (_isLocked) return;
          // 1 pixel ≈ 200ms
          _seekAccumulator += details.delta.dx * 200;
          final dur = _videoCtrl?.duration ?? Duration.zero;
          final pos = _seekStartPosition + Duration(milliseconds: _seekAccumulator.toInt());
          final clampedMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds);
          final progress = dur.inMilliseconds > 0 ? clampedMs / dur.inMilliseconds : 0.0;
          final current = Duration(milliseconds: clampedMs);
          _showGestureOverlayWith(
            details.delta.dx > 0 ? '⏩' : '⏪',
            '${_formatDuration(current)} / ${_formatDuration(dur)}',
            progress);
        },
        onHorizontalDragEnd: (details) {
          if (_isLocked) return;
          final dur = _videoCtrl?.duration ?? Duration.zero;
          final pos = _seekStartPosition + Duration(milliseconds: _seekAccumulator.toInt());
          final clampedMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds);
          _videoCtrl?.seekTo(Duration(milliseconds: clampedMs));
          _hideGestureOverlay();
        },
        onLongPressStart: (_) {
          if (_isLocked) return;
          _isLongPressing = true;
          _preLongPressSpeed = _speed;
          final longSpeed = _app.danmuLongPressSpeed;
          _setSpeed(longSpeed);
          _showGestureOverlayWith('⚡', '${longSpeed}x 倍速', 1.0);
        },
        onLongPressEnd: (_) {
          if (!_isLongPressing) return;
          _isLongPressing = false;
          _setSpeed(_preLongPressSpeed);
          _hideGestureOverlay();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            Center(
              child: _isInitialized && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.aspectRatio,
                      child: _videoCtrl!.buildVideo(
                        subtitleSize: appState.subtitleSize,
                        subtitleOutline: appState.subtitleOutline,
                        subtitleBackground: appState.subtitleBackground,
                        subtitleColor: Color(appState.subtitleColorValue),
                        subtitleWeight: appState.subtitleWeight,
                      ),
                    )
                  : const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen)),
            ),

            // Buffering indicator
            if (_isBuffering)
              const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen, strokeWidth: 3)),

            // Danmu overlay
            if (_danmuOn && _isPlaying)
              DanmuOverlay(
                comments: _danmuItems,
                currentTime: _videoCtrl?.position.inMilliseconds.toDouble() ?? 0,
                opacity: _app.danmuOpacity,
                fontSize: _app.danmuFontSize,
                areaPercent: _app.danmuArea,
                showOutline: _app.danmuOutline,
                speed: _app.danmuSpeed,
                danmuDensity: _app.danmuDensity / 100.0,
                topMargin: _app.danmuTopMargin,
              ),

            // 软件字幕覆盖层（ExoPlayer 用）
            if (_softwareSubtitle != null && _softwareSubtitle!.isNotEmpty)
              SubtitleOverlay(
                subtitleData: _softwareSubtitle,
                currentPosition: _videoCtrl?.position ?? Duration.zero,
                fontSize: appState.subtitleSize,
                outline: appState.subtitleOutline,
                showBackground: appState.subtitleBackground,
                color: Color(appState.subtitleColorValue),
                bottomMargin: appState.subtitleBottomMargin,
              ),

            // Controls
            if (_showControls)
              PlayerControls(
                title: _displayTitle,
                isPlaying: _isPlaying,
                isLocked: _isLocked,
                speed: _speed,
                position: _videoCtrl?.position ?? Duration.zero,
                duration: _videoCtrl?.duration ?? Duration.zero,
                episodeList: _episodeList,
                currentEpIndex: _currentEpIndex,
                danmuOn: _danmuOn,
                qualityCount: _qualityCount,
                qualityLabels: _qualityLabels,
                qualityIndex: _qualityIndex,
                audioStreams: _audioStreams,
                subtitleStreams: _subtitleStreams,
                selectedAudioIndex: _selectedAudioIndex,
                selectedSubtitleIndex: _selectedSubtitleIndex,
                onPlayPause: _togglePlay,
                onSeek: _seek,
                onSpeed: _setSpeed,
                onLock: () => setState(() {
                  _isLocked = !_isLocked;
                  if (_isLocked) _showControls = false;
                }),
                onDanmu: () {
                  setState(() => _danmuOn = !_danmuOn);
                  if (_danmuOn) {
                    _startDanmuTimer();
                  } else {
                    _danmuTimer?.cancel();
                  }
                },
                onBack: () {
                  // 返回前强制恢复竖屏
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.portraitDown,
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]);
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                  Navigator.pop(context);
                },
                onEpisode: _playEpisode,
                onQuality: (idx) {
                  setState(() {
                    _qualityIndex = idx;
                    _cloudDirectUrl = _qualityUrls[idx];
                  });
                  _videoCtrl?.dispose();
                  _videoCtrl = null;
                  setState(() => _isInitialized = false);
                  _startPlayback();
                },
                onAudioSelected: (idx) {
                  setState(() => _selectedAudioIndex = idx);
                  _videoCtrl?.setAudioTrack(idx);
                },
                onSubtitleSelected: (idx) {
                  setState(() => _selectedSubtitleIndex = idx);
                  _videoCtrl?.setSubtitleTrack(idx);
                },
                onSeekChanged: (val) {
                  _videoCtrl?.seekTo(Duration(milliseconds: val.toInt()));
                },
                showName: _tvTitle.isNotEmpty ? _tvTitle : _itemTitle,
                currentDanmuSource: _danmuSource,
                onDanmuSourceSelected: (data) {
                  // 用户手动选择了弹幕源，保存并重新加载
                  final matchName = _tvTitle.isNotEmpty ? _tvTitle : _itemTitle;
                  if (matchName.isNotEmpty) {
                    _app.setDanmuSource(matchName, data);
                    setState(() {
                      _danmuSource = data;
                      _danmuItems.clear();
                    });
                    _loadDanmuFromSource(data);
                  }
                },
                onLoadExternalSubtitle: _loadExternalSubtitle,
                useMpv: _engine == 'mpv',
              ),

            // Lock button (always visible)
            Positioned(
              right: 16,
              top: 0, bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isLocked = !_isLocked;
                    if (!_isLocked) _resetHideTimer();
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

            // Engine indicator (only show when controls visible)
            if (_showControls)
            Positioned(
              left: 16, top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _engine == 'mpv' ? 'MPV' : (_engine == 'ijk' ? 'IJK' : 'Exo'),
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            // Gesture overlay (brightness / volume / seek / speed)
            if (_showGestureOverlay)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_gestureOverlayIcon, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(_gestureOverlayText,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _gestureOverlayProgress,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(FnTheme.danmuGreen),
                            minHeight: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}
