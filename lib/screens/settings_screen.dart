import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../models/mpv_player_settings.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';
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
                subtitle: 'MPV · ${MpvPlayerSettings.hwdecLabel(app.mpvHwdec)}',
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
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bug_report_rounded, size: 20, color: Colors.orange),
                      ),
                      title: const Text('记录调试日志'),
                      subtitle: Text(
                        app.debugLogEnabled
                            ? '已开启 · ${LogBuffer.instance.entries.length} 条'
                            : '默认关闭，排查问题时再开启',
                        style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                      ),
                      value: app.debugLogEnabled,
                      activeColor: FnTheme.danmuGreen,
                      onChanged: (v) => app.debugLogEnabled = v,
                    ),
                    if (app.debugLogEnabled)
                      ListTile(
                        leading: const SizedBox(width: 36),
                        title: const Text('查看日志'),
                        subtitle: Text(
                          '${LogBuffer.instance.entries.length} 条记录',
                          style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                        ),
                      ),
                  ],
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
          _buildMpvInfoCard(),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('硬件解码器'),
                  subtitle: Text(
                    MpvPlayerSettings.hwdecLabel(app.mpvHwdec),
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showOptionSheet(
                    context,
                    title: '硬件解码器',
                    options: MpvPlayerSettings.hwdecOptions,
                    current: app.mpvHwdec,
                    label: MpvPlayerSettings.hwdecLabel,
                    description: MpvPlayerSettings.hwdecDescription,
                    onSelect: (v) => app.mpvHwdec = v,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('视频渲染器'),
                  subtitle: Text(
                    MpvPlayerSettings.voLabel(app.mpvVo),
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showOptionSheet(
                    context,
                    title: '视频渲染器',
                    options: MpvPlayerSettings.voOptions,
                    current: app.mpvVo,
                    label: MpvPlayerSettings.voLabel,
                    description: MpvPlayerSettings.voDescription,
                    onSelect: (v) => app.mpvVo = v,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('最大缓冲大小')),
                      Text('${app.mpvBufferMb} MB',
                        style: const TextStyle(color: FnTheme.danmuGreen, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Slider(
                    value: app.mpvBufferMb.toDouble(),
                    min: 50,
                    max: 512,
                    divisions: 23,
                    activeColor: FnTheme.danmuGreen,
                    label: '${app.mpvBufferMb} MB',
                    onChanged: (v) => app.mpvBufferMb = v.round(),
                  ),
                  const Text('增大可缓解卡顿，但会占用更多内存',
                    style: TextStyle(fontSize: 11, color: FnTheme.textMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('预读缓冲时长')),
                      Text('${app.mpvCacheSecs} s',
                        style: const TextStyle(color: FnTheme.danmuGreen, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Slider(
                    value: app.mpvCacheSecs.toDouble(),
                    min: 10,
                    max: 300,
                    divisions: 29,
                    activeColor: FnTheme.danmuGreen,
                    label: '${app.mpvCacheSecs} s',
                    onChanged: (v) => app.mpvCacheSecs = v.round(),
                  ),
                  const Text('网络流建议 60s 以上，局域网可适当降低',
                    style: TextStyle(fontSize: 11, color: FnTheme.textMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              title: const Text('画面插帧'),
              subtitle: const Text('开启后运动画面更顺滑，部分设备可能增加延迟'),
              value: app.mpvInterpolation,
              activeColor: FnTheme.danmuGreen,
              onChanged: (v) => app.mpvInterpolation = v,
            ),
          ),
          const SizedBox(height: 10),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '修改解码/渲染/缓冲设置后，需重新进入播放页生效',
              style: TextStyle(fontSize: 12, color: FnTheme.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMpvInfoCard() {
    return Card(
      color: FnTheme.danmuGreen.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.play_circle_fill_rounded, color: FnTheme.danmuGreen.withOpacity(0.9), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MPV 播放内核', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 4),
                  Text(
                    '开源跨平台引擎，支持广泛格式、内嵌字幕与多音轨。'
                    '可按设备情况调整硬解与缓冲策略。',
                    style: TextStyle(fontSize: 12, color: FnTheme.textSecondary, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionSheet(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String current,
    required String Function(String) label,
    required String Function(String) description,
    required void Function(String) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ...options.map((opt) {
              final selected = opt == current;
              return ListTile(
                title: Text(label(opt),
                  style: TextStyle(
                    color: selected ? FnTheme.danmuGreen : FnTheme.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  )),
                subtitle: description(opt).isNotEmpty
                    ? Text(description(opt),
                        style: const TextStyle(fontSize: 11, color: FnTheme.textMuted))
                    : null,
                trailing: selected
                    ? const Icon(Icons.check_rounded, color: FnTheme.danmuGreen, size: 20)
                    : null,
                onTap: () {
                  onSelect(opt);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                      FnToast.show(context, '已切换到 ${acc.label}', type: FnToastType.success);
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
              FnToast.show(context, '日志已复制到剪贴板', type: FnToastType.success);
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
