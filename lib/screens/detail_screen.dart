import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/app_state.dart';
import '../models/play_list_item.dart';
import '../models/play_info.dart';
import '../models/watch_record.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final PlayListItem item;

  const DetailScreen({super.key, required this.item});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  PlayInfoResponse? _playInfo;
  Map<String, dynamic>? _itemDetail; // 来自 /v/api/v1/item/{guid}
  List<Map<String, dynamic>> _persons = []; // 演员/导演
  List<PlayListItem> _episodes = [];
  List<Map<String, dynamic>> _seasons = [];
  List<String> _genreLabels = [];
  List<PlayListItem> _similarItems = [];
  bool _loadingSimilar = false;
  int _selectedSeasonIndex = 0;
  bool _loadingInfo = true;
  bool _loadingEpisodes = false;
  String? _error;
  Color _dominantColor = const Color(0xFF1A1A2E);
  int _episodeViewMode = 0; // 0=详细列表 1=封面九宫格 2=数字按钮
  bool _episodeSortAscending = true;
  String? _parentGuid; // TV 或 Season GUID，用于刷新
  String? _tvGuid;
  bool _overviewExpanded = false;
  static Map<int, String>? _genreMapCache;
  static const double _appBarExpandedHeight = 260;

  final ScrollController _scrollController = ScrollController();
  double _appBarCollapse = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPlayInfo();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !mounted) return;
    final topPadding = MediaQuery.of(context).padding.top;
    final collapseDistance = _appBarExpandedHeight - kToolbarHeight - topPadding;
    if (collapseDistance <= 0) return;
    final t = (_scrollController.offset / collapseDistance).clamp(0.0, 1.0);
    if ((t - _appBarCollapse).abs() > 0.015) {
      setState(() => _appBarCollapse = t);
    }
  }

  double get _collapsedTitleOpacity {
    if (_appBarCollapse <= 0.72) return 0;
    return ((_appBarCollapse - 0.72) / 0.28).clamp(0.0, 1.0);
  }

  AppState get _app => context.read<AppState>();

  // ==================== 数据加载 ====================

  Future<void> _loadPlayInfo() async {
    try {
      final resp = await _app.api.getPlayInfo(widget.item.guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final info = PlayInfoResponse.fromJson(resp['data']);
        if (mounted) {
          setState(() {
            _playInfo = info;
            _loadingInfo = false;
          });
          _extractPalette();
          // 获取 item 详情（logos/backdrops）和演员信息
          _loadItemDetail(widget.item.guid);
          _loadPersons(widget.item.guid);
          final type = info.type ?? widget.item.type;
          if (type == 'TV' || type == 'Episode') {
            _tvGuid = type == 'TV' ? widget.item.guid : null;
            _parentGuid = type == 'Episode' ? info.parentGuid : widget.item.guid;
            _initTvEpisodes(type ?? 'TV', info);
          }
        }
      } else {
        if (mounted) setState(() {
          _loadingInfo = false;
        });
        if (widget.item.isFolder) {
          _loadEpisodes(widget.item.guid);
        }
      }
    } catch (e) {
      debugPrint('loadPlayInfo error: $e');
      if (mounted) setState(() {
        _error = '获取详情失败: $e';
        _loadingInfo = false;
      });
    }
  }

  Future<void> _initTvEpisodes(String type, PlayInfoResponse info) async {
    if (type == 'Episode') {
      final seasonGuid = info.parentGuid ?? widget.item.parentGuid;
      _tvGuid = await _resolveTvGuid(seasonGuid);
    }
    if (_tvGuid != null && _tvGuid!.isNotEmpty) {
      await _loadSeasons(_tvGuid!, currentSeasonGuid: type == 'Episode' ? info.parentGuid : null);
      if (_tvGuid != widget.item.guid) _loadItemDetail(_tvGuid!);
    } else if (_parentGuid != null && _parentGuid!.isNotEmpty) {
      await _loadEpisodes(_parentGuid!);
    }
  }

  Future<String?> _resolveTvGuid(String? seasonGuid) async {
    if (_isTvShow) return widget.item.guid;
    if (seasonGuid == null || seasonGuid.isEmpty) return null;
    try {
      final resp = await _app.api.getItemDetail(seasonGuid);
      final data = resp['data'];
      if (data is Map<String, dynamic>) {
        final pg = data['parent_guid']?.toString();
        if (pg != null && pg.isNotEmpty) return pg;
      }
    } catch (e) {
      debugPrint('resolveTvGuid error: $e');
    }
    return null;
  }

  Future<void> _loadSeasons(String tvGuid, {String? currentSeasonGuid}) async {
    if (mounted) setState(() => _loadingEpisodes = true);
    try {
      final resp = await _app.api.getSeasonList(tvGuid);
      List<Map<String, dynamic>> seasons = [];
      if (resp['code'] == 0 && resp['data'] != null) {
        final data = resp['data'];
        if (data is List) {
          seasons = data.whereType<Map<String, dynamic>>().toList();
        }
      }
      seasons.sort((a, b) => (a['season_number'] ?? 0).compareTo(b['season_number'] ?? 0));

      if (seasons.isNotEmpty) {
        var idx = 0;
        if (currentSeasonGuid != null) {
          final found = seasons.indexWhere((s) => s['guid']?.toString() == currentSeasonGuid);
          if (found >= 0) idx = found;
        }
        if (mounted) {
          setState(() {
            _seasons = seasons;
            _selectedSeasonIndex = idx;
            _parentGuid = seasons[idx]['guid']?.toString();
          });
        }
        if (_parentGuid != null) {
          await _loadEpisodes(_parentGuid!, keepLoading: true);
        } else if (mounted) {
          setState(() => _loadingEpisodes = false);
        }
      } else if (_parentGuid != null && _parentGuid!.isNotEmpty) {
        await _loadEpisodes(_parentGuid!, keepLoading: true);
      } else if (mounted) {
        setState(() => _loadingEpisodes = false);
      }
    } catch (e) {
      debugPrint('loadSeasons error: $e');
      if (_parentGuid != null && _parentGuid!.isNotEmpty) {
        await _loadEpisodes(_parentGuid!, keepLoading: true);
      } else if (mounted) {
        setState(() => _loadingEpisodes = false);
      }
    }
  }

  Future<void> _loadEpisodes(String seasonGuid, {bool keepLoading = false}) async {
    if (!keepLoading && mounted) setState(() => _loadingEpisodes = true);
    try {
      final resp = await _app.api.getEpisodeList(seasonGuid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final items = (resp['data'] as List).map((e) => PlayListItem.fromJson(e)).toList();
        if (mounted) setState(() {
          _episodes = items;
          _loadingEpisodes = false;
        });
      } else {
        if (mounted) setState(() => _loadingEpisodes = false);
      }
    } catch (e) {
      debugPrint('loadEpisodes error: $e');
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  void _selectSeason(int index) {
    if (index < 0 || index >= _seasons.length) return;
    final guid = _seasons[index]['guid']?.toString();
    if (guid == null || guid.isEmpty) return;
    setState(() {
      _selectedSeasonIndex = index;
      _parentGuid = guid;
    });
    _loadEpisodes(guid);
  }

  Future<void> _loadItemDetail(String guid) async {
    try {
      final resp = await _app.api.getItemDetail(guid);
      if (resp['code'] == 0 && resp['data'] != null && mounted) {
        final data = resp['data'] as Map<String, dynamic>;
        setState(() => _itemDetail = data);
        _loadGenreLabels(data['genres']);
        _loadSimilarItems(data);
      }
    } catch (e) {
      debugPrint('loadItemDetail error: $e');
    }
  }

  Future<void> _loadGenreLabels(dynamic genreIds) async {
    if (genreIds is! List || genreIds.isEmpty) return;
    try {
      _genreMapCache ??= await _fetchGenreMap();
      if (_genreMapCache == null) return;
      final labels = genreIds
          .map((id) => _genreMapCache![id is int ? id : int.tryParse(id.toString()) ?? -1])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      if (mounted && labels.isNotEmpty) setState(() => _genreLabels = labels);
    } catch (e) {
      debugPrint('loadGenreLabels error: $e');
    }
  }

  Future<Map<int, String>> _fetchGenreMap() async {
    final resp = await _app.api.getGenres();
    final map = <int, String>{};
    if (resp['code'] != 0 || resp['data'] == null) return map;
    final data = resp['data'];
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final id = item['id'] ?? item['genre_id'];
          final name = item['name'] ?? item['title'];
          if (id != null && name != null) map[id is int ? id : int.parse(id.toString())] = name.toString();
        }
      }
    } else if (data is Map) {
      data.forEach((k, v) {
        final id = int.tryParse(k.toString());
        if (id != null && v != null) map[id] = v.toString();
      });
    }
    return map;
  }

  Future<void> _loadSimilarItems(Map<String, dynamic> data) async {
    final ancestorGuid = data['ancestor_guid']?.toString();
    if (ancestorGuid == null || ancestorGuid.isEmpty) return;
    if (mounted) setState(() => _loadingSimilar = true);
    try {
      final resp = await _app.api.getItemList({
        'ancestor_guid': ancestorGuid,
        'tags': {'type': ['Movie', 'TV']},
        'exclude_grouped_video': 1,
        'sort_type': 'DESC',
        'sort_column': 'release_date',
        'page': 1,
        'page_size': 24,
      });
      if (resp['code'] == 0 && resp['data'] != null) {
        final selfGuids = {widget.item.guid, _tvGuid, _playInfo?.item?.guid}.whereType<String>().toSet();
        final list = ((resp['data']['list'] as List?) ?? [])
            .map((e) => PlayListItem.fromJson(e as Map<String, dynamic>))
            .where((e) => !selfGuids.contains(e.guid))
            .take(12)
            .toList();
        if (mounted) setState(() {
          _similarItems = list;
          _loadingSimilar = false;
        });
      } else if (mounted) {
        setState(() => _loadingSimilar = false);
      }
    } catch (e) {
      debugPrint('loadSimilarItems error: $e');
      if (mounted) setState(() => _loadingSimilar = false);
    }
  }

  void _openSimilar(PlayListItem item) {
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => DetailScreen(item: item),
    ));
  }

  double? _epProgress(PlayListItem ep) {
    if (ep.ts <= 0) return null;
    if (ep.duration > 0) return (ep.ts / ep.duration).clamp(0.0, 1.0);
    return 0.15;
  }

  Future<void> _loadPersons(String guid) async {
    try {
      final resp = await _app.api.getPersonList(guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final list = (resp['data']['list'] as List?) ?? [];
        if (mounted) setState(() => _persons = list.whereType<Map<String, dynamic>>().toList());
      }
    } catch (e) {
      debugPrint('loadPersons error: $e');
    }
  }

  // ==================== 调色板 ====================

  Future<void> _extractPalette() async {
    final url = _posterUrl;
    if (url.isEmpty) return;
    try {
      final provider = CachedNetworkImageProvider(url, headers: _app.api.imageHeaders);
      final palette = await PaletteGenerator.fromImageProvider(
        provider,
        maximumColorCount: 5,
      );
      if (mounted && palette.dominantColor != null) {
        setState(() {
          // 取主色调，稍微降低亮度避免太亮
          final c = palette.dominantColor!.color;
          _dominantColor = HSLColor.fromColor(c).withLightness(0.18).toColor();
        });
      }
    } catch (e) {
      debugPrint('extractPalette error: $e');
    }
  }

  // ==================== 播放 ====================

  void _playItem(PlayListItem item) async {
    try {
      final resp = await _app.api.getPlayInfo(item.guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final info = PlayInfoResponse.fromJson(resp['data']);
        _app.addWatchRecord(WatchRecord(
          guid: item.guid,
          title: item.title ?? '',
          tvTitle: item.tvTitle ?? widget.item.title,
          episodeNumber: item.episodeNumber,
          poster: _bestPoster,
          libraryName: item.ancestorName,
          parentGuid: info.parentGuid ?? item.parentGuid,
          ts: item.ts,
          duration: item.duration,
        ));
        if (mounted) {
          // 优先使用 play/info 返回的 ts（服务端记录的进度），其次用 episode list 的 ts
          final seekTs = info.ts > 0 ? info.ts : item.ts;
          debugPrint('Play item: seekTs=$seekTs (info.ts=${info.ts}, item.ts=${item.ts})');
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => PlayerScreen(
              itemGuid: item.guid,
              title: item.title ?? '',
              tvTitle: item.tvTitle ?? widget.item.title ?? '',
              episodeNumber: item.episodeNumber,
              poster: _bestPoster,
              category: widget.item.categoryLabel,
              seekTs: seekTs,
              duration: item.duration,
              parentGuid: info.parentGuid ?? item.parentGuid,
              logoUrl: _logoUrl,
            ),
          ));
          if (mounted) await _refreshAfterPlayback();
        }
      }
    } catch (e) {
      debugPrint('playItem error: $e');
      if (mounted) {
        FnToast.show(context, '播放失败: $e', type: FnToastType.error);
      }
    }
  }

  /// 从播放页返回后同步本地/服务端进度并刷新 UI
  Future<void> _refreshAfterPlayback() async {
    final tasks = <Future<void>>[
      _app.fetchServerPlayList(),
      _refreshPlayInfo(),
    ];
    if (_parentGuid != null && _parentGuid!.isNotEmpty) {
      tasks.add(_loadEpisodes(_parentGuid!, keepLoading: true));
    }
    await Future.wait(tasks);
  }

  Future<void> _refreshPlayInfo() async {
    try {
      final resp = await _app.api.getPlayInfo(widget.item.guid);
      if (resp['code'] == 0 && resp['data'] != null && mounted) {
        setState(() => _playInfo = PlayInfoResponse.fromJson(resp['data']));
      }
    } catch (e) {
      debugPrint('refreshPlayInfo error: $e');
    }
  }

  // ==================== 图片 URL ====================

  String get _bestPoster {
    return _playInfo?.item?.poster
        ?? _playInfo?.posterPath
        ?? widget.item.poster
        ?? '';
  }

  String get _posterUrl {
    final p = _bestPoster;
    if (p.isNotEmpty) {
      return _app.api.getImageUrl(p, width: 600);
    }
    return '';
  }

  String get _backdropUrl {
    final bd = _playInfo?.item?.backdrops
        ?? _itemDetail?['backdrops']?.toString();
    if (bd != null && bd.isNotEmpty) {
      return _app.api.getImageUrl(bd, width: 1200);
    }
    return '';
  }

  String get _logoUrl {
    // play/info 可能没有 logo，从 item 详情获取
    final logo = _playInfo?.item?.logos
        ?? _playInfo?.item?.logo
        ?? _itemDetail?['logos']?.toString()
        ?? _itemDetail?['logo']?.toString();
    if (logo != null && logo.isNotEmpty) {
      return _app.api.getImageUrl(logo, width: 500);
    }
    return '';
  }

  // ==================== 判断类型 ====================

  bool get _isTvShow {
    final type = _playInfo?.type ?? widget.item.type;
    return type == 'TV';
  }

  bool get _isEpisode {
    final type = _playInfo?.type ?? widget.item.type;
    return type == 'Episode';
  }

  bool get _showEpisodes => _isTvShow || _isEpisode || _episodes.isNotEmpty;

  /// 导航栏/顶部展示用剧名
  String get _displayTitle {
    final item = _playInfo?.item;
    if (_isEpisode) {
      return item?.tvTitle ?? widget.item.tvTitle ?? widget.item.title ?? '';
    }
    return item?.tvTitle ?? item?.title ?? widget.item.tvTitle ?? widget.item.title ?? '';
  }

  /// 副标题（单集名 / 季名）
  String? get _displaySubtitle {
    final item = _playInfo?.item;
    if (_isEpisode) {
      final epTitle = item?.title ?? widget.item.title;
      if (epTitle != null && epTitle.isNotEmpty) return epTitle;
    }
    if (item?.parentTitle != null && item!.parentTitle!.isNotEmpty) {
      return item.parentTitle;
    }
    return null;
  }

  MediaStreamInfo? get _mediaStream {
    final item = _playInfo?.item;
    if (item?.mediaStream != null) return item!.mediaStream;
    final raw = _itemDetail?['media_stream'];
    if (raw is Map<String, dynamic>) return MediaStreamInfo.fromJson(raw);
    return null;
  }

  PlayListItem? get _continueEpisode {
    if (_episodes.isEmpty) return null;
    for (final ep in _episodes) {
      if (ep.ts > 0 && ep.watched == 0) return ep;
    }
    for (final ep in _episodes) {
      if (ep.watched == 0) return ep;
    }
    return null;
  }

  double get _watchProgress {
    if (_episodes.isEmpty) return 0;
    final total = _episodes.length;
    final done = _episodes.where((e) => e.watched > 0).length;
    final partial = _episodes.where((e) => e.ts > 0 && e.watched == 0).length;
    return ((done + partial * 0.3) / total).clamp(0.0, 1.0);
  }

  int get _watchedCount => _episodes.where((e) => e.watched > 0).length;

  List<PlayListItem> get _sortedEpisodes {
    final items = List<PlayListItem>.from(_episodes);
    items.sort((a, b) {
      final an = a.episodeNumber > 0 ? a.episodeNumber : 9999;
      final bn = b.episodeNumber > 0 ? b.episodeNumber : 9999;
      return _episodeSortAscending ? an.compareTo(bn) : bn.compareTo(an);
    });
    return items;
  }

  String get _playButtonLabel {
    final cont = _continueEpisode;
    if (cont != null && cont.ts > 0) {
      final epNum = cont.episodeNumber > 0 ? cont.episodeNumber : _episodes.indexOf(cont) + 1;
      return '继续观看 · 第$epNum集';
    }
    if (_showEpisodes && _episodes.isNotEmpty) return '播放第1集';
    return '播放';
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dominantColor,
      body: _loadingInfo
          ? const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: FnTheme.textSecondary)),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() { _loadingInfo = true; _error = null; });
              _loadPlayInfo();
            },
            child: const Text('重试', style: TextStyle(color: FnTheme.danmuGreen)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final item = _playInfo?.item;
    final wide = MediaQuery.of(context).size.width >= 720;

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        _buildSliverAppBar(item),
        SliverToBoxAdapter(
          child: Container(
            color: _dominantColor,
            child: wide ? _buildWideBody(item) : _buildNarrowBody(item),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildNarrowBody(ItemInfo? item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPosterThumb(_posterUrl),
              const SizedBox(width: 14),
              Expanded(child: _buildHeroInfoCard(item, compact: true)),
            ],
          ),
        ),
        _buildHeroActions(),
        if (_showEpisodes && _episodes.isNotEmpty) _buildWatchProgress(),
        if (_genreLabels.isNotEmpty) _buildGenreSection(),
        if (_persons.isNotEmpty) _buildActorsSection(),
        _buildInfoSection(item),
        if (_showEpisodes) ...[
          if (_seasons.length > 1) _buildSeasonSelector(),
          _buildEpisodeHeader(),
        ],
        if (_showEpisodes) _buildEpisodeList(),
        _buildSimilarSection(),
      ],
    );
  }

  Widget _buildWideBody(ItemInfo? item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              children: [
                _buildPosterThumb(_posterUrl, width: 200, height: 286),
                const SizedBox(height: 16),
                _buildHeroActions(),
                if (_showEpisodes && _episodes.isNotEmpty) _buildWatchProgress(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroInfoCard(item, compact: true),
                if (_genreLabels.isNotEmpty) _buildGenreSection(),
                if (_persons.isNotEmpty) _buildActorsSection(),
                _buildInfoSection(item),
                if (_showEpisodes) ...[
                  if (_seasons.length > 1) _buildSeasonSelector(),
                  _buildEpisodeHeader(),
                  _buildEpisodeList(),
                ],
                _buildSimilarSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarSection() {
    if (_loadingSimilar) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen)),
      );
    }
    if (_similarItems.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: FnTheme.danmuGreen, size: 18),
              SizedBox(width: 8),
              Text('相似推荐', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: FnTheme.textPrimary)),
            ],
          ),
        ),
        SizedBox(
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _similarItems.length,
            itemBuilder: (_, i) {
              final item = _similarItems[i];
              final title = item.tvTitle?.isNotEmpty == true ? item.tvTitle! : (item.title ?? '');
              final poster = item.poster ?? '';
              final url = poster.isNotEmpty ? _app.api.getImageUrl(poster, width: 200) : '';
              return GestureDetector(
                onTap: () => _openSimilar(item),
                child: Container(
                  width: 108,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFF2A2A2A),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: url.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: url,
                                  httpHeaders: _app.api.imageHeaders,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(Icons.movie_rounded, color: Colors.grey),
                                )
                              : const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 32)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: FnTheme.textSecondary, height: 1.3)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  SliverAppBar _buildSliverAppBar(ItemInfo? item) {
    final bgUrl = _backdropUrl.isNotEmpty ? _backdropUrl : _posterUrl;
    return SliverAppBar(
      expandedHeight: _appBarExpandedHeight,
      pinned: true,
      backgroundColor: _dominantColor,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Opacity(
        opacity: _collapsedTitleOpacity,
        child: _buildCollapsedAppBarTitle(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (bgUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: bgUrl,
                httpHeaders: _app.api.imageHeaders,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorWidget: (_, __, ___) => Container(color: _dominantColor),
              )
            else
              Container(color: _dominantColor),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(80),
                    Colors.black.withAlpha(140),
                    _dominantColor,
                  ],
                  stops: const [0.0, 0.65, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Opacity(
                opacity: (1 - _appBarCollapse * 1.15).clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildLogoOrTitle(
                    title: _displayTitle,
                    maxHeight: 72,
                    maxWidth: 300,
                    titleSize: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedAppBarTitle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: _buildLogoOrTitle(
        title: _displayTitle,
        maxHeight: 30,
        maxWidth: 260,
        titleSize: 16,
        titleMaxLines: 1,
        alignment: Alignment.centerLeft,
      ),
    );
  }

  Widget _buildLogoOrTitle({
    required String title,
    double maxHeight = 72,
    double maxWidth = 300,
    double titleSize = 22,
    int titleMaxLines = 2,
    Alignment alignment = Alignment.bottomCenter,
  }) {
    if (_logoUrl.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
        child: CachedNetworkImage(
          imageUrl: _logoUrl,
          httpHeaders: _app.api.imageHeaders,
          fit: BoxFit.contain,
          alignment: alignment,
          errorWidget: (_, __, ___) => _buildTitleText(title, size: titleSize, maxLines: titleMaxLines),
        ),
      );
    }
    return _buildTitleText(title, size: titleSize, maxLines: titleMaxLines);
  }

  Widget _buildHeroInfoCard(ItemInfo? item, {bool compact = false}) {
    final title = _displayTitle;
    final subtitle = _displaySubtitle;
    final logoUrl = _logoUrl;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logoUrl.isEmpty || compact) _buildTitleText(title, size: compact ? 26 : 22),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: Colors.white.withAlpha(190)),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _buildMetaRow(item),
          ),
          if (_hasOverview(item) && !compact) ...[
            const SizedBox(height: 8),
            Text(
              item?.overview ?? widget.item.overview ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(170), height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWatchProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '观看进度',
                style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(200), fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '$_watchedCount / ${_episodes.length} 集',
                style: const TextStyle(fontSize: 12, color: FnTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _watchProgress,
              minHeight: 5,
              backgroundColor: Colors.white.withAlpha(25),
              valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: _genreLabels.map((g) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: FnTheme.danmuGreen.withAlpha(35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FnTheme.danmuGreen.withAlpha(60)),
          ),
          child: Text(g, style: const TextStyle(fontSize: 12, color: FnTheme.danmuGreen)),
        )).toList(),
      ),
    );
  }

  Widget _buildSeasonSelector() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        itemCount: _seasons.length,
        itemBuilder: (_, i) {
          final season = _seasons[i];
          final active = i == _selectedSeasonIndex;
          final num = season['season_number'] ?? (i + 1);
          final title = season['title']?.toString();
          final label = title != null && title.isNotEmpty ? title : '第$num季';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label, style: TextStyle(
                fontSize: 13,
                color: active ? Colors.white : FnTheme.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
              selected: active,
              onSelected: (_) => _selectSeason(i),
              selectedColor: FnTheme.danmuGreen,
              backgroundColor: Colors.white.withAlpha(15),
              side: BorderSide(color: active ? FnTheme.danmuGreen : Colors.white.withAlpha(30)),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        },
      ),
    );
  }
  Widget _buildPosterThumb(String posterUrl, {double width = 108, double height = 154}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(140),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: posterUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: posterUrl,
              httpHeaders: _app.api.imageHeaders,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: const Color(0xFF2A2A2A),
                child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 32)),
              ),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF2A2A2A),
                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 32)),
              ),
            )
          : Container(
              color: const Color(0xFF2A2A2A),
              child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 32)),
            ),
    );
  }

  /// 播放 / 收藏 操作区
  Widget _buildHeroActions() {
    final item = _playInfo?.item;
    final isFav = (item?.isFavorite ?? widget.item.isFavorite) > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_showEpisodes && _episodes.isNotEmpty) {
                    _playItem(_continueEpisode ?? _episodes.first);
                  } else {
                    _playItem(widget.item);
                  }
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                label: Text(
                  _playButtonLabel,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FnTheme.danmuGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                FnToast.show(context, isFav ? '已在收藏夹' : '收藏功能待接入 API');
              },
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? Colors.redAccent : Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleText(String title, {double size = 22, int maxLines = 2}) {
    return Text(
      title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: FnTheme.textPrimary,
        shadows: const [
          Shadow(blurRadius: 8, color: Colors.black87),
        ],
      ),
    );
  }

  bool _hasOverview(ItemInfo? item) {
    final overview = item?.overview ?? widget.item.overview;
    return overview != null && overview.isNotEmpty;
  }

  Widget _buildMetaRow(ItemInfo? item) {
    final parts = <String>[];
    final year = item?.airDate ?? item?.releaseDate ?? widget.item.airDate;
    if (year != null && year.isNotEmpty) {
      parts.add(year.length > 4 ? year.substring(0, 4) : year);
    }
    final vote = item?.voteAverage ?? widget.item.voteAverage;
    if (vote != null && vote.isNotEmpty && vote != '0' && vote != '0.0') {
      parts.add('⭐ $vote');
    }
    final epCount = item?.numberOfEpisodes ?? widget.item.numberOfEpisodes;
    final displayEp = _episodes.isNotEmpty
        ? _episodes.length
        : (epCount > 0 ? epCount : widget.item.localNumberOfEpisodes);
    if (displayEp > 0) {
      parts.add('$displayEp 集');
    }
    final seasonCount = item?.numberOfSeasons ?? widget.item.numberOfSeasons;
    final localSeason = widget.item.localNumberOfSeasons;
    final displaySeason = seasonCount > 0 ? seasonCount : localSeason;
    if (displaySeason > 0) {
      parts.add('$displaySeason 季');
    }
    final rt = (item?.runtime ?? 0) > 0 ? item!.runtime : widget.item.runtime;
    if (rt > 0 && displayEp == 0) {
      parts.add('$rt 分钟');
    }
    if (item?.status != null && item!.status!.isNotEmpty) {
      parts.add(item.status!);
    }
    // 媒体库来源
    final library = widget.item.ancestorName;
    if (library != null && library.isNotEmpty) {
      parts.add(library);
    }
    // 画质 / 音频
    final ms = _mediaStream;
    if (ms?.resolutions != null) {
      for (final r in ms!.resolutions!) {
        if (r.isNotEmpty) parts.add(r.toUpperCase());
      }
    }
    if (ms?.colorRangeType != null) {
      for (final c in ms!.colorRangeType!) {
        if (c.isNotEmpty) parts.add(c);
      }
    }
    if (ms?.audioType != null) {
      for (final a in ms!.audioType!) {
        if (a.isNotEmpty) parts.add(a);
      }
    }
    // 导演
    final directors = _persons.where((p) => p['job'] == 'Director').map((p) => p['name']?.toString() ?? '').where((n) => n.isNotEmpty);
    if (directors.isNotEmpty) {
      parts.add('导演 ${directors.take(2).join(' / ')}');
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: parts.map((p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withAlpha(25), width: 0.5),
        ),
        child: Text(p, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(200))),
      )).toList(),
    );
  }

  Widget _buildInfoSection(ItemInfo? item) {
    final overview = item?.overview ?? widget.item.overview;
    if (overview == null || overview.isEmpty) return const SizedBox.shrink();

    final needsExpand = overview.length > 100;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '简介',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: FnTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            overview,
            maxLines: _overviewExpanded ? null : 4,
            overflow: _overviewExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: FnTheme.textSecondary,
              height: 1.65,
            ),
          ),
          if (needsExpand)
            GestureDetector(
              onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _overviewExpanded ? '收起' : '展开全部',
                  style: const TextStyle(fontSize: 13, color: FnTheme.danmuGreen),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActorsSection() {
    final actors = _persons.where((p) => p['job'] == 'Actor').toList();
    if (actors.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '演职人员',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: FnTheme.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: actors.length,
            itemBuilder: (_, i) {
              final actor = actors[i];
              final name = actor['name']?.toString() ?? '';
              final role = actor['role']?.toString() ?? '';
              final profilePath = actor['profile_path']?.toString() ?? '';
              final imgUrl = profilePath.isNotEmpty ? _app.api.getImageUrl(profilePath, width: 200) : '';
              return Container(
                width: 80,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 60, height: 60,
                        child: imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              httpHeaders: _app.api.imageHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(Icons.person, color: Colors.grey, size: 30),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Icon(Icons.person, color: Colors.grey, size: 30),
                            ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    if (role.isNotEmpty)
                      Text(role, style: const TextStyle(color: Colors.white54, fontSize: 10),
                        maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeHeader() {
    if (_episodes.isEmpty && !_loadingEpisodes) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          const Icon(Icons.list_rounded, color: FnTheme.danmuGreen, size: 20),
          const SizedBox(width: 8),
          const Text('选集', style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: FnTheme.textPrimary,
          )),
          const SizedBox(width: 12),
          if (_episodes.isNotEmpty)
            Text('${_episodes.length} 集', style: const TextStyle(
              color: FnTheme.textMuted, fontSize: 13,
            )),
          const Spacer(),
          if (_episodes.isNotEmpty) ...[
            _sortOrderBtn(),
            const SizedBox(width: 4),
            _viewModeBtn(0, Icons.view_list_rounded, '详细'),
            _viewModeBtn(1, Icons.grid_view_rounded, '封面'),
            _viewModeBtn(2, Icons.apps_rounded, '按钮'),
          ],
        ],
      ),
    );
  }

  Widget _sortOrderBtn() {
    final ascending = _episodeSortAscending;
    return Tooltip(
      message: ascending ? '正序（点击切换倒序）' : '倒序（点击切换正序）',
      child: InkWell(
        onTap: () => setState(() => _episodeSortAscending = !ascending),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: FnTheme.danmuGreen.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ascending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 16,
                color: FnTheme.danmuGreen,
              ),
              const SizedBox(width: 4),
              Text(
                ascending ? '正序' : '倒序',
                style: const TextStyle(fontSize: 12, color: FnTheme.danmuGreen, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewModeBtn(int mode, IconData icon, String tip) {
    final active = _episodeViewMode == mode;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () => setState(() => _episodeViewMode = mode),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 4),
          decoration: active ? BoxDecoration(
            color: FnTheme.danmuGreen.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ) : null,
          child: Icon(icon, size: 18, color: active ? FnTheme.danmuGreen : FnTheme.textMuted),
        ),
      ),
    );
  }

  Widget _buildEpisodeList() {
    if (_loadingEpisodes) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen)),
      );
    }
    if (_episodes.isEmpty) {
      return const SizedBox.shrink();
    }
    switch (_episodeViewMode) {
      case 1: return _buildEpisodeGrid();
      case 2: return _buildEpisodeButtons();
      default: return _buildEpisodeDetailList();
    }
  }

  /// 详细列表视图（原有）
  Widget _buildEpisodeDetailList() {
    final episodes = _sortedEpisodes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(episodes.length, (i) => _buildEpisodeTile(episodes[i], i)),
    );
  }

  /// 封面九宫格视图
  Widget _buildEpisodeGrid() {
    final episodes = _sortedEpisodes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 6 : constraints.maxWidth > 600 ? 4 : 3;
        final itemW = (constraints.maxWidth - 20 * 2 - (crossCount - 1) * 8) / crossCount;
        final itemH = itemW * 9 / 16; // 16:9 比例
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(episodes.length, (i) {
              final ep = episodes[i];
              final epNum = ep.episodeNumber > 0 ? ep.episodeNumber : i + 1;
              final epPoster = ep.poster ?? _bestPoster;
              final posterUrl = epPoster.isNotEmpty ? _app.api.getImageUrl(epPoster, width: 300) : '';
              final hasProgress = ep.ts > 0 && ep.duration > 0;
              final progress = hasProgress ? ep.ts / ep.duration : 0.0;

              return GestureDetector(
                onTap: () => _playItem(ep),
                child: SizedBox(
                  width: itemW.toDouble(),
                  height: (itemH + 28).toDouble(),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: const Color(0xFF2A2A2A),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (posterUrl.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: posterUrl,
                                  httpHeaders: _app.api.imageHeaders,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text('$epNum', style: const TextStyle(color: FnTheme.textMuted, fontSize: 20, fontWeight: FontWeight.bold)),
                                  ),
                                )
                              else
                                Center(
                                  child: Text('$epNum', style: const TextStyle(color: FnTheme.textMuted, fontSize: 20, fontWeight: FontWeight.bold)),
                                ),
                              const Center(
                                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white60, size: 32),
                              ),
                              // 集数角标
                              Positioned(
                                top: 4, left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(180),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('$epNum', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              if (hasProgress)
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  child: LinearProgressIndicator(
                                    value: progress.clamp(0.0, 1.0),
                                    backgroundColor: Colors.black54,
                                    valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
                                    minHeight: 3,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '第$epNum集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  /// 数字按钮视图
  Widget _buildEpisodeButtons() {
    final episodes = _sortedEpisodes;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 12 : constraints.maxWidth > 600 ? 8 : 6;
        final btnSize = (constraints.maxWidth - 20 * 2 - (crossCount - 1) * 8) / crossCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(episodes.length, (i) {
              final ep = episodes[i];
              final epNum = ep.episodeNumber > 0 ? ep.episodeNumber : i + 1;
              final hasProgress = ep.ts > 0 && ep.duration > 0;
              final isWatched = ep.watched > 0;

              return GestureDetector(
                onTap: () => _playItem(ep),
                child: Container(
                  width: btnSize.clamp(40, 64).toDouble(),
                  height: btnSize.clamp(40, 64).toDouble(),
                  decoration: BoxDecoration(
                    color: hasProgress ? FnTheme.danmuGreen.withAlpha(40) : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasProgress ? FnTheme.danmuGreen.withAlpha(100) : const Color(0xFF3A3A3A),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$epNum',
                        style: TextStyle(
                          fontSize: btnSize > 50 ? 16 : 14,
                          fontWeight: FontWeight.bold,
                          color: hasProgress ? FnTheme.danmuGreen : FnTheme.textPrimary,
                        ),
                      ),
                      if (isWatched)
                        Positioned(
                          top: 3, right: 3,
                          child: Icon(Icons.check_circle, size: 12, color: FnTheme.danmuGreen),
                        ),
                      if (hasProgress)
                        Positioned(
                          bottom: 3, left: 6, right: 6,
                          child: LinearProgressIndicator(
                            value: (ep.ts / ep.duration).clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
                            minHeight: 2,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeTile(PlayListItem ep, int index) {
    final epPoster = ep.poster ?? _bestPoster;
    final posterUrl = epPoster.isNotEmpty ? _app.api.getImageUrl(epPoster, width: 200) : '';
    final progress = _epProgress(ep);
    final epNum = ep.episodeNumber > 0 ? ep.episodeNumber : index + 1;
    final isWatched = ep.watched > 0;
    final cont = _continueEpisode;
    final isContinue = cont?.guid == ep.guid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Material(
        color: isContinue
            ? FnTheme.danmuGreen.withAlpha(18)
            : Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playItem(ep),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isContinue
                      ? FnTheme.danmuGreen
                      : (progress != null ? FnTheme.danmuGreen.withAlpha(120) : Colors.transparent),
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF2A2A2A),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: posterUrl,
                              httpHeaders: _app.api.imageHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Center(
                                child: Text('$epNum', style: const TextStyle(
                                  color: FnTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            )
                          : Center(
                              child: Text('$epNum', style: const TextStyle(
                                color: FnTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white.withAlpha(isContinue ? 230 : 160), size: 30),
                    if (progress != null && progress > 0)
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.black54,
                          valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isContinue ? FnTheme.danmuGreen : Colors.white.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isContinue ? '继续' : 'E$epNum',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isContinue ? Colors.black : Colors.white70,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ep.title?.isNotEmpty == true ? ep.title! : '第$epNum集',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isContinue ? FontWeight.bold : FontWeight.w600,
                                color: isContinue ? FnTheme.danmuGreen : FnTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (isWatched)
                            const Icon(Icons.check_circle_rounded, color: FnTheme.danmuGreen, size: 16),
                        ],
                      ),
                      if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(ep.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: FnTheme.textMuted, height: 1.4)),
                      ],
                      if (ep.duration > 0) ...[
                        const SizedBox(height: 4),
                        Text(_formatDuration(ep.duration),
                          style: const TextStyle(fontSize: 11, color: FnTheme.textMuted)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
