import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _remember = true;
  bool _loading = false;
  bool _showNewAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefaults());
  }

  Future<void> _loadDefaults() async {
    final app = context.read<AppState>();
    while (!app.initDone && mounted) {
      await Future.delayed(const Duration(milliseconds: 30));
    }
    if (!mounted) return;

    final sp = await SharedPreferences.getInstance();
    final activeId = sp.getString('active_account_id') ?? '';
    SavedAccount? acc;
    if (activeId.isNotEmpty) {
      final matches = app.accounts.where((a) => a.id == activeId);
      if (matches.isNotEmpty) acc = matches.first;
    }
    acc ??= app.accounts.isNotEmpty ? app.accounts.first : null;

    if (acc != null) {
      _hostCtrl.text = acc.host;
      _userCtrl.text = acc.user;
      if (acc.pass.isNotEmpty) _passCtrl.text = acc.pass;
    } else {
      _hostCtrl.text = sp.getString('last_host') ?? sp.getString('host') ?? 'http://192.168.10.158:5666';
      _userCtrl.text = sp.getString('user') ?? '';
    }
    if (mounted) setState(() {});
  }

  Future<void> _doLogin() async {
    if (_loading) return;
    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (host.isEmpty || user.isEmpty || pass.isEmpty) {
      if (mounted) {
        FnToast.show(context, '所有字段都不能为空', type: FnToastType.warning);
      }
      return;
    }
    setState(() => _loading = true);
    final app = context.read<AppState>();
    final ok = await app.login(host, user, pass, _remember);
    if (!ok && mounted) {
      FnToast.show(context, '登录失败，请检查服务器地址和账号密码', type: FnToastType.error);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final accounts = app.accounts;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: FnTheme.danmuGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.play_circle_fill_rounded,
                      size: 44, color: FnTheme.danmuGreen),
                  ),
                  const SizedBox(height: 14),
                  Text('飞牛TV', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )),
                  const SizedBox(height: 4),
                  Text('弹幕版 · 跨平台客户端',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    )),
                  const SizedBox(height: 32),

                  // Saved accounts list
                  if (accounts.isNotEmpty && !_showNewAccount) ...[
                    Row(
                      children: [
                        const Icon(Icons.people_rounded, size: 18, color: FnTheme.textMuted),
                        const SizedBox(width: 6),
                        const Text('已保存账号', style: TextStyle(
                          color: FnTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...accounts.map((acc) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          setState(() => _loading = true);
                          final ok = await app.switchAccount(acc.id);
                          if (!ok) {
                            // Token expired, try re-login with saved pass
                            if (acc.pass.isNotEmpty) {
                              _hostCtrl.text = acc.host;
                              _userCtrl.text = acc.user;
                              _passCtrl.text = acc.pass;
                              setState(() => _loading = false);
                              _doLogin();
                              return;
                            }
                            if (mounted) {
                              FnToast.show(context, 'Token 已过期，请重新输入密码', type: FnToastType.warning);
                              _hostCtrl.text = acc.host;
                              _userCtrl.text = acc.user;
                              _passCtrl.text = '';
                              setState(() { _loading = false; _showNewAccount = true; });
                            }
                            return;
                          }
                          setState(() => _loading = false);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: FnTheme.danmuGreen.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.person_rounded, size: 22, color: FnTheme.danmuGreen),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(acc.user, style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(acc.host.replaceAll(RegExp(r'^https?://'), ''),
                                      style: const TextStyle(color: FnTheme.textSecondary, fontSize: 12),
                                      overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: FnTheme.textMuted),
                                onPressed: () {
                                  app.removeAccount(acc.id);
                                  if (mounted) {
                                    FnToast.show(context, '已删除 ${acc.label}', type: FnToastType.success);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(height: 8),
                    // Add new account button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _showNewAccount = true;
                          _passCtrl.text = '';
                        }),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加新账号'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FnTheme.danmuGreen,
                          side: BorderSide(color: FnTheme.danmuGreen.withOpacity(0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Login form (shown when no accounts or adding new)
                  if (accounts.isEmpty || _showNewAccount) ...[
                    if (accounts.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _showNewAccount = false),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('返回账号列表'),
                          style: TextButton.styleFrom(foregroundColor: FnTheme.textSecondary),
                        ),
                      ),
                    // Server
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        hintText: 'http://192.168.x.x:5666',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    // Username
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    // Password
                    TextField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _doLogin(),
                    ),
                    const SizedBox(height: 10),
                    // Remember
                    Row(
                      children: [
                        Checkbox(
                          value: _remember,
                          onChanged: (v) => setState(() => _remember = v ?? false),
                          activeColor: FnTheme.danmuGreen,
                        ),
                        const Text('保存账号'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _doLogin,
                        child: _loading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text('登 录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('登录账号为飞牛影视的账号密码',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
