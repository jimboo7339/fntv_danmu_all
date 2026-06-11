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
import '../models/watch_record.dart';
import '../utils/format.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/theme.dart';
import '../widgets/danmu_overlay.dart';
import '../widgets/player_controls.dart';
import '../services/video_wrapper.dart';

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
  bool _useMpv = true;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isBuffering = false;
  bool _isInitialized = false;

  // Stream info
  String? _mediaGuid;
  String? _parentGuid;
  String _itemTitle = '';
  String _tvTitle = '';
  int _episodeNumber = 0;
  int _seasonNumber = 1;
  String _actualVideoDecoder = '';

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

  // Speed
  double _speed = 1.0;

  Timer? _hideTimer;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _itemTitle = widget.title;
    _tvTitle = widget.tvTitle;
    _episodeNumber = widget.episodeNumber;
    _parentGuid = widget.parentGuid;
    final app = context.read<AppState>();
    _danmuOn = app.danmuOn;
    _useMpv = app.playerEngine == 'mpv';
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadPlayInfo();
  }

  AppState get _app => context.read<AppState>();

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
        if (info.item != null) {
          if (info.item!.tvTitle != null) _tvTitle = info.item!.tvTitle!;
          _itemTitle = info.item!.title ?? _itemTitle;
          _seasonNumber = info.item!.seasonNumber > 0 ? info.item!.seasonNumber : 1;
          _episodeNumber = info.item!.episodeNumber;
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
        }
      }
    } catch (e) {
      debugPrint('fetchStreamInfo error: $e');
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
    debugPrint('Playing (${_useMpv ? 'mpv' : 'exo'}): $url');
    _initVideo(url);
  }

  void _initVideo(String url) {
    _videoCtrl?.dispose();
    _videoCtrl = VideoWrapper(useMpv: _useMpv, url: url);
    _videoCtrl!.addListener(_videoListener);
    _videoCtrl!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isInitialized = true);
      _videoCtrl!.setSpeed(_speed);
      if (widget.seekTs > 0) {
        _videoCtrl!.seekTo(Duration(seconds: widget.seekTs));
      }
      _videoCtrl!.play();
      _isPlaying = true;
      _startProgressTimer();
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

  void _saveProgress() {
    if (_videoCtrl == null || !mounted) return;
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
      // 搜索关键词：剧名 + S01E03 格式
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

      // 解析搜索结果（可能是数组或 {data: [...]} 结构）
      List<dynamic> results = [];
      final raw = searchResp.data;
      if (raw is List) {
        results = raw;
      } else if (raw is Map && raw['data'] is List) {
        results = raw['data'] as List;
      } else if (raw is Map && raw['bangumi'] is List) {
        results = raw['bangumi'] as List;
      }
      if (results.isEmpty) {
        debugPrint('Danmu: no search results for "$searchKw"');
        return;
      }

      // 取第一个结果的 ID
      final animeId = results[0]['id'] ?? results[0]['bangumiId'] ?? 0;
      if (animeId == 0) {
        debugPrint('Danmu: no valid anime ID');
        return;
      }
      debugPrint('Danmu: found anime id=$animeId');

      // 2. 获取动画详情（含剧集列表）
      final bangumiResp = await _app.api.dio.get('$danmuUrl/api/v2/bangumi/$animeId');
      if (bangumiResp.statusCode != 200 || bangumiResp.data == null) {
        debugPrint('Danmu: bangumi fetch failed');
        return;
      }

      // 解析剧集列表
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
      int episodeId = 0;
      if (targetEp > 0) {
        for (final ep in episodes) {
          final epIdx = ep['episodeIndex'] ?? ep['ep'] ?? 0;
          if (epIdx == targetEp) {
            episodeId = ep['episodeId'] ?? ep['id'] ?? 0;
            break;
          }
        }
      }
      // 没匹配到就用第一集
      if (episodeId == 0 && episodes.isNotEmpty) {
        episodeId = episodes[0]['episodeId'] ?? episodes[0]['id'] ?? 0;
      }
      if (episodeId == 0) {
        debugPrint('Danmu: no matching episode');
        return;
      }
      debugPrint('Danmu: matched episodeId=$episodeId');

      // 4. 获取弹幕评论（必须加 ?format=json）
      final commentResp = await _app.api.dio.get('$danmuUrl/api/v2/comment/$episodeId?format=json');
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
      final danmuList = <DanmuComment>[];
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

        danmuList.add(DanmuComment(text: text, time: time, color: color, type: type));
      }

      debugPrint('Danmu: loaded ${danmuList.length} comments');
      if (mounted && danmuList.isNotEmpty) {
        setState(() => _danmuItems = danmuList);
      }
    } catch (e) {
      debugPrint('loadDanmu error: $e');
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
    _progressTimer?.cancel();
    _saveProgress();
    _videoCtrl?.removeListener(_videoListener);
    _videoCtrl?.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            Center(
              child: _isInitialized && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.aspectRatio,
                      child: _videoCtrl!.buildVideo(),
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
                onDanmu: () => setState(() => _danmuOn = !_danmuOn),
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
                  _useMpv ? 'MPV' : 'Exo',
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
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
