import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/app_state.dart';
import '../models/play_info.dart';
import '../models/stream_response.dart';
import '../models/play_list_item.dart';
import '../models/danmu_comment.dart';
import '../models/watch_record.dart';
import '../utils/format.dart';
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
  final _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  int _speedIdx = 2;

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
      final body = <String, dynamic>{
        'header': {
          'User-Agent': ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36']
        },
        'level': 1,
        'media_guid': _mediaGuid,
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
      String query = matchName;
      if (_episodeNumber > 0) {
        query = '$matchName S${_seasonNumber.toString().padLeft(2, '0')}E${_episodeNumber.toString().padLeft(2, '0')}';
      }
      debugPrint('Loading danmu for: $query from $danmuUrl');
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

  void _cycleSpeed() {
    _speedIdx = (_speedIdx + 1) % _speeds.length;
    _speed = _speeds[_speedIdx];
    _videoCtrl?.setSpeed(_speed);
    setState(() {});
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
                onPlayPause: _togglePlay,
                onSeek: _seek,
                onSpeed: _cycleSpeed,
                onLock: () => setState(() {
                  _isLocked = !_isLocked;
                  if (_isLocked) _showControls = false;
                }),
                onDanmu: () => setState(() => _danmuOn = !_danmuOn),
                onBack: () => Navigator.pop(context),
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

            // Engine indicator
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
}
