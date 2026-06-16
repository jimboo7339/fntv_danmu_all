import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import '../models/mpv_player_settings.dart';
import '../models/update_mirror.dart';
import '../models/app_release_info.dart';
import '../providers/app_state.dart';
import '../services/update_service.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';
import '../utils/log_buffer.dart';
import 'danmu_settings_screen.dart';
import 'login_screen.dart';

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
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('音画同步模式'),
                  subtitle: Text(
                    MpvPlayerSettings.videoSyncLabel(app.mpvVideoSync),
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showOptionSheet(
                    context,
                    title: '音画同步模式',
                    options: MpvPlayerSettings.videoSyncOptions,
                    current: app.mpvVideoSync,
                    label: MpvPlayerSettings.videoSyncLabel,
                    description: MpvPlayerSettings.videoSyncDescription,
                    onSelect: (v) => app.mpvVideoSync = v,
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: const Text('网速指示器'),
                  subtitle: const Text('呼出进度条时显示当前网速与系统时间'),
                  value: app.showNetworkSpeed,
                  activeColor: FnTheme.danmuGreen,
                  onChanged: (v) => app.showNetworkSpeed = v,
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

  Future<void> _afterAccountChanged(BuildContext context) async {
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

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
                    if (!context.mounted) return;
                    if (ok) {
                      FnToast.show(context, '已切换到 ${acc.label}', type: FnToastType.success);
                      await _afterAccountChanged(context);
                    } else {
                      FnToast.show(context, '切换失败，请重新登录该账号', type: FnToastType.error);
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
                  title: const Text('添加账号'),
                  subtitle: const Text('登录新服务器账号'),
                  onTap: () async {
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(fromAccountPicker: true),
                      ),
                    );
                    if (ok == true && context.mounted) {
                      FnToast.show(context, '已登录 ${app.currentAccount?.label ?? ''}',
                          type: FnToastType.success);
                      await _afterAccountChanged(context);
                    }
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.switch_account_rounded, size: 20, color: FnTheme.textMuted),
                  ),
                  title: const Text('账号选择页'),
                  subtitle: const Text('退出当前登录，回到账号列表'),
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
class _AboutPage extends StatefulWidget {
  final String version;
  const _AboutPage({required this.version});

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  final _updateService = UpdateService();
  bool _checking = false;
  String? _statusText;

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _statusText = '正在检查更新…';
    });

    final result = await _updateService.checkForUpdate(widget.version);
    if (!mounted) return;

    setState(() {
      _checking = false;
      _statusText = null;
    });

    if (result.error != null) {
      FnToast.show(context, result.error!, type: FnToastType.error, duration: const Duration(seconds: 4));
      return;
    }

    if (!result.hasUpdate || result.release == null) {
      FnToast.show(context, '当前已是最新版本', type: FnToastType.success);
      return;
    }

    await _showUpdateDialog(result.release!);
  }

  Future<void> _showUpdateDialog(AppReleaseInfo release) async {
    final mirror = await showModalBottomSheet<UpdateMirror>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('发现新版本 ${release.versionLabel}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        if (release.apkSizeText.isNotEmpty)
                          Text(release.apkSizeText,
                            style: const TextStyle(fontSize: 12, color: FnTheme.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            if (release.body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  release.body.trim(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary, height: 1.4),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('选择下载源',
                style: TextStyle(fontSize: 13, color: FnTheme.textMuted, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: UpdateMirror.mirrors.map((m) => ListTile(
                  title: Text(m.label, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(m.description,
                    style: const TextStyle(fontSize: 11, color: FnTheme.textMuted)),
                  trailing: const Icon(Icons.download_rounded, color: FnTheme.danmuGreen, size: 20),
                  onTap: () => Navigator.pop(ctx, m),
                )).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (mirror != null && mounted) {
      await _downloadAndInstall(release, mirror);
    }
  }

  Future<void> _downloadAndInstall(AppReleaseInfo release, UpdateMirror mirror) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadUpdateDialog(
        updateService: _updateService,
        release: release,
        mirror: mirror,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.version;
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
                  title: const Text('检查更新'),
                  subtitle: Text(
                    _statusText ?? (_updateService.isSupported
                        ? '从 GitHub Releases 下载安装包'
                        : '仅 Android 客户端支持'),
                    style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                  ),
                  trailing: _checking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen),
                        )
                      : const Icon(Icons.system_update_rounded, color: FnTheme.danmuGreen),
                  enabled: _updateService.isSupported && !_checking,
                  onTap: _updateService.isSupported ? _checkUpdate : null,
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

class _DownloadUpdateDialog extends StatefulWidget {
  final UpdateService updateService;
  final AppReleaseInfo release;
  final UpdateMirror mirror;

  const _DownloadUpdateDialog({
    required this.updateService,
    required this.release,
    required this.mirror,
  });

  @override
  State<_DownloadUpdateDialog> createState() => _DownloadUpdateDialogState();
}

class _DownloadUpdateDialogState extends State<_DownloadUpdateDialog> {
  late final CancelToken _cancelToken;
  int _received = 0;
  int _total = 0;
  String _status = '连接中…';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    _total = widget.release.apkSize > 0 ? widget.release.apkSize : 0;
    _startDownload();
  }

  Future<void> _startDownload() async {
    if (_started) return;
    _started = true;

    try {
      final path = await widget.updateService.downloadApk(
        release: widget.release,
        mirror: widget.mirror,
        cancelToken: _cancelToken,
        onProgress: (r, t) {
          if (!mounted) return;
          setState(() {
            _received = r;
            if (t > 0) _total = t;
            _status = _total > 0
                ? '${(_received / _total * 100).toStringAsFixed(0)}%'
                : '${(_received / (1024 * 1024)).toStringAsFixed(1)} MB';
          });
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
      final openResult = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (!mounted) return;
      if (openResult.type != ResultType.done) {
        FnToast.show(context, '请允许安装未知来源应用', type: FnToastType.warning);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      FnToast.show(context, '下载失败: $e', type: FnToastType.error, duration: const Duration(seconds: 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text('正在下载 (${widget.mirror.label})',
          style: const TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _total > 0 ? _received / _total : null,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(FnTheme.danmuGreen),
          ),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(color: FnTheme.textSecondary, fontSize: 13)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelToken.cancel('user cancelled');
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
      ],
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
