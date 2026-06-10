import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/media_item.dart';
import '../models/play_list_item.dart';
import '../models/play_info.dart';
import '../models/watch_record.dart';
import '../utils/theme.dart';
import '../widgets/media_card.dart';
import '../widgets/continue_watching_card.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
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
      final resp = await _app.api.getMediaDbList();
      if (resp['code'] == 0 && resp['data'] != null) {
        _libraries = (resp['data'] as List).map((e) => MediaDbItem.fromJson(e)).toList();
        // Load previews for each library
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

  void _onItemTap(PlayListItem item) async {
    if (item.isFolder) {
      _fetchItems(item.guid, item.title ?? '');
      return;
    }
    // Get play info
    try {
      final resp = await _app.api.getPlayInfo(item.guid);
      if (resp['code'] == 0 && resp['data'] != null) {
        final info = PlayInfoResponse.fromJson(resp['data']);
        _launchPlayer(item, info);
      }
    } catch (e) {
      debugPrint('getPlayInfo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取播放信息失败: $e')),
        );
      }
    }
  }

  void _launchPlayer(PlayListItem item, PlayInfoResponse info) {
    final app = _app;
    app.addWatchRecord(WatchRecord(
      guid: item.guid,
      title: item.title ?? '',
      tvTitle: item.tvTitle,
      episodeNumber: item.episodeNumber,
      poster: item.poster,
      libraryName: item.ancestorName,
      parentGuid: info.parentGuid ?? item.parentGuid,
      ts: item.ts,
      duration: item.duration,
    ));
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PlayerScreen(
        itemGuid: item.guid,
        title: item.title ?? '',
        tvTitle: item.tvTitle ?? '',
        episodeNumber: item.episodeNumber,
        poster: item.poster ?? '',
        category: item.categoryLabel,
        seekTs: item.ts,
        duration: item.duration,
        parentGuid: info.parentGuid ?? item.parentGuid,
      ),
    ));
  }

  void _onWatchRecordTap(WatchRecord record) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Top tab bar
          _buildTopBar(),
          // Content
          Expanded(
            child: _currentTab == 2
                ? const SettingsScreen()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      color: const Color(0xFF1A1A1A),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          const Text('FnOS TV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          _tabBtn('首页', 0, Icons.home_outlined),
          _tabBtn('媒体库', 1, Icons.video_library_outlined),
          _tabBtn('设置', 2, Icons.settings_outlined),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _tabBtn(String label, int idx, IconData icon) {
    final selected = _currentTab == idx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: () {
          setState(() {
            _currentTab = idx;
            if (idx == 0 || idx == 1) {
              _browseGuid = null;
              _browseItems = null;
            }
          });
          if (idx == 1 && _libraries.isEmpty) _loadOverview();
        },
        icon: Icon(icon, size: 18, color: selected ? FnTheme.danmuGreen : Colors.grey),
        label: Text(label, style: TextStyle(
          color: selected ? FnTheme.danmuGreen : Colors.grey,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // If browsing a specific library
    if (_browseGuid != null && _browseItems != null) {
      return _buildBrowseView();
    }

    if (_currentTab == 0) {
      return _buildOverview();
    } else {
      return _buildLibraryList();
    }
  }

  Widget _buildOverview() {
    final history = _app.watchHistory.where((r) => !r.isNearlyFinished).toList();
    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: CustomScrollView(
        slivers: [
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
                height: 210,
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
                  height: 210,
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
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ),
          ],
          if (_libraries.isEmpty && !_loading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('暂无影视内容', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildLibraryList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _libraries.length,
      itemBuilder: (_, i) {
        final lib = _libraries[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                lib.category == 'TV' ? Icons.tv : Icons.movie_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(lib.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(lib.category ?? '', style: const TextStyle(color: FnTheme.textSecondary)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _fetchItems(lib.guid, lib.title),
          ),
        );
      },
    );
  }

  Widget _buildBrowseView() {
    return Column(
      children: [
        // Back bar
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _browseGuid = null; _browseItems = null; }),
              ),
              Text(_browseTitle ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              if (_browseItems != null)
                Text('${_browseItems!.length} 项', style: const TextStyle(color: FnTheme.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: _browseItems == null
              ? const Center(child: CircularProgressIndicator())
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

  int _calcColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1200) return 7;
    if (w > 900) return 5;
    if (w > 600) return 4;
    return 3;
  }
}
