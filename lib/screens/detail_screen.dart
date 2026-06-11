import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../providers/app_state.dart';
import '../models/play_list_item.dart';
import '../models/play_info.dart';
import '../models/watch_record.dart';
import '../utils/theme.dart';
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
  bool _loadingInfo = true;
  bool _loadingEpisodes = false;
  String? _error;
  Color _dominantColor = const Color(0xFF1A1A2E);
  int _episodeViewMode = 0; // 0=详细列表 1=封面九宫格 2=数字按钮

  @override
  void initState() {
    super.initState();
    _loadPlayInfo();
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
          // 判断是否需要加载剧集列表
          final type = info.type ?? widget.item.type;
          if (type == 'TV' || type == 'Episode') {
            final parentGuid = type == 'Episode' ? info.parentGuid : widget.item.guid;
            if (parentGuid != null && parentGuid.isNotEmpty) {
              _loadEpisodes(parentGuid);
            }
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

  Future<void> _loadEpisodes(String parentGuid) async {
    if (mounted) setState(() => _loadingEpisodes = true);
    try {
      final resp = await _app.api.getEpisodeList(parentGuid);
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

  Future<void> _loadItemDetail(String guid) async {
    try {
      final resp = await _app.api.getItemDetail(guid);
      if (resp['code'] == 0 && resp['data'] != null && mounted) {
        setState(() => _itemDetail = resp['data'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('loadItemDetail error: $e');
    }
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
          Navigator.push(context, MaterialPageRoute(
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
            ),
          ));
        }
      }
    } catch (e) {
      debugPrint('playItem error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
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

    return SingleChildScrollView(
      child: Column(
        children: [
          // 顶部海报模糊区域
          _buildHeroSection(item),
          // 信息区域（用取色填充背景）
          Container(
            color: _dominantColor,
            child: Column(
              children: [
                _buildInfoSection(item),
                if (_persons.isNotEmpty) _buildActorsSection(),
                if (_showEpisodes) ...[
                  _buildPlayButton(),
                  _buildEpisodeHeader(),
                  _buildEpisodeList(),
                ] else
                  _buildPlayButton(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部海报模糊区域：海报模糊作为背景 + logo + 标题
  Widget _buildHeroSection(ItemInfo? item) {
    final backdropUrl = _backdropUrl;
    final posterUrl = _posterUrl;
    final title = item?.tvTitle ?? item?.title ?? widget.item.title ?? '';
    final subtitle = item?.title != null && item!.title != item.tvTitle ? item.title : null;
    final logoUrl = _logoUrl;
    final bgUrl = backdropUrl.isNotEmpty ? backdropUrl : posterUrl;

    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 模糊海报背景
          if (bgUrl.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: CachedNetworkImage(
                imageUrl: bgUrl,
                httpHeaders: _app.api.imageHeaders,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: _dominantColor),
              ),
            )
          else
            Container(color: _dominantColor),

          // 深色遮罩（让内容可读）
          Container(
            color: Colors.black.withOpacity(0.45),
          ),

          // 底部渐变（过渡到取色背景）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, _dominantColor],
                stops: const [0.5, 1.0],
              ),
            ),
          ),

          // 返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // 海报卡片（小图）
          Positioned(
            left: 20,
            bottom: 16,
            child: Container(
              width: 120,
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 20,
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
                        child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 36)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 36)),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF2A2A2A),
                      child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 36)),
                    ),
            ),
          ),

          // Logo/标题 + 信息区域
          Positioned(
            left: 155,
            bottom: 16,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo 图片或标题
                if (logoUrl.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 70, maxWidth: 280),
                    child: CachedNetworkImage(
                      imageUrl: logoUrl,
                      httpHeaders: _app.api.imageHeaders,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      errorWidget: (_, __, ___) => _buildTitleText(title),
                    ),
                  )
                else
                  _buildTitleText(title),
                // 信息行：年份 · 评分 · 集数/时长
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildMetaRow(item),
                ),
                // 简介预览（2行）
                if (_hasOverview(item)) ...[
                  const SizedBox(height: 6),
                  Text(
                    item!.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withAlpha(180),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleText(String title) {
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: FnTheme.textPrimary,
        shadows: [
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
    // 年份
    final year = item?.airDate ?? widget.item.airDate;
    if (year != null && year.isNotEmpty) {
      parts.add(year.length > 4 ? year.substring(0, 4) : year);
    }
    // 评分
    final vote = item?.voteAverage ?? widget.item.voteAverage;
    if (vote != null && vote.isNotEmpty && vote != '0' && vote != '0.0') {
      parts.add('⭐ $vote');
    }
    // 集数
    final epCount = item?.numberOfEpisodes ?? widget.item.numberOfEpisodes;
    if (epCount > 0) {
      parts.add('$epCount 集');
    }
    // 季数
    final seasonCount = item?.numberOfSeasons ?? widget.item.numberOfSeasons;
    if (seasonCount > 0) {
      parts.add('$seasonCount 季');
    }
    // 时长
    final rt = (item?.runtime ?? 0) > 0 ? item!.runtime : widget.item.runtime;
    if (rt > 0 && epCount == 0) {
      parts.add('$rt 分钟');
    }
    // 状态（仅 ItemInfo 有）
    if (item?.status != null && item!.status!.isNotEmpty) {
      parts.add(item.status!);
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
    final voteRaw = item?.voteAverage ?? widget.item.voteAverage;
    final runtime = (item?.runtime ?? 0) > 0 ? item!.runtime : widget.item.runtime;
    final airDate = item?.airDate ?? widget.item.airDate;
    final overview = item?.overview ?? widget.item.overview;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _tag(widget.item.categoryLabel, FnTheme.danmuGreen),
              if (voteRaw != null && voteRaw.isNotEmpty && voteRaw != '0' && voteRaw != '0.0')
                _tag('⭐ $voteRaw', Colors.amber),
              if (runtime > 0)
                _tag('$runtime 分钟', FnTheme.textSecondary),
              if (airDate != null && airDate.isNotEmpty)
                _tag(airDate.length > 4 ? airDate.substring(0, 4) : airDate, FnTheme.textSecondary),
              if (widget.item.numberOfSeasons > 0)
                _tag('${widget.item.numberOfSeasons} 季', FnTheme.textSecondary),
              if (widget.item.numberOfEpisodes > 0)
                _tag('${widget.item.numberOfEpisodes} 集', FnTheme.textSecondary),
            ],
          ),
          // Overview
          if (overview != null && overview.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              overview,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: FnTheme.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _buildActorsSection() {
    // 只显示演员（Actor），导演在标签区已体现
    final actors = _persons.where((p) => p['job'] == 'Actor').toList();
    if (actors.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 140,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
    );
  }

  Widget _buildPlayButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () {
            if (_isTvShow && _episodes.isNotEmpty) {
              final firstUnwatched = _episodes.firstWhere(
                (e) => e.watched == 0,
                orElse: () => _episodes.first,
              );
              _playItem(firstUnwatched);
            } else {
              _playItem(widget.item);
            }
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: const Text(
            '播放',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: FnTheme.danmuGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
          ),
        ),
      ),
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
          // 视图切换按钮
          if (_episodes.isNotEmpty) ...[
            _viewModeBtn(0, Icons.view_list_rounded, '详细'),
            _viewModeBtn(1, Icons.grid_view_rounded, '封面'),
            _viewModeBtn(2, Icons.apps_rounded, '按钮'),
          ],
        ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_episodes.length, (i) => _buildEpisodeTile(_episodes[i], i)),
    );
  }

  /// 封面九宫格视图
  Widget _buildEpisodeGrid() {
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
            children: List.generate(_episodes.length, (i) {
              final ep = _episodes[i];
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 12 : constraints.maxWidth > 600 ? 8 : 6;
        final btnSize = (constraints.maxWidth - 20 * 2 - (crossCount - 1) * 8) / crossCount;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_episodes.length, (i) {
              final ep = _episodes[i];
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
    final posterUrl = epPoster.isNotEmpty
        ? _app.api.getImageUrl(epPoster, width: 200)
        : '';
    final hasProgress = ep.ts > 0 && ep.duration > 0;
    final progress = hasProgress ? ep.ts / ep.duration : 0.0;
    final epNum = ep.episodeNumber > 0 ? ep.episodeNumber : index + 1;

    return InkWell(
      onTap: () => _playItem(ep),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Episode thumbnail
            Container(
              width: 120,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
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
                        child: Text('$epNum',
                          style: const TextStyle(color: FnTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    )
                  else
                    Center(
                      child: Text('$epNum',
                        style: const TextStyle(color: FnTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  // Play icon overlay
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 28),
                  ),
                  // Progress bar
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
            const SizedBox(width: 14),
            // Episode info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第$epNum集${ep.title != null && ep.title!.isNotEmpty ? '  ${ep.title}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FnTheme.textPrimary,
                    ),
                  ),
                  if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ep.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: FnTheme.textMuted, height: 1.4),
                    ),
                  ],
                  if (ep.duration > 0 || ep.watched > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (ep.duration > 0)
                          Text(
                            _formatDuration(ep.duration),
                            style: const TextStyle(fontSize: 11, color: FnTheme.textMuted),
                          ),
                        if (ep.watched > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_rounded, color: FnTheme.danmuGreen, size: 14),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
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
