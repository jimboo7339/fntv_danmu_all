import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';
import 'login_screen.dart';

/// 有缓存账号时展示的账号选择页。
class AccountSelectScreen extends StatefulWidget {
  const AccountSelectScreen({super.key});

  @override
  State<AccountSelectScreen> createState() => _AccountSelectScreenState();
}

class _AccountSelectScreenState extends State<AccountSelectScreen> {
  String? _loadingId;

  Future<void> _selectAccount(SavedAccount acc) async {
    if (_loadingId != null) return;
    setState(() => _loadingId = acc.id);
    final app = context.read<AppState>();
    final ok = await app.switchAccount(acc.id);
    if (!mounted) return;

    if (ok) {
      setState(() => _loadingId = null);
      return;
    }

    // Token 失效：有密码则自动重登，否则跳转登录页补密码
    if (acc.pass.isNotEmpty) {
      final relogin = await app.login(acc.host, acc.user, acc.pass, true);
      if (relogin) {
        if (mounted) setState(() => _loadingId = null);
        return;
      }
    }

    if (mounted) {
      setState(() => _loadingId = null);
      FnToast.show(context, '登录已过期，请重新输入密码', type: FnToastType.warning);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            fromAccountPicker: true,
            initialHost: acc.host,
            initialUser: acc.user,
          ),
        ),
      );
    }
  }

  void _openAddAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen(fromAccountPicker: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final accounts = app.accounts;

    if (accounts.isEmpty) {
      return const LoginScreen();
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _buildHeader(context),
                  const SizedBox(height: 28),
                  Text(
                    '选择账号',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: FnTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '点击账号进入，或添加新的服务器账号',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),
                  ...accounts.map((acc) => _AccountTile(
                    account: acc,
                    loading: _loadingId == acc.id,
                    onTap: () => _selectAccount(acc),
                    onDelete: () {
                      app.removeAccount(acc.id);
                      FnToast.show(context, '已删除 ${acc.label}', type: FnToastType.success);
                    },
                  )),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadingId != null ? null : _openAddAccount,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('添加新账号'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FnTheme.danmuGreen,
                      side: BorderSide(color: FnTheme.danmuGreen.withOpacity(0.35)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: FnTheme.danmuGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.play_circle_fill_rounded, size: 44, color: FnTheme.danmuGreen),
        ),
        const SizedBox(height: 14),
        Text(
          '飞牛TV',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '弹幕版 · 跨平台客户端',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final SavedAccount account;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AccountTile({
    required this.account,
    required this.loading,
    required this.onTap,
    required this.onDelete,
  });

  String get _hostDisplay => account.host.replaceAll(RegExp(r'^https?://'), '');

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FnTheme.danmuGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_rounded, size: 24, color: FnTheme.danmuGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.user,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hostDisplay,
                      style: const TextStyle(color: FnTheme.textSecondary, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: FnTheme.danmuGreen),
                )
              else ...[
                const Icon(Icons.chevron_right_rounded, color: FnTheme.textMuted),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: FnTheme.textMuted),
                  onPressed: onDelete,
                  tooltip: '删除账号',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
