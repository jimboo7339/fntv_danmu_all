import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/media_item.dart';
import '../models/play_list_item.dart';

import '../models/watch_record.dart';
import '../utils/theme.dart';
import '../widgets/media_card.dart';
import '../widgets/continue_watching_card.dart';
import 'player_screen.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MediaDbItem> _libraries = [];
  Map<String, List<PlayListItem>> _previews = {};
  bool _loading = true;
  String? _browseGuid;
  String? _browseTitle;
  List<PlayListItem>? _browseItems;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  AppState get _app => context.read<AppState>();

  Future<void> _loadOverview() async {
    setState(() { _loading = true; _browseGuid = null; _browseItems = null; });
    try {
      // 同时加载媒体库列表和服务端继续观看记录
      final results = await Future.wait([
        _app.api.getMediaDbList(),
        _app.fetchServerPlayList(),
      ]);
      final resp = results[0] as Map<String, dynamic>;
      if (resp['code'] == 0 && resp['data'] != null) {
        _libraries = (resp['data'] as List).map((e) => MediaDbItem.fromJson(e)).toList();
        for (final lib in _libraries) {
          _loadPreview(lib.guid);
        }
      }
    } catch (e) {
      debugPrint('loadOverview error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPreview(String guid) async {
    try {
      final resp = await _app.api.getItemList({
        'ancestor_guid': guid,
        'tags': {'type': ['Movie', 'TV', 'Directory', 'Video']},
        'exclude_grouped_video': 1,
        'sort_type': 'DESC',
        'sort_column': 'create_time',
        'page_size': 22,
      });
      if (resp['code'] == 0 && resp['data'] != null && resp['data']['list'] != null) {
        final items = (resp['data']['list'] as List).map((e) => PlayListItem.fromJson(e)).toList();
        if (mounted) setState(() => _previews[guid] = items.take(10).toList());
      }
    } catch (e) {
      debugPrint('loadPreview $guid error: $e');
    }
  }

  Future<void> _fetchItems(String guid, String title) async {
    setState(() { _loading = true; _browseGuid = guid; _browseTitle = title; });
    try {
      final resp = await _app.api.getItemList({
        'ancestor_guid': guid,
        'tags': {'type': ['Movie', 'TV', 'Directory', 'Video']},
        'exclude_grouped_video': 1,
        'sort_type': 'DESC',
        'sort_column': 'create_time',
        'page_size': 50,
      });
      if (resp['code'] == 0 && resp['data'] != null && resp['data']['list'] != null) {
        _browseItems = (resp['data']['list'] as List).map((e) => PlayListItem.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('browseItems error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onItemTap(PlayListItem item) {
    if (item.type == 'Directory') {
      // Directory: navigate into folder
      _fetchItems(item.guid, item.title ?? '');
      return;
    }
    // TV / Movie / Episode / Video → go to detail screen
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DetailScreen(item: item),
    ));
  }

  void _onWatchRecordTap(WatchRecord record) {
    debugPrint('WatchRecord tap: ${record.title} seekTs=${record.ts} dur=${record.duration}');
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        itemGuid: record.guid,
        title: record.title,
        tvTitle: record.tvTitle ?? '',
        episodeNumber: record.episodeNumber,
        poster: record.poster ?? '',
        category: record.libraryName ?? '',
        seekTs: record.ts,
        duration: record.duration,
        parentGuid: record.parentGuid,
      ),
    ));
  }

  int _calcColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1200) return 7;
    if (w > 900) return 5;
    if (w > 600) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    if (_browseGuid != null && _browseItems != null) {
      return _buildBrowseView();
    }
    return _buildOverview();
  }

  Widget _buildOverview() {
    final history = context.watch<AppState>().watchHistory.where((r) => !r.isNearlyFinished).toList();
    return _loading
        ? const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen))
        : RefreshIndicator(
            onRefresh: _loadOverview,
            child: CustomScrollView(
              slivers: [
                // App header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Icon(Icons.play_circle_fill_rounded,
                          color: FnTheme.danmuGreen, size: 24),
                        const SizedBox(width: 8),
                        Text('飞牛TV', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                      ],
                    ),
                  ),
                ),
                // Continue watching
                if (history.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.play_circle_outline, color: FnTheme.danmuGreen, size: 20),
                          SizedBox(width: 6),
                          Text('继续观看', style: TextStyle(
                            color: FnTheme.danmuGreen, fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: history.length,
                        itemBuilder: (_, i) => ContinueWatchingCard(
                          record: history[i],
                          imageUrl: _app.api.getImageUrl(history[i].poster),
                          onTap: () => _onWatchRecordTap(history[i]),
                        ),
                      ),
                    ),
                  ),
                ],
                // Library previews
                for (final lib in _libraries) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(lib.title, style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17, color: FnTheme.textPrimary))),
                          TextButton(
                            onPressed: () => _fetchItems(lib.guid, lib.title),
                            child: const Text('查看全部 ›', style: TextStyle(color: FnTheme.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_previews[lib.guid] != null && _previews[lib.guid]!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _previews[lib.guid]!.length,
                          itemBuilder: (_, i) => MediaCard(
                            item: _previews[lib.guid]![i],
                            imageUrl: _app.api.getImageUrl(_previews[lib.guid]![i].poster),
                            onTap: () => _onItemTap(_previews[lib.guid]![i]),
                          ),
                        ),
                      ),
                    )
                  else
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen)),
                      ),
                    ),
                ],
                if (_libraries.isEmpty && !_loading)
                  const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.movie_outlined, size: 48, color: FnTheme.textMuted),
                            SizedBox(height: 12),
                            Text('暂无影视内容', style: TextStyle(color: FnTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
  }

  Widget _buildBrowseView() {
    return Column(
      children: [
        // Back bar
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() { _browseGuid = null; _browseItems = null; }),
              ),
              Text(_browseTitle ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (_browseItems != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${_browseItems!.length} 项',
                    style: const TextStyle(color: FnTheme.textSecondary, fontSize: 13)),
                ),
            ],
          ),
        ),
        Expanded(
          child: _browseItems == null
              ? const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen))
              : _browseItems!.isEmpty
                  ? const Center(child: Text('暂无内容', style: TextStyle(color: Colors.grey)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _calcColumns(context),
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _browseItems!.length,
                      itemBuilder: (_, i) => MediaCard(
                        item: _browseItems![i],
                        imageUrl: _app.api.getImageUrl(_browseItems![i].poster),
                        onTap: () => _onItemTap(_browseItems![i]),
                        showTitle: true,
                      ),
                    ),
        ),
      ],
    );
  }
}
