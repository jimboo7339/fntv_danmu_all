import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/log_buffer.dart';
import 'danmu_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        // Scrollable content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Current server info
              if (app.currentAccount != null)
                Card(
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
                              Text(app.currentAccount!.user,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(height: 3),
                              Text(app.currentAccount!.host.replaceAll(RegExp(r'^https?://'), ''),
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
                ),
              const SizedBox(height: 20),

              // 弹幕设置 — 二级菜单入口
              _sectionTitle('弹幕'),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: FnTheme.danmuGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.subtitles_rounded, size: 20, color: FnTheme.danmuGreen),
                  ),
                  title: const Text('弹幕设置'),
                  subtitle: Text(
                    app.danmuOn ? '已开启 · ${app.danmuFontSize.toInt()}px · ${(app.danmuOpacity * 100).toInt()}%' : '已关闭',
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const DanmuSettingsScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 播放设置
              _sectionTitle('播放设置'),
              Card(
                child: Column(
                  children: [
                    // Player engine selector (Android only shows both, others show mpv info)
                    ListTile(
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: FnTheme.danmuGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.play_circle_rounded, size: 20, color: FnTheme.danmuGreen),
                      ),
                      title: const Text('播放内核'),
                      subtitle: Text(
                        app.playerEngine == 'mpv' ? 'MPV (libmpv) — 解码能力强' : 'ExoPlayer — Android 原生',
                        style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showEnginePicker(context, app),
                    ),
                    ListTile(
                      title: const Text('解码模式'),
                      subtitle: Text(app.decoderMode == 'hardware' ? '硬解' : '软解'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showDecoderPicker(context, app),
                    ),
                    ListTile(
                      title: const Text('快进步长'),
                      subtitle: Text('${app.seekStep} 秒'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showSeekStepPicker(context, app),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 弹幕服务器
              _sectionTitle('弹幕服务器'),
              Card(
                child: ListTile(
                  title: const Text('弹幕 API 地址'),
                  subtitle: Text(app.danmuUrl),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => _editDanmuUrl(context, app),
                ),
              ),
              const SizedBox(height: 16),

              // 账号管理
              _sectionTitle('账号管理'),
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
              const SizedBox(height: 16),

              // 关于
              _sectionTitle('关于'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      title: Text('版本'),
                      subtitle: Text('飞牛TV v1.0.0 (Flutter)'),
                    ),
                    ListTile(
                      title: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
                      trailing: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      onTap: () {
                        app.logout();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 调试日志
              _sectionTitle('调试'),
              Card(
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bug_report_rounded, size: 20, color: Colors.orange),
                  ),
                  title: const Text('查看日志'),
                  subtitle: Text(
                    '${LogBuffer.instance.entries.length} 条记录',
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showLogViewer(context),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(
        color: FnTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  void _showEnginePicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('播放内核'),
      children: [
        RadioListTile(
          value: 'mpv', groupValue: app.playerEngine,
          title: const Text('MPV (libmpv)'),
          subtitle: const Text('解码能力强，支持更多格式'),
          onChanged: (v) { app.playerEngine = v!; Navigator.pop(ctx); },
        ),
        RadioListTile(
          value: 'exo', groupValue: app.playerEngine,
          title: const Text('ExoPlayer'),
          subtitle: const Text('Android 原生，兼容性好'),
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

  void _editDanmuUrl(BuildContext ctx, AppState app) {
    final ctrl = TextEditingController(text: app.danmuUrl);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('弹幕 API 地址'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'http://host:9321')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () { app.danmuUrl = ctrl.text.trim(); Navigator.pop(ctx); }, child: const Text('保存')),
      ],
    ));
  }

  void _showLogViewer(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const LogViewerScreen(),
    ));
  }
}

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
          // Filter bar
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
          // Log count
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
          // Log list
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
