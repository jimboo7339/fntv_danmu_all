import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/log_buffer.dart';
import 'danmu_settings_screen.dart';

// ────────────────────────────────────────────────────────────
//  主设置页 — 二级菜单入口
// ────────────────────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // ── 账号信息卡片 ──
              if (app.currentAccount != null)
                _AccountCard(account: app.currentAccount!),
              const SizedBox(height: 20),

              // ── 播放器设置 ──
              _MenuTile(
                icon: Icons.play_circle_rounded,
                color: FnTheme.danmuGreen,
                title: '播放器设置',
                subtitle: '${app.playerEngine == 'mpv' ? 'MPV' : 'ExoPlayer'} · ${app.decoderMode == 'hardware' ? '硬解' : '软解'}',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _PlayerSettingsPage()),
                ),
              ),
              const SizedBox(height: 10),

              // ── 弹幕设置 ──
              _MenuTile(
                icon: Icons.subtitles_rounded,
                color: FnTheme.danmuGreen,
                title: '弹幕设置',
                subtitle: app.danmuOn ? '已开启 · ${app.danmuFontSize.toInt()}px' : '已关闭',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DanmuSettingsScreen()),
                ),
              ),
              const SizedBox(height: 10),

              // ── 账号管理 ──
              _MenuTile(
                icon: Icons.people_rounded,
                color: FnTheme.danmuGreen,
                title: '账号管理',
                subtitle: '${app.accounts.length} 个账号',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _AccountManagePage()),
                ),
              ),
              const SizedBox(height: 10),

              // ── 关于 ──
              _MenuTile(
                icon: Icons.info_outline_rounded,
                color: FnTheme.textMuted,
                title: '关于',
                subtitle: _version.isNotEmpty ? '飞牛TV ${_version.startsWith('v') ? _version : 'v$_version'}' : '飞牛TV',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => _AboutPage(version: _version)),
                ),
              ),
              const SizedBox(height: 10),

              // ── 调试日志 ──
              _MenuTile(
                icon: Icons.bug_report_rounded,
                color: Colors.orange,
                title: '调试日志',
                subtitle: '${LogBuffer.instance.entries.length} 条记录',
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  通用菜单入口 Tile
// ────────────────────────────────────────────────────────────
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  账号信息卡片（主设置页内嵌）
// ────────────────────────────────────────────────────────────
class _AccountCard extends StatelessWidget {
  final dynamic account;
  const _AccountCard({required this.account});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: FnTheme.danmuGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.dns_rounded, size: 26, color: FnTheme.danmuGreen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.user,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(account.host.replaceAll(RegExp(r'^https?://'), ''),
                    style: const TextStyle(color: FnTheme.textSecondary, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 7, height: 7,
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('已连接', style: TextStyle(color: Colors.green[400], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  播放器设置 二级页面
// ────────────────────────────────────────────────────────────
class _PlayerSettingsPage extends StatelessWidget {
  const _PlayerSettingsPage();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('播放器设置'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 播放内核
          Card(
            child: ListTile(
              title: const Text('播放内核'),
              subtitle: Text(
                app.playerEngine == 'mpv' ? 'MPV (libmpv) — 解码能力强' : 'ExoPlayer — Android 原生',
                style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showEnginePicker(context, app),
            ),
          ),
          const SizedBox(height: 10),

          // 解码模式
          Card(
            child: ListTile(
              title: const Text('解码模式'),
              subtitle: Text(app.decoderMode == 'hardware' ? '硬解' : '软解'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showDecoderPicker(context, app),
            ),
          ),
          const SizedBox(height: 10),

          // 快进步长
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('快进步长'),
                  subtitle: Text('${app.seekStep} 秒'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showSeekStepPicker(context, app),
                ),
                ListTile(
                  title: const Text('长按倍速'),
                  subtitle: Text('${app.danmuLongPressSpeed}x'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showLongPressSpeedPicker(context, app),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showEnginePicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('播放内核'),
      children: [
        RadioListTile(
          value: 'mpv', groupValue: app.playerEngine,
          title: const Text('MPV (libmpv)'),
          subtitle: const Text('解码能力强，支持内嵌字幕/音轨'),
          onChanged: (v) { app.playerEngine = v!; Navigator.pop(ctx); },
        ),
        RadioListTile(
          value: 'exo', groupValue: app.playerEngine,
          title: const Text('ExoPlayer'),
          subtitle: const Text('Android 原生，兼容性好，软件字幕'),
          onChanged: (v) { app.playerEngine = v!; Navigator.pop(ctx); },
        ),
      ],
    ));
  }

  void _showDecoderPicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('解码模式'),
      children: [
        RadioListTile(value: 'hardware', groupValue: app.decoderMode,
          title: const Text('硬解'), onChanged: (v) { app.decoderMode = v!; Navigator.pop(ctx); }),
        RadioListTile(value: 'software', groupValue: app.decoderMode,
          title: const Text('软解'), onChanged: (v) { app.decoderMode = v!; Navigator.pop(ctx); }),
      ],
    ));
  }

  void _showSeekStepPicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('快进步长'),
      children: [5, 10, 15, 30].map((s) => RadioListTile(
        value: s, groupValue: app.seekStep,
        title: Text('$s 秒'),
        onChanged: (v) { app.seekStep = v!; Navigator.pop(ctx); },
      )).toList(),
    ));
  }

  void _showLongPressSpeedPicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('长按倍速'),
      children: [1.5, 2.0, 2.5, 3.0].map((s) => RadioListTile(
        value: s, groupValue: app.danmuLongPressSpeed,
        title: Text('${s}x'),
        onChanged: (v) { app.danmuLongPressSpeed = v!; Navigator.pop(ctx); },
      )).toList(),
    ));
  }
}

// ────────────────────────────────────────────────────────────
//  账号管理 二级页面
// ────────────────────────────────────────────────────────────
class _AccountManagePage extends StatelessWidget {
  const _AccountManagePage();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('账号管理'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ...app.accounts.map((acc) => ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: acc.id == app.currentAccount?.id
                          ? FnTheme.danmuGreen.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_rounded, size: 20,
                      color: acc.id == app.currentAccount?.id
                          ? FnTheme.danmuGreen : FnTheme.textMuted),
                  ),
                  title: Text(acc.user,
                    style: TextStyle(
                      fontWeight: acc.id == app.currentAccount?.id
                          ? FontWeight.bold : FontWeight.normal,
                    )),
                  subtitle: Text(acc.host.replaceAll(RegExp(r'^https?://'), ''),
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                    overflow: TextOverflow.ellipsis),
                  trailing: acc.id == app.currentAccount?.id
                      ? const Icon(Icons.check_circle_rounded, color: FnTheme.danmuGreen, size: 20)
                      : null,
                  onTap: acc.id == app.currentAccount?.id ? null : () async {
                    final ok = await app.switchAccount(acc.id);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已切换到 ${acc.label}')),
                      );
                    }
                  },
                )),
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_rounded, size: 20, color: FnTheme.textMuted),
                  ),
                  title: const Text('切换 / 添加账号'),
                  onTap: () {
                    app.logout();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 退出登录
          Card(
            child: ListTile(
              title: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
              trailing: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              onTap: () {
                app.logout();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  关于 二级页面
// ────────────────────────────────────────────────────────────
class _AboutPage extends StatelessWidget {
  final String version;
  const _AboutPage({required this.version});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('关于'),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App icon & name
          const SizedBox(height: 32),
          Center(
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: FnTheme.danmuGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.tv_rounded, size: 36, color: FnTheme.danmuGreen),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('飞牛TV',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Center(
            child: Text(
              version.isNotEmpty ? (version.startsWith('v') ? version : 'v$version') : 'v--',
              style: const TextStyle(color: FnTheme.textSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(height: 32),

          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('版本号'),
                  trailing: Text(version.isNotEmpty ? version : '--',
                    style: const TextStyle(color: FnTheme.textSecondary)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Framework'),
                  trailing: const Text('Flutter', style: TextStyle(color: FnTheme.textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  日志查看器
// ────────────────────────────────────────────────────────────
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final _scrollController = ScrollController();
  String _filter = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = LogBuffer.instance.entries;
    final entries = _filter.isEmpty
        ? allEntries
        : allEntries.where((e) => e.message.contains(_filter)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('调试日志'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '复制全部',
            onPressed: () {
              final text = LogBuffer.instance.dump();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '清空',
            onPressed: () {
              setState(() => LogBuffer.instance.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '过滤日志...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${entries.length} 条${_filter.isNotEmpty ? ' (共 ${allEntries.length} 条)' : ''}',
                  style: const TextStyle(color: FnTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('暂无日志', style: TextStyle(color: FnTheme.textMuted)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText(
                          '[${e.time.toIso8601String().substring(11, 23)}] ${e.message}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: FnTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: FnTheme.danmuGreen,
        onPressed: () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        },
        child: const Icon(Icons.arrow_downward, size: 18),
      ),
    );
  }
}
