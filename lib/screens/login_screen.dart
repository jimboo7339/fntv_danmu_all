import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';
import '../utils/toast.dart';

/// 无缓存账号时的登录页；也可从账号选择页进入添加/重登。
class LoginScreen extends StatefulWidget {
  final bool fromAccountPicker;
  final String? initialHost;
  final String? initialUser;

  const LoginScreen({
    super.key,
    this.fromAccountPicker = false,
    this.initialHost,
    this.initialUser,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _remember = true;
  bool _loading = false;

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

    if (widget.initialHost != null) {
      _hostCtrl.text = widget.initialHost!;
    }
    if (widget.initialUser != null) {
      _userCtrl.text = widget.initialUser!;
    }

    if (_hostCtrl.text.isEmpty || _userCtrl.text.isEmpty) {
      final sp = await SharedPreferences.getInstance();
      if (_hostCtrl.text.isEmpty) {
        _hostCtrl.text = sp.getString('last_host') ?? sp.getString('host') ?? 'http://192.168.10.158:5666';
      }
      if (_userCtrl.text.isEmpty) {
        _userCtrl.text = sp.getString('user') ?? '';
      }
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
    if (ok && mounted) {
      FnToast.show(context, '登录成功', type: FnToastType.success);
      if (widget.fromAccountPicker) {
        Navigator.of(context).pop(true);
      }
    }
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.fromAccountPicker)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _loading ? null : () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('返回账号列表'),
                        style: TextButton.styleFrom(foregroundColor: FnTheme.textSecondary),
                      ),
                    ),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: FnTheme.danmuGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.play_circle_fill_rounded, size: 44, color: FnTheme.danmuGreen),
                    ),
                  ),
                  Text(
                    widget.fromAccountPicker ? '登录账号' : '飞牛TV',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.fromAccountPicker ? '输入服务器与账号密码' : '弹幕版 · 跨平台客户端',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 32),
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
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
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
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _doLogin,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('登 录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '登录账号为飞牛影视的账号密码',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
