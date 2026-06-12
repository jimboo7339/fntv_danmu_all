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
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/theme.dart';
import '../utils/toast.dart';
import '../widgets/danmu_overlay.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/player_controls.dart';
import '../services/video_wrapper.dart';
import '../services/danmu_service.dart';
import '../services/subtitle_service.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
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
  final String logoUrl;

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
    this.logoUrl = '',
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
  String _logoUrl = '';
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

  // 画面比例 / 屏幕方向
  String _aspectMode = 'fit';
  bool _preferPortrait = false;

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

  late DanmuService _danmuService;
  late SubtitleService _subtitleService;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>(); // Cache before dispose
    _danmuService = DanmuService(api: _appState!.api, appState: _appState!);
    _subtitleService = SubtitleService(_appState!.api);
    _itemTitle = widget.title;
    _tvTitle = widget.tvTitle;
    _logoUrl = widget.logoUrl;
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

  String get _headerTitle => _tvTitle.isNotEmpty ? _tvTitle : _itemTitle;

  String _logoUrlFromItem(ItemInfo? item) {
    if (item == null) return _logoUrl;
    final logo = item.logos ?? item.logo;
    if (logo != null && logo.isNotEmpty) {
      return _app.api.getImageUrl(logo, width: 500);
    }
    return _logoUrl;
  }

  Future<void> _loadPlayInfo() async {
    // 加载保存的倍速
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSpeed = prefs.getDouble('play_speed') ?? 1.0;
      if (savedSpeed > 0) _speed = savedSpeed;
      _aspectMode = prefs.getString('aspect_mode') ?? 'fit';
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
          _logoUrl = _logoUrlFromItem(info.item);
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
        if (mounted) setState(() {});
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
          _selectedSubtitleIndex = -1;
          if (_isStrmFile && _engine != 'mpv' && _app.autoMpvForStrm) {
            debugPrint('Strm+subtitle: auto switch to MPV');
            _engine = 'mpv';
          } else if (_engine == 'mpv') {
            // MPV 在 initialize 完成后加载字幕轨
          } else if (!_isStrmFile) {
            _autoLoadExoSubtitle();
          }
        }
      }
    } catch (e) {
      debugPrint('fetchStreamInfo error: $e');
    }
  }

  /// ExoPlayer: 自动加载默认字幕
  Future<void> _autoLoadExoSubtitle() async {
    if (_mediaGuid == null) return;
    final data = await _subtitleService.loadDefault(
      mediaGuid: _mediaGuid!,
      subtitleGuid: _subtitleGuid,
      videoGuid: _videoGuid,
      streams: _subtitleStreams,
    );
    if (mounted && data != null && data.isNotEmpty) {
      setState(() {
        _softwareSubtitle = data;
        _selectedSubtitleIndex = 0;
      });
    }
  }

  /// ExoPlayer: 按索引加载/关闭字幕
  Future<void> _loadExoSubtitle({required int index}) async {
    if (_mediaGuid == null) return;
    if (index < 0) {
      if (mounted) {
        setState(() {
          _selectedSubtitleIndex = -1;
          _softwareSubtitle = null;
        });
      }
      return;
    }
    final streams = _subtitleStreams;
    if (streams == null || streams.isEmpty) return;

    final stream = index < streams.length ? streams[index] : null;
    SubtitleData? data = await _subtitleService.loadByStreamIndex(
      mediaGuid: _mediaGuid!,
      streamIndex: index,
      stream: stream,
      subtitleGuid: _subtitleGuid,
      videoGuid: _videoGuid,
    );
    if (data == null) {
      data = await _subtitleService.loadDefault(
        mediaGuid: _mediaGuid!,
        subtitleGuid: stream?.guid ?? _subtitleGuid,
        videoGuid: _videoGuid,
        streams: streams,
      );
    }

    if (!mounted) return;
    if (data != null && data.isNotEmpty) {
      setState(() {
        _softwareSubtitle = data;
        _selectedSubtitleIndex = index;
      });
      debugPrint('✅ Exo subtitle ready: ${data.entries.length} entries, index=$index');
    } else {
      setState(() {
        _selectedSubtitleIndex = -1;
        _softwareSubtitle = null;
      });
      FnToast.show(context, '字幕加载失败，可尝试加载外部 SRT/VTT 文件', type: FnToastType.warning, duration: const Duration(seconds: 3));
      debugPrint('❌ Exo subtitle load failed for index=$index');
    }
  }

  Future<void> _onExoSubtitleSelected(int idx) async {
    if (idx < 0) {
      setState(() {
        _selectedSubtitleIndex = -1;
        _softwareSubtitle = null;
      });
      return;
    }
    if (_isStrmFile) {
      await _switchToMpvForSubtitle(subtitleIndex: idx);
      return;
    }
    setState(() => _selectedSubtitleIndex = idx);
    await _loadExoSubtitle(index: idx);
  }

  /// strm / 内嵌字幕：切换 MPV 由本地 demux 字幕（API 无法提取）
  Future<void> _switchToMpvForSubtitle({int subtitleIndex = 0, bool silent = false}) async {
    final pos = _videoCtrl?.position ?? Duration.zero;
    final seekTs = pos.inSeconds > 0 ? pos.inSeconds : (widget.seekTs > 0 ? widget.seekTs : _serverSeekTs);

    setState(() {
      _engine = 'mpv';
      _softwareSubtitle = null;
      _selectedSubtitleIndex = subtitleIndex;
      _isInitialized = false;
      _serverSeekTs = seekTs;
    });
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _startPlayback();

    if (!silent && mounted) {
      FnToast.show(context, '已切换 MPV 内核，正在加载内嵌字幕…', type: FnToastType.success);
    }
  }

  void _applyMpvSubtitleTrack(int index) {
    if (_engine != 'mpv' || _videoCtrl == null) return;
    if (index < 0) {
      _videoCtrl!.setSubtitleTrack(-1);
      return;
    }
    _videoCtrl!.setSubtitleTrack(index);
    if (mounted) setState(() => _selectedSubtitleIndex = index);
    debugPrint('✅ MPV subtitle track index=$index');
  }

  Future<void> _autoLoadMpvSubtitle() async {
    if (_engine != 'mpv' || _subtitleStreams == null || _subtitleStreams!.isEmpty) return;
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted || _videoCtrl == null) return;
    _applyMpvSubtitleTrack(_selectedSubtitleIndex >= 0 ? _selectedSubtitleIndex : 0);
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

      final data = SubtitleData.parseAuto(content);
      if (data == null || data.entries.isEmpty) return;

      if (mounted) {
        setState(() => _softwareSubtitle = data);
        debugPrint('✅ Loaded ${data.entries.length} subtitle entries from ${file.name}');
        if (mounted) {
          FnToast.show(context, '已加载 ${data.entries.length} 条字幕', type: FnToastType.success);
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
      decoderMode: _app!.decoderMode,
    );
    _videoCtrl!.addListener(_videoListener);
    _videoCtrl!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isInitialized = true);
      _videoCtrl!.setSpeed(_speed);
      // 优先使用 widget.seekTs（详情页传入），其次用 _serverSeekTs（play/info 获取）
      final seekTs = widget.seekTs > 0 ? widget.seekTs : _serverSeekTs;

      _videoCtrl!.play();
      _isPlaying = true;
      if (_engine == 'mpv' && _subtitleStreams != null && _subtitleStreams!.isNotEmpty) {
        _autoLoadMpvSubtitle();
      }
      if (seekTs > 0) {
        final seekMs = seekTs * 1000;
        debugPrint('🎯 Will seek to ${seekTs}s (${seekMs}ms) — widget=${widget.seekTs}s, server=${_serverSeekTs}s');
        _performSeekWithRetry(seekMs, isMpv: _engine == 'mpv');
      } else {
        debugPrint('ℹ️ No seek needed: widget.seekTs=${widget.seekTs}s, _serverSeekTs=$_serverSeekTs');
      }
      // 立即上报一次进度（不等5秒定时器）
      Future.delayed(const Duration(seconds: 2), () => _saveProgress());
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
      final result = await _danmuService.loadAuto(
        matchName: matchName,
        episodeNumber: _episodeNumber,
      );
      if (result != null && mounted) {
        setState(() {
          _danmuSource = result.source;
          _danmuItems = result.comments;
        });
        debugPrint('Danmu: loaded ${result.comments.length} comments');
      }
    } catch (e) {
      debugPrint('loadDanmu error: $e');
    }
  }

  Future<void> _loadDanmuFromSource(Map<String, dynamic> source) async {
    try {
      final result = await _danmuService.loadFromSource(source);
      if (result != null && mounted) {
        setState(() {
          _danmuItems = result.comments;
          _danmuSource = result.source;
        });
        debugPrint('Danmu: loaded ${result.comments.length} from manual source');
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
        list.sort((a, b) {
          final an = a.episodeNumber > 0 ? a.episodeNumber : 9999;
          final bn = b.episodeNumber > 0 ? b.episodeNumber : 9999;
          return an.compareTo(bn);
        });
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
      _softwareSubtitle = null;
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
        if (info.item != null) {
          if (info.item!.tvTitle != null) _tvTitle = info.item!.tvTitle!;
          _itemTitle = info.item!.title ?? _itemTitle;
          _episodeNumber = info.item!.episodeNumber;
          _logoUrl = _logoUrlFromItem(info.item);
        }
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

  void _setAspectMode(String mode) {
    setState(() => _aspectMode = mode);
    SharedPreferences.getInstance().then((p) => p.setString('aspect_mode', mode));
  }

  Future<void> _switchEngine(String engine) async {
    if (engine == _engine) return;
    final pos = _videoCtrl?.position ?? Duration.zero;
    final seekTs = pos.inSeconds > 0 ? pos.inSeconds : _serverSeekTs;
    setState(() {
      _engine = engine;
      _app.playerEngine = engine;
      _isInitialized = false;
      _softwareSubtitle = null;
      _serverSeekTs = seekTs;
    });
    _videoCtrl?.dispose();
    _videoCtrl = null;
    await _fetchStreamInfo();
    _startPlayback();
    if (mounted) {
      FnToast.show(context, '已切换 ${engine == 'mpv' ? 'MPV' : 'Exo'} 内核', type: FnToastType.success);
    }
  }

  void _toggleOrientation() {
    setState(() => _preferPortrait = !_preferPortrait);
    SystemChrome.setPreferredOrientations(_preferPortrait
        ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    FnToast.show(context, _preferPortrait ? '已切换竖屏' : '已切换横屏');
  }

  Widget _buildVideoArea(_SubtitleStyle style) {
    if (!_isInitialized || _videoCtrl == null) {
      return const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen));
    }
    final video = _videoCtrl!.buildVideo(
      subtitleSize: style.size,
      subtitleOutline: style.outline,
      subtitleBackground: style.background,
      subtitleColor: Color(style.color),
      subtitleWeight: style.weight,
    );
    switch (_aspectMode) {
      case 'fill':
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoCtrl!.aspectRatio * 1000,
              height: 1000,
              child: video,
            ),
          ),
        );
      case '16:9':
        return Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRect(child: FittedBox(fit: BoxFit.contain, child: video)),
          ),
        );
      case '4:3':
        return Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRect(child: FittedBox(fit: BoxFit.contain, child: video)),
          ),
        );
      default:
        return Center(
          child: AspectRatio(
            aspectRatio: _videoCtrl!.aspectRatio,
            child: video,
          ),
        );
    }
  }

  String get _engineLabel {
    final buf = StringBuffer(_engine == 'mpv' ? 'MPV' : 'Exo');
    if (_isStrmFile && _cloudDirectUrl.isNotEmpty) buf.write(' · 直链');
    if (_streamVWidth > 0 && _streamVHeight > 0) buf.write(' · ${_streamVWidth}x$_streamVHeight');
    return buf.toString();
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
    _saveProgress(force: true);
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
    final seekStep = _app.seekStep;
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
            _seek(Duration(seconds: -seekStep));
          } else if (dx > w * 2 / 3) {
            _seek(Duration(seconds: seekStep));
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
            // Video + 字幕样式（仅监听字幕相关设置）
            Selector<AppState, _SubtitleStyle>(
              selector: (_, app) => _SubtitleStyle(
                size: app.subtitleSize,
                outline: app.subtitleOutline,
                background: app.subtitleBackground,
                color: app.subtitleColorValue,
                weight: app.subtitleWeight,
                bottomMargin: app.subtitleBottomMargin,
              ),
              builder: (context, style, _) => _buildVideoArea(style),
            ),

            // Buffering indicator
            if (_isBuffering)
              const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen, strokeWidth: 3)),

            // Danmu overlay（监听弹幕设置变化，调速实时生效）
            if (_danmuOn && _videoCtrl != null && _danmuItems.isNotEmpty)
              Selector<AppState, _DanmuStyle>(
                selector: (_, app) => _DanmuStyle(
                  opacity: app.danmuOpacity,
                  fontSize: app.danmuFontSize,
                  areaPercent: app.danmuArea,
                  showOutline: app.danmuOutline,
                  speed: app.danmuSpeed,
                  danmuDensity: app.danmuDensity / 100.0,
                  topMargin: app.danmuTopMargin,
                  showScroll: app.danmuScroll,
                  showTop: app.danmuTop,
                  showBottom: app.danmuBottom,
                  antiOverlap: app.danmuAntiOverlap,
                ),
                builder: (context, style, _) => DanmuOverlay(
                  comments: _danmuItems,
                  getCurrentTime: () => _videoCtrl!.position,
                  positionListenable: _videoCtrl!.positionNotifier,
                  opacity: style.opacity,
                  fontSize: style.fontSize,
                  areaPercent: style.areaPercent,
                  showOutline: style.showOutline,
                  speed: style.speed,
                  danmuDensity: style.danmuDensity,
                  topMargin: style.topMargin,
                  showScroll: style.showScroll,
                  showTop: style.showTop,
                  showBottom: style.showBottom,
                  antiOverlap: style.antiOverlap,
                ),
              ),

            // 软件字幕覆盖层（ExoPlayer 用）
            if (_engine != 'mpv' && _selectedSubtitleIndex >= 0 && _softwareSubtitle != null && _softwareSubtitle!.isNotEmpty)
              Selector<AppState, _SubtitleStyle>(
                selector: (_, app) => _SubtitleStyle(
                  size: app.subtitleSize,
                  outline: app.subtitleOutline,
                  background: app.subtitleBackground,
                  color: app.subtitleColorValue,
                  weight: app.subtitleWeight,
                  bottomMargin: app.subtitleBottomMargin,
                ),
                builder: (context, style, _) => SubtitleOverlay(
                  subtitleData: _softwareSubtitle,
                  getCurrentTime: () => _videoCtrl!.position,
                  positionListenable: _videoCtrl?.positionNotifier,
                  fontSize: style.size,
                  outline: style.outline,
                  showBackground: style.background,
                  color: Color(style.color),
                  fontWeight: FontWeight.values[
                    ((style.weight.clamp(100, 900) - 100) / 100).round().clamp(0, 8)
                  ],
                  bottomMargin: style.bottomMargin,
                ),
              ),

            // Controls
            if (_showControls)
              PlayerControls(
                title: _displayTitle,
                logoUrl: _logoUrl,
                headerTitle: _headerTitle,
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
                onDanmuToggle: (v) => setState(() {
                  _danmuOn = v;
                  _app.danmuOn = v;
                }),
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
                seekStep: seekStep,
                onSubtitleSelected: (idx) {
                  if (_engine == 'mpv') {
                    if (idx < 0) {
                      setState(() => _selectedSubtitleIndex = -1);
                      _videoCtrl?.setSubtitleTrack(-1);
                    } else {
                      _applyMpvSubtitleTrack(idx);
                    }
                  } else {
                    _onExoSubtitleSelected(idx);
                  }
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
                isStrmFile: _isStrmFile,
                onSwitchToMpv: (_isStrmFile && _engine != 'mpv')
                    ? () => _switchToMpvForSubtitle(subtitleIndex: 0)
                    : null,
                engineLabel: _engineLabel,
                onEngineSelect: _switchEngine,
                aspectMode: _aspectMode,
                onAspectMode: _setAspectMode,
                hasPrevEpisode: _currentEpIndex > 0,
                hasNextEpisode: _episodeList != null &&
                    _currentEpIndex >= 0 &&
                    _currentEpIndex < _episodeList!.length - 1,
                onPrevEpisode: _currentEpIndex > 0 ? () => _playEpisode(_currentEpIndex - 1) : null,
                onNextEpisode: (_episodeList != null &&
                        _currentEpIndex >= 0 &&
                        _currentEpIndex < _episodeList!.length - 1)
                    ? () => _playEpisode(_currentEpIndex + 1)
                    : null,
                onRotate: _toggleOrientation,
                danmuComments: _danmuItems,
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

class _SubtitleStyle {
  final double size;
  final double outline;
  final bool background;
  final int color;
  final double weight;
  final double bottomMargin;

  const _SubtitleStyle({
    required this.size,
    required this.outline,
    required this.background,
    required this.color,
    required this.weight,
    required this.bottomMargin,
  });

  @override
  bool operator ==(Object other) =>
      other is _SubtitleStyle &&
      other.size == size &&
      other.outline == outline &&
      other.background == background &&
      other.color == color &&
      other.weight == weight &&
      other.bottomMargin == bottomMargin;

  @override
  int get hashCode => Object.hash(size, outline, background, color, weight, bottomMargin);
}

class _DanmuStyle {
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;
  final double speed;
  final double danmuDensity;
  final double topMargin;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool antiOverlap;

  const _DanmuStyle({
    required this.opacity,
    required this.fontSize,
    required this.areaPercent,
    required this.showOutline,
    required this.speed,
    required this.danmuDensity,
    required this.topMargin,
    required this.showScroll,
    required this.showTop,
    required this.showBottom,
    required this.antiOverlap,
  });

  @override
  bool operator ==(Object other) =>
      other is _DanmuStyle &&
      other.opacity == opacity &&
      other.fontSize == fontSize &&
      other.areaPercent == areaPercent &&
      other.showOutline == showOutline &&
      other.speed == speed &&
      other.danmuDensity == danmuDensity &&
      other.topMargin == topMargin &&
      other.showScroll == showScroll &&
      other.showTop == showTop &&
      other.showBottom == showBottom &&
      other.antiOverlap == antiOverlap;

  @override
  int get hashCode => Object.hash(
    opacity, fontSize, areaPercent, showOutline, speed,
    danmuDensity, topMargin, showScroll, showTop, showBottom, antiOverlap,
  );
}
