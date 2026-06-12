import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/account_select_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/theme.dart';

import 'utils/log_buffer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LogBuffer.instance.install();
  MediaKit.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  runApp(const FnTvApp());
}

class FnTvApp extends StatelessWidget {
  const FnTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (ctx, app, _) {
          return MaterialApp(
            title: '飞牛TV',
            debugShowCheckedModeBanner: false,
            theme: FnTheme.dark,
            home: !app.initDone
                ? const _SplashScreen()
                : app.sessionRestoring
                    ? _SplashScreen(
                        showSwitchAccount: app.accounts.isNotEmpty,
                        statusText: '正在连接服务器…',
                      )
                    : app.isLoggedIn
                        ? const MainShell()
                        : app.accounts.isNotEmpty
                            ? const AccountSelectScreen()
                            : const LoginScreen(),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final bool showSwitchAccount;
  final String? statusText;

  const _SplashScreen({
    this.showSwitchAccount = false,
    this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: FnTheme.danmuGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.play_circle_fill_rounded, size: 40, color: FnTheme.danmuGreen),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: FnTheme.danmuGreen, strokeWidth: 2.5),
            if (statusText != null) ...[
              const SizedBox(height: 16),
              Text(
                statusText!,
                style: const TextStyle(color: FnTheme.textSecondary, fontSize: 13),
              ),
            ],
            if (showSwitchAccount) ...[
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () => context.read<AppState>().cancelSessionRestore(),
                icon: const Icon(Icons.switch_account_rounded, size: 18),
                label: const Text('切换账号'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FnTheme.danmuGreen,
                  side: BorderSide(color: FnTheme.danmuGreen.withOpacity(0.35)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '连接较慢？可切换其他服务器或添加新账号',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _pages = const [
    HomeScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(
            top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, '首页'),
                _buildNavItem(1, Icons.video_library_rounded, Icons.video_library_outlined, '媒体库'),
                _buildNavItem(2, Icons.settings_rounded, Icons.settings_outlined, '设置'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final selected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: selected
                  ? BoxDecoration(
                      color: FnTheme.danmuGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Icon(
                selected ? activeIcon : inactiveIcon,
                size: 22,
                color: selected ? FnTheme.danmuGreen : const Color(0xFF666666),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? FnTheme.danmuGreen : const Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
