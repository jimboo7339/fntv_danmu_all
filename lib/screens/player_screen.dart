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
import '../models/mpv_player_settings.dart';
import '../models/watch_record.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/theme.dart';
import '../utils/toast.dart';
import '../utils/format.dart';
import '../widgets/danmu_overlay.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/player_controls.dart';
import '../services/app_video_player.dart';
import '../services/player_factory.dart';
import '../services/player_adapter.dart';
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
  VideoWrapper? get _mpvCtrl =>
      _videoCtrl is VideoWrapper ? _videoCtrl as VideoWrapper : null;

  AppVideoPlayer? _videoCtrl;
  PlayerCoreType _activeCore = PlayerCoreType.exo;
  String _lastPlaybackUrl = '';
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isBuffering = false;
  bool _isInitialized = false;
  bool _mpvSubUiActive = false;

  // Stream info
  String? _mediaGuid;
  String? _episodeGuid; // play/info 返回的实际 episode GUID
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
  int? _explicitSeekTs; // 非 null 时优先使用（切集=0、切画质=当前位置）
  bool _useRouteSeekTs = true; // 仅首次进入播放页时使用路由 seekTs
  bool _fetchServerSeekOnLoad = false; // 选集面板切换时拉取该集服务端进度

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

  // 外部字幕文件（SRT/VTT 等）
  SubtitleData? _softwareSubtitle;
  final Set<String> _subtitleServerFailed = {};

  // Direct link
  String _cloudDirectUrl = '';
  bool _cloudDirectMode = true;
  int _qualityIndex = 1;
  int _qualityCount = 0;
  List<String> _qualityLabels = [];
  List<String> _qualityUrls = [];
  bool _qualityIsDirectLink = false;
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
  int _networkSpeedBps = 0;

  late DanmuService _danmuService;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>(); // Cache before dispose
    _danmuService = DanmuService(api: _appState!.api, appState: _appState!);
    _itemTitle = widget.title;
    _tvTitle = widget.tvTitle;
    _logoUrl = widget.logoUrl;
    _episodeNumber = widget.episodeNumber;
    _parentGuid = widget.parentGuid;
    _danmuOn = _appState!.danmuOn;
    // Initialize brightness and volume from system
    try {
      ScreenBrightness().current.then((v) {
        _currentBrightness = v;
      }).catchError((_) {});
    } catch (_) {}
    try {
      FlutterVolumeController.getVolume().then((v) {
        if (v != null) _currentVolume = v;
      }).catchError((_) {});
    } catch (_) {}
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadPlayInfo();
    _resetHideTimer();
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
          _seasonNumber =
              info.item!.seasonNumber > 0 ? info.item!.seasonNumber : 1;
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
          'User-Agent': [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          ]
        },
        'level': 1,
        'media_guid': _mediaGuid,
        'ip': ipHash,
        'nonce': (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
            .toString(),
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
          _isStrmFile = fp.toLowerCase().endsWith('.strm') ||
              fn.toLowerCase().endsWith('.strm');
        }
        if (sd.directLinkQualities != null &&
            sd.directLinkQualities!.isNotEmpty) {
          _applyQualityOptions(sd.directLinkQualities!, isDirectLink: true);
        } else if (sd.qualities != null && sd.qualities!.isNotEmpty) {
          _applyQualityOptions(sd.qualities!, isDirectLink: false);
        }
        // Parse audio/subtitle streams
        if (sd.audioStreams != null && sd.audioStreams!.isNotEmpty) {
          _audioStreams = sd.audioStreams;
          _selectedAudioIndex = 0;
        }
        if (sd.subtitleStreams != null && sd.subtitleStreams!.isNotEmpty) {
          _subtitleStreams = sd.subtitleStreams;
          _selectedSubtitleIndex =
              _defaultSubtitleListIndex(sd.subtitleStreams!);
        }
      }
    } catch (e) {
      debugPrint('fetchStreamInfo error: $e');
    }
  }

  int _defaultSubtitleListIndex(List<SubtitleStreamInfo> streams) {
    if (_subtitleGuid != null) {
      final i = streams.indexWhere((s) => s.guid == _subtitleGuid);
      if (i >= 0) return i;
    }
    return 0;
  }

  bool get _preferEmbeddedSubtitle => _cloudDirectUrl.isNotEmpty || _isStrmFile;

  MpvPlayerSettings _mpvSettingsForPlayback() {
    final base = _app.mpvSettings;
    if (_preferEmbeddedSubtitle) {
      return base.copyWith(videoSync: 'audio');
    }
    final hasSubs = _subtitleStreams != null && _subtitleStreams!.isNotEmpty;
    if (!hasSubs) return base;
    final hw = base.hwdec;
    if (hw == 'no') return base;
    if (hw == 'mediacodec' || hw == 'mediacodec-copy' || hw == 'auto-copy') {
      return base.copyWith(hwdec: 'auto-safe');
    }
    return base;
  }

  void _initVideo(String url, {bool forceMpv = false}) {
    _lastPlaybackUrl = url;
    _disposeVideoCtrl();
    final seekTs = _resolveSeekTs();
    final startAt = seekTs > 0 ? Duration(seconds: seekTs) : null;

    final core = PlayerFactory.resolveCore(
      userPreference: _app.playerCore,
      preferEmbedded: _preferEmbeddedSubtitle,
      subtitleStreams: _subtitleStreams,
      forceMpv: forceMpv,
    );
    _activeCore = core;

    _videoCtrl = PlayerFactory.create(
      core: core,
      url: url,
      headers: _app!.api.headers,
      mpvSettings: _mpvSettingsForPlayback(),
    );
    _mpvCtrl?.onPositionRegression = (lastStable) {
      debugPrint('🔄 Position regression at ${lastStable.inSeconds}s');
    };

    final deferSeek =
        core == PlayerCoreType.mpv && _preferEmbeddedSubtitle && seekTs > 0;

    _networkSpeedBps = 0;
    _videoCtrl!.networkSpeedBps.addListener(_onNetworkSpeedUpdate);
    _videoCtrl!.addListener(_videoListener);
    _videoCtrl!
        .initialize(
      startAt: deferSeek ? null : startAt,
      initialSpeed: _speed,
      deferSeek: deferSeek,
    )
        .then((_) async {
      if (!mounted || _videoCtrl == null) return;
      setState(() => _isInitialized = true);
      await _videoCtrl!.play();
      _isPlaying = true;

      if (deferSeek && startAt != null) {
        await _videoCtrl!.resumeAfterPlay(startAt);
        debugPrint('🎯 Cloud resume from ${seekTs}s (post-play seek)');
      } else if (startAt != null && startAt > Duration.zero) {
        debugPrint('🎯 Resume from ${seekTs}s');
      }

      if (_audioStreams != null &&
          _audioStreams!.length > 1 &&
          _selectedAudioIndex > 0) {
        await _videoCtrl!.applyInitialAudioIfNeeded(
          audioStreams: _audioStreams,
          preferredListIndex: _selectedAudioIndex,
        );
      }

      await _autoLoadDefaultSubtitle();

      if (!forceMpv &&
          _activeCore == PlayerCoreType.mpv &&
          _app.playerCore == PlayerCoreType.exo &&
          PlayerFactory.needsMpvForEmbeddedSubtitles(
            preferEmbedded: _preferEmbeddedSubtitle,
            subtitleStreams: _subtitleStreams,
          ) &&
          mounted) {
        FnToast.show(context, '内嵌字幕已自动切换 MPV', type: FnToastType.info);
      }

      Future.delayed(const Duration(seconds: 2), () => _saveProgress());
      _startProgressTimer();
      _resetHideTimer();
    }).catchError((e) {
      debugPrint('Player init error: $e');
      if (!forceMpv && _app.playerCore == PlayerCoreType.exo && mounted) {
        FnToast.show(context, 'Exo 播放失败，切换 MPV', type: FnToastType.info);
        _initVideo(url, forceMpv: true);
      }
    });
  }

  Future<void> _fallbackToMpv() async {
    if (_activeCore == PlayerCoreType.mpv || _lastPlaybackUrl.isEmpty) return;
    final pos = _videoCtrl?.position.inSeconds ?? 0;
    _explicitSeekTs = pos > 0 ? pos : 0;
    if (mounted) {
      FnToast.show(context, '内嵌字幕已切换 MPV 播放', type: FnToastType.info);
    }
    setState(() => _isInitialized = false);
    _initVideo(_lastPlaybackUrl, forceMpv: true);
  }

  Future<void> _selectSubtitleTrack(int index) async {
    if (_videoCtrl == null) return;
    if (index < 0) {
      await _videoCtrl!.setSubtitleTrack(-1);
      if (mounted) {
        setState(() {
          _selectedSubtitleIndex = -1;
          _softwareSubtitle = null;
        });
      }
      return;
    }

    final streams = _subtitleStreams;
    if (mounted) {
      setState(() {
        _selectedSubtitleIndex = index;
        _softwareSubtitle = null;
      });
    }

    final preferEmbedded = _preferEmbeddedSubtitle;
    final cacheKey = '${_mediaGuid ?? ''}:$index';
    final streamInfo =
        streams != null && index < streams.length ? streams[index] : null;

    if (!preferEmbedded &&
        _mediaGuid != null &&
        streamInfo != null &&
        !_subtitleServerFailed.contains(cacheKey)) {
      final svc = SubtitleService(_app.api);
      final data = await svc.loadByStreamIndex(
        mediaGuid: _mediaGuid!,
        streamIndex: index,
        stream: streamInfo,
        subtitleGuid: _subtitleGuid,
        videoGuid: _videoGuid,
      );
      if (data != null && mounted) {
        await _videoCtrl!.setSubtitleTrack(-1);
        setState(() {
          _softwareSubtitle = data;
          _selectedSubtitleIndex = index;
        });
        debugPrint(
            '✅ Software subtitle $index: ${data.entries.length} entries');
        return;
      }
      _subtitleServerFailed.add(cacheKey);
    }

    if (preferEmbedded) {
      debugPrint('📺 Cloud direct: use MPV embedded subtitle');
    }
    final ok = await _videoCtrl!.enableEmbeddedSubtitleDeferred(
      listIndex: index,
      info: streamInfo,
      delay: preferEmbedded
          ? const Duration(milliseconds: 1000)
          : (_isPlaying
              ? const Duration(milliseconds: 400)
              : const Duration(milliseconds: 800)),
    );
    if (ok && mounted) {
      setState(() {
        _softwareSubtitle = null;
        _selectedSubtitleIndex = index;
      });
      debugPrint('✅ MPV embedded subtitle $index');
    } else if (mounted) {
      debugPrint('⚠️ Subtitle track $index failed');
      if (_activeCore == PlayerCoreType.exo && preferEmbedded) {
        await _fallbackToMpv();
      }
    }
  }

  void _applyQualityOptions(List<DirectLinkQuality> options,
      {required bool isDirectLink}) {
    _qualityCount = options.length;
    _qualityIsDirectLink = isDirectLink;
    _qualityLabels = options.map(_qualityOptionLabel).toList();
    _qualityUrls =
        options.map((q) => (q.url ?? '').replaceAll(r'\u0026', '&')).toList();
    if (_qualityIndex >= _qualityCount) _qualityIndex = 0;
    _cloudDirectUrl = isDirectLink ? _qualityUrls[_qualityIndex] : '';
  }

  String _qualityOptionLabel(DirectLinkQuality q) {
    final res = q.resolution ?? '画质';
    if (q.bitrate > 0) return '$res · ${formatBitrate(q.bitrate)}';
    return res;
  }

  String _resolvePlaybackUrl() {
    if (_cloudDirectUrl.isNotEmpty) return _cloudDirectUrl;
    if (_qualityCount > 0 && _mediaGuid != null) {
      final direct = _qualityUrls.length > _qualityIndex
          ? _qualityUrls[_qualityIndex]
          : '';
      if (direct.isNotEmpty) return direct;
      if (_qualityIsDirectLink) {
        return _app.api.getMediaUrlWithQuality(_mediaGuid!, _qualityIndex);
      }
      return _app.api
          .getMediaUrlWithTranscodeQuality(_mediaGuid!, _qualityIndex);
    }
    return _app.api.getMediaUrl(_mediaGuid!);
  }

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
        setState(() {
          _softwareSubtitle = data;
          _selectedSubtitleIndex = -1;
        });
        debugPrint(
            '✅ Loaded ${data.entries.length} subtitle entries from ${file.name}');
        if (mounted) {
          FnToast.show(context, '已加载 ${data.entries.length} 条字幕',
              type: FnToastType.success);
        }
      }
    } catch (e) {
      debugPrint('Load subtitle error: $e');
    }
  }

  void _startPlayback() {
    if (_mediaGuid == null) return;
    final url = _resolvePlaybackUrl();
    debugPrint('Playing (${_app.playerCore.label}): $url');
    _initVideo(url);
  }

  void _disposeVideoCtrl() {
    _videoCtrl?.removeListener(_videoListener);
    _videoCtrl?.networkSpeedBps.removeListener(_onNetworkSpeedUpdate);
    _videoCtrl?.dispose();
    _videoCtrl = null;
  }

  int _resolveSeekTs() {
    if (_explicitSeekTs != null) {
      final ts = _explicitSeekTs!;
      _explicitSeekTs = null;
      return ts;
    }
    if (_useRouteSeekTs && widget.seekTs > 0) {
      _useRouteSeekTs = false;
      return widget.seekTs;
    }
    _useRouteSeekTs = false;
    return _serverSeekTs;
  }

  Future<void> _autoLoadDefaultSubtitle() async {
    final streams = _subtitleStreams;
    if (streams == null || streams.isEmpty) return;
    final idx = _selectedSubtitleIndex >= 0
        ? _selectedSubtitleIndex
        : _defaultSubtitleListIndex(streams);
    if (mounted && _selectedSubtitleIndex < 0) {
      setState(() => _selectedSubtitleIndex = idx);
    }
    await _selectSubtitleTrack(idx);
  }

  void _onNetworkSpeedUpdate() {
    if (_videoCtrl == null || !mounted) return;
    final bps = _videoCtrl!.networkSpeedBps.value;
    if (bps != _networkSpeedBps) {
      setState(() => _networkSpeedBps = bps);
    }
  }

  void _videoListener() {
    if (_videoCtrl == null || !mounted) return;
    final isBuffering = _videoCtrl!.isBuffering;
    final isPlaying = _videoCtrl!.isPlaying;
    final subActive = _videoCtrl!.mpvSubtitleActive;
    if (isBuffering != _isBuffering ||
        isPlaying != _isPlaying ||
        subActive != _mpvSubUiActive) {
      setState(() {
        _isBuffering = isBuffering;
        _isPlaying = isPlaying;
        _mpvSubUiActive = subActive;
      });
    }
    // Check if ended
    if (_videoCtrl!.position >= _videoCtrl!.duration &&
        _videoCtrl!.duration.inSeconds > 0) {
      _onPlaybackComplete();
    }
  }

  void _onPlaybackComplete() {
    if (_episodeList != null &&
        _currentEpIndex >= 0 &&
        _currentEpIndex < _episodeList!.length - 1) {
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
    _writeLocalProgress();
    _flushProgressToServer();
  }

  void _writeLocalProgress() {
    if (_videoCtrl == null) return;
    final pos = _videoCtrl!.position.inSeconds;
    final dur = _videoCtrl!.duration.inSeconds;
    if (dur <= 0) return;
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

  Future<void> _flushProgressToServer() async {
    if (_videoCtrl == null) return;
    final pos = _videoCtrl!.position.inSeconds;
    final dur = _videoCtrl!.duration.inSeconds;
    if (dur <= 0) return;
    _writeLocalProgress();
    final episodeGuid = _episodeGuid ?? widget.itemGuid;
    try {
      await _app.api.recordPlayStatus({
        'item_guid': episodeGuid,
        'media_guid': _mediaGuid ?? '',
        'video_guid': _videoGuid ?? '',
        'audio_guid': _audioGuid ?? '',
        'subtitle_guid': _subtitleGuid ?? '',
        'resolution': '原画',
        'bitrate': 0,
        'ts': pos,
        'duration': dur,
      });
    } catch (e) {
      debugPrint(
          '❌ recordPlayStatus error: $e (item=$episodeGuid, media=${_mediaGuid ?? ""}, ts=$pos, dur=$dur)');
    }
  }

  Future<void> _exitPlayer() async {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await _flushProgressToServer();
    if (mounted) Navigator.pop(context);
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
        debugPrint(
            'Danmu: loaded ${result.comments.length} from manual source');
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
        final list = (resp['data'] as List)
            .map((e) => PlayListItem.fromJson(e))
            .toList();
        list.sort((a, b) {
          final an = a.episodeNumber > 0 ? a.episodeNumber : 9999;
          final bn = b.episodeNumber > 0 ? b.episodeNumber : 9999;
          return an.compareTo(bn);
        });
        setState(() {
          _episodeList = list;
          _currentEpIndex = list.indexWhere((e) => e.guid == widget.itemGuid);
          if (_currentEpIndex < 0) {
            _currentEpIndex =
                list.indexWhere((e) => e.episodeNumber == _episodeNumber);
          }
        });
      }
    } catch (e) {
      debugPrint('loadEpisodes error: $e');
    }
  }

  void _playEpisode(int index, {bool resumeFromServer = false}) {
    if (_episodeList == null || index < 0 || index >= _episodeList!.length)
      return;
    final ep = _episodeList![index];
    _useRouteSeekTs = false;
    if (resumeFromServer) {
      _explicitSeekTs = null;
      _fetchServerSeekOnLoad = true;
    } else {
      _explicitSeekTs = 0;
      _serverSeekTs = 0;
      _fetchServerSeekOnLoad = false;
    }
    setState(() {
      _currentEpIndex = index;
      _itemTitle = ep.title ?? '';
      _episodeNumber = ep.episodeNumber;
      _mediaGuid = null;
      _cloudDirectUrl = '';
      _isInitialized = false;
      _danmuItems.clear();
      _softwareSubtitle = null;
      _subtitleServerFailed.clear();
      _audioStreams = null;
      _subtitleStreams = null;
      _selectedAudioIndex = 0;
      _selectedSubtitleIndex = -1;
    });
    _disposeVideoCtrl();
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
        if (_fetchServerSeekOnLoad) {
          _serverSeekTs = info.ts;
          _fetchServerSeekOnLoad = false;
        }
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
    SharedPreferences.getInstance()
        .then((p) => p.setString('aspect_mode', mode));
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
      return const ColoredBox(color: Colors.black);
    }
    final video = _videoCtrl!.buildVideo(
      subtitleSize: style.size,
      subtitleOutline: style.outline,
      subtitleBackground: style.background,
      subtitleColor: Color(style.color),
      subtitleWeight: style.weight,
      subtitleVisible:
          _softwareSubtitle == null && _videoCtrl!.mpvSubtitleActive,
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
            child:
                ClipRect(child: FittedBox(fit: BoxFit.contain, child: video)),
          ),
        );
      case '4:3':
        return Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child:
                ClipRect(child: FittedBox(fit: BoxFit.contain, child: video)),
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

  String get _playbackInfoLabel {
    final buf = StringBuffer(_activeCore.label);
    if (_isStrmFile && _cloudDirectUrl.isNotEmpty) buf.write(' · 直链');
    if (_streamVWidth > 0 && _streamVHeight > 0)
      buf.write(' · ${_streamVWidth}x$_streamVHeight');
    return buf.toString();
  }

  Future<void> _setSpeed(double speed) async {
    _speed = speed;
    await _videoCtrl?.setSpeed(_speed);
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('play_speed', _speed);
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

  void _onPlayerTap() {
    if (_isLocked) {
      _resetHideTimer();
      return;
    }
    if (_showControls) {
      setState(() => _showControls = false);
    } else {
      _resetHideTimer();
    }
  }

  Widget _buildPlayerGestureLayer(BuildContext context, int seekStep) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onPlayerTap,
        onDoubleTapDown: (details) {
          if (_isLocked) return;
          final w = MediaQuery.of(context).size.width;
          final dx = details.globalPosition.dx;
          final leftAction = _app.doubleTapLeft;
          final rightAction = _app.doubleTapRight;
          if (dx < w / 3) {
            if (leftAction == 'pause') {
              _togglePlay();
            } else {
              _seek(Duration(seconds: -seekStep));
            }
          } else if (dx > w * 2 / 3) {
            if (rightAction == 'pause') {
              _togglePlay();
            } else {
              _seek(Duration(seconds: seekStep));
            }
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
          final delta = -details.delta.dy / 200;
          if (isLeftSide) {
            _currentBrightness = (_currentBrightness + delta).clamp(0.0, 1.0);
            _showGestureOverlayWith('☀',
                '${(_currentBrightness * 100).toInt()}%', _currentBrightness);
            try {
              ScreenBrightness().setScreenBrightness(_currentBrightness);
            } catch (_) {}
          } else {
            _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
            _showGestureOverlayWith(
                '🔊', '${(_currentVolume * 100).toInt()}%', _currentVolume);
            try {
              FlutterVolumeController.setVolume(_currentVolume);
            } catch (_) {}
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
          _seekAccumulator += details.delta.dx * 200;
          final dur = _videoCtrl?.duration ?? Duration.zero;
          final pos = _seekStartPosition +
              Duration(milliseconds: _seekAccumulator.toInt());
          final clampedMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds);
          final progress =
              dur.inMilliseconds > 0 ? clampedMs / dur.inMilliseconds : 0.0;
          final current = Duration(milliseconds: clampedMs);
          _showGestureOverlayWith(
              details.delta.dx > 0 ? '⏩' : '⏪',
              '${_formatDuration(current)} / ${_formatDuration(dur)}',
              progress);
        },
        onHorizontalDragEnd: (details) {
          if (_isLocked) return;
          final dur = _videoCtrl?.duration ?? Duration.zero;
          final pos = _seekStartPosition +
              Duration(milliseconds: _seekAccumulator.toInt());
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
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gestureOverlayTimer?.cancel();
    _progressTimer?.cancel();
    _writeLocalProgress();
    _flushProgressToServer();
    _disposeVideoCtrl();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _exitPlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
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

            // 全屏手势层（覆盖原生播放器，加载/缓冲时也能唤出控制条）
            _buildPlayerGestureLayer(context, seekStep),

            // Buffering indicator
            if (_isBuffering || !_isInitialized)
              const IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(
                      color: FnTheme.danmuGreen, strokeWidth: 3),
                ),
              ),

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
                  isPlaying: _isPlaying,
                  playbackSpeed: _speed,
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

            // 外部字幕覆盖层
            if (_softwareSubtitle != null && _softwareSubtitle!.isNotEmpty)
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
                      ((style.weight.clamp(100, 900) - 100) / 100)
                          .round()
                          .clamp(0, 8)],
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
                onBack: _exitPlayer,
                onEpisode: (i) => _playEpisode(i, resumeFromServer: true),
                onQuality: (idx) {
                  final pos = _videoCtrl?.position.inSeconds ?? 0;
                  setState(() {
                    _qualityIndex = idx;
                    if (_qualityIsDirectLink && idx < _qualityUrls.length) {
                      _cloudDirectUrl = _qualityUrls[idx];
                    } else {
                      _cloudDirectUrl = '';
                    }
                    if (pos > 0) _explicitSeekTs = pos;
                  });
                  _disposeVideoCtrl();
                  setState(() => _isInitialized = false);
                  _startPlayback();
                },
                onAudioSelected: (idx) async {
                  setState(() => _selectedAudioIndex = idx);
                  final streams = _audioStreams;
                  await _videoCtrl?.setAudioTrackByInfo(
                    listIndex: idx,
                    info: streams != null && idx < streams.length
                        ? streams[idx]
                        : null,
                  );
                },
                seekStep: seekStep,
                onSubtitleSelected: (idx) => _selectSubtitleTrack(idx),
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
                playbackInfo: _playbackInfoLabel,
                aspectMode: _aspectMode,
                onAspectMode: _setAspectMode,
                hasPrevEpisode: _currentEpIndex > 0,
                hasNextEpisode: _episodeList != null &&
                    _currentEpIndex >= 0 &&
                    _currentEpIndex < _episodeList!.length - 1,
                onPrevEpisode: _currentEpIndex > 0
                    ? () => _playEpisode(_currentEpIndex - 1)
                    : null,
                onNextEpisode: (_episodeList != null &&
                        _currentEpIndex >= 0 &&
                        _currentEpIndex < _episodeList!.length - 1)
                    ? () => _playEpisode(_currentEpIndex + 1)
                    : null,
                onRotate: _toggleOrientation,
                danmuComments: _danmuItems,
                showNetworkSpeed: _app.showNetworkSpeed,
                networkSpeedBps: _networkSpeedBps,
              ),

            // Lock button — 屏幕右侧中间，始终可点，用于上锁/解锁
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _isLocked = !_isLocked;
                    if (_isLocked) {
                      _showControls = false;
                    } else {
                      _resetHideTimer();
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      color: _isLocked ? Colors.orange : Colors.white70,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_gestureOverlayIcon,
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(_gestureOverlayText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _gestureOverlayProgress,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                FnTheme.danmuGreen),
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
  int get hashCode =>
      Object.hash(size, outline, background, color, weight, bottomMargin);
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
        opacity,
        fontSize,
        areaPercent,
        showOutline,
        speed,
        danmuDensity,
        topMargin,
        showScroll,
        showTop,
        showBottom,
        antiOverlap,
      );
}
