import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  List<PlayListItem> _episodes = [];
  bool _loadingInfo = true;
  bool _loadingEpisodes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  AppState get _app => context.read<AppState>();

  Future<void> _loadData() async {
    // Load play info for all types (gives us rich metadata)
    await _loadPlayInfo();
    // If TV type, also load episodes
    if (widget.item.isFolder) {
      await _loadEpisodes();
    }
  }

  Future<void> _loadPlayInfo() async {
    try {
      final resp = await _app.api.getPlayInfo(widget.item.guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        if (mounted) setState(() {
          _playInfo = PlayInfoResponse.fromJson(resp['data']);
          _loadingInfo = false;
        });
      } else {
        if (mounted) setState(() {
          _error = '获取详情失败';
          _loadingInfo = false;
        });
      }
    } catch (e) {
      debugPrint('loadPlayInfo error: $e');
      if (mounted) setState(() {
        _error = '获取详情失败: $e';
        _loadingInfo = false;
      });
    }
  }

  Future<void> _loadEpisodes() async {
    if (mounted) setState(() => _loadingEpisodes = true);
    try {
      final resp = await _app.api.getItemList({
        'ancestor_guid': widget.item.guid,
        'tags': {'type': ['Episode', 'Video']},
        'exclude_grouped_video': 1,
        'sort_type': 'ASC',
        'sort_column': 'episode_number',
        'page_size': 200,
      });
      if (resp['code'] == 0 && resp['data'] != null && resp['data']['list'] != null) {
        final items = (resp['data']['list'] as List).map((e) => PlayListItem.fromJson(e)).toList();
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
          poster: widget.item.poster,
          libraryName: item.ancestorName,
          parentGuid: info.parentGuid ?? item.parentGuid,
          ts: item.ts,
          duration: item.duration,
        ));
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PlayerScreen(
              itemGuid: item.guid,
              title: item.title ?? '',
              tvTitle: item.tvTitle ?? widget.item.title ?? '',
              episodeNumber: item.episodeNumber,
              poster: widget.item.poster ?? '',
              category: widget.item.categoryLabel,
              seekTs: item.ts,
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

  String get _posterUrl {
    // Try playInfo item poster first, then fall back to original item poster
    final poster = _playInfo?.posterPath ?? _playInfo?.item?.poster ?? widget.item.poster;
    if (poster != null && poster.isNotEmpty) {
      return _app.api.getImageUrl(poster, width: 600);
    }
    return '';
  }

  String get _backdropUrl {
    final bd = _playInfo?.item?.backdrops;
    if (bd != null && bd.isNotEmpty) {
      return _app.api.getImageUrl(bd, width: 1200);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FnTheme.surfaceDark,
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
              _loadData();
            },
            child: const Text('重试', style: TextStyle(color: FnTheme.danmuGreen)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final item = _playInfo?.item;
    final isTv = widget.item.isFolder;

    return CustomScrollView(
      slivers: [
        // Hero area with poster + backdrop
        SliverToBoxAdapter(child: _buildHeroSection(item)),
        // Info section
        SliverToBoxAdapter(child: _buildInfoSection(item)),
        // Play button (movie) or Episode list (TV)
        if (!isTv)
          SliverToBoxAdapter(child: _buildPlayButton())
        else ...[
          SliverToBoxAdapter(child: _buildEpisodeHeader()),
          _buildEpisodeList(),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildHeroSection(ItemInfo? item) {
    final backdropUrl = _backdropUrl;
    final posterUrl = _posterUrl;

    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop or gradient
          if (backdropUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdropUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: const Color(0xFF121212)),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1A2E), FnTheme.surfaceDark],
                ),
              ),
            ),
          // Gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, FnTheme.surfaceDark],
                stops: [0.3, 1.0],
              ),
            ),
          ),
          // Back button
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
          // Poster card
          Positioned(
            left: 20,
            bottom: 0,
            child: Container(
              width: 130,
              height: 190,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 40)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF2A2A2A),
                      child: const Center(child: Icon(Icons.movie_rounded, color: Colors.grey, size: 40)),
                    ),
            ),
          ),
          // Title next to poster
          Positioned(
            left: 165,
            bottom: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.title ?? widget.item.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: FnTheme.textPrimary,
                  ),
                ),
                if (item?.originalTitle != null && item!.originalTitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item!.originalTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: FnTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ItemInfo? item) {
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
              if (item?.voteAverage != null && item!.voteAverage!.isNotEmpty)
                _tag('⭐ ${item.voteAverage}', Colors.amber),
              if (item?.runtime != null && item!.runtime > 0)
                _tag('${item.runtime} 分钟', FnTheme.textSecondary),
              if (item?.airDate != null && item!.airDate!.isNotEmpty)
                _tag(item!.airDate!.substring(0, item.airDate!.length > 4 ? 4 : item.airDate!.length), FnTheme.textSecondary),
              if (widget.item.numberOfSeasons > 0)
                _tag('${widget.item.numberOfSeasons} 季', FnTheme.textSecondary),
              if (widget.item.numberOfEpisodes > 0)
                _tag('${widget.item.numberOfEpisodes} 集', FnTheme.textSecondary),
            ],
          ),
          // Overview
          if (item?.overview != null && item!.overview!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              item!.overview!,
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

  Widget _buildPlayButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () => _playItem(widget.item),
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: const Text('播放', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
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
          const Spacer(),
          if (_episodes.isNotEmpty)
            Text('${_episodes.length} 集', style: const TextStyle(
              color: FnTheme.textMuted, fontSize: 13,
            )),
        ],
      ),
    );
  }

  Widget _buildEpisodeList() {
    if (_loadingEpisodes) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen)),
        ),
      );
    }
    if (_episodes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('暂无剧集', style: TextStyle(color: FnTheme.textMuted))),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => _buildEpisodeTile(_episodes[i], i),
        childCount: _episodes.length,
      ),
    );
  }

  Widget _buildEpisodeTile(PlayListItem ep, int index) {
    final epPoster = ep.poster ?? widget.item.poster;
    final posterUrl = epPoster != null && epPoster.isNotEmpty
        ? _app.api.getImageUrl(epPoster, width: 200)
        : '';
    final hasProgress = ep.ts > 0 && ep.duration > 0;
    final progress = hasProgress ? ep.ts / ep.duration : 0.0;

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
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text('${ep.episodeNumber > 0 ? ep.episodeNumber : index + 1}',
                          style: const TextStyle(color: FnTheme.textMuted, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    )
                  else
                    Center(
                      child: Text('${ep.episodeNumber > 0 ? ep.episodeNumber : index + 1}',
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
                    ep.title ?? '第 ${ep.episodeNumber > 0 ? ep.episodeNumber : index + 1} 集',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: FnTheme.textPrimary,
                    ),
                  ),
                  if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ep.overview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: FnTheme.textMuted),
                    ),
                  ],
                  if (ep.duration > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(ep.duration),
                      style: const TextStyle(fontSize: 11, color: FnTheme.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            // Watched indicator
            if (ep.watched > 0)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle_rounded, color: FnTheme.danmuGreen, size: 20),
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
