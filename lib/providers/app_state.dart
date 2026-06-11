import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_record.dart';
import '../services/api_client.dart';

/// Represents a saved account (server + user).
class SavedAccount {
  final String id;       // host|user as unique key
  final String host;
  final String user;
  final String pass;
  final String token;
  final String label;    // display name: "user@host"

  SavedAccount({
    required this.id,
    required this.host,
    required this.user,
    required this.pass,
    required this.token,
    String? label,
  }) : label = label ?? '$user@${_shortHost(host)}';

  static String _shortHost(String host) {
    var h = host.replaceAll(RegExp(r'^https?://'), '');
    h = h.replaceAll(RegExp(r':\d+$'), '');
    return h;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'host': host, 'user': user,
    'pass': pass, 'token': token, 'label': label,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    id: j['id'] ?? '', host: j['host'] ?? '', user: j['user'] ?? '',
    pass: j['pass'] ?? '', token: j['token'] ?? '', label: j['label'],
  );
}

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();
  late SharedPreferences _prefs;
  bool _isLoggedIn = false;
  bool _loading = false;
  List<WatchRecord> _watchHistory = [];
  List<SavedAccount> _accounts = [];
  SavedAccount? _currentAccount;

  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  List<WatchRecord> get watchHistory => _watchHistory;
  List<SavedAccount> get accounts => _accounts;
  SavedAccount? get currentAccount => _currentAccount;
  String get serverHost => _currentAccount?.host ?? '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadAccounts();
    // Try auto-login with last active account
    final activeId = _prefs.getString('active_account_id') ?? '';
    if (activeId.isNotEmpty) {
      final acc = _accounts.where((a) => a.id == activeId).toList();
      if (acc.isNotEmpty && acc.first.token.isNotEmpty) {
        _currentAccount = acc.first;
        api.updateBaseUrl(acc.first.host);
        api.setToken(acc.first.token);
        _isLoggedIn = true;
      }
    }
  }

  // ====== Accounts ======

  void _loadAccounts() {
    final json = _prefs.getString('accounts');
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        _accounts = list.map((e) => SavedAccount.fromJson(e)).toList();
      } catch (_) {
        _accounts = [];
      }
    }
  }

  void _saveAccounts() {
    _prefs.setString('accounts', jsonEncode(_accounts.map((a) => a.toJson()).toList()));
  }

  /// Switch to a saved account without re-login.
  Future<bool> switchAccount(String accountId) async {
    final acc = _accounts.where((a) => a.id == accountId).toList();
    if (acc.isEmpty) return false;
    final account = acc.first;
    if (account.token.isEmpty) return false;
    _currentAccount = account;
    api.updateBaseUrl(account.host);
    api.setToken(account.token);
    await _prefs.setString('active_account_id', account.id);
    // Clear watch history on account switch
    _watchHistory.clear();
    _isLoggedIn = true;
    notifyListeners();
    return true;
  }

  /// Remove a saved account.
  void removeAccount(String accountId) {
    _accounts.removeWhere((a) => a.id == accountId);
    _saveAccounts();
    notifyListeners();
  }

  // ====== Login / Logout ======

  Future<bool> login(String host, String user, String pass, bool remember) async {
    _loading = true;
    notifyListeners();
    try {
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        host = 'http://$host';
      }
      api.updateBaseUrl(host);
      final resp = await api.login(user, pass);
      if (resp['code'] == 0) {
        final token = resp['data']['token'] as String;
        api.setToken(token);

        // Build account id
        final accId = '$host|$user';
        final account = SavedAccount(
          id: accId, host: host, user: user,
          pass: remember ? pass : '', token: token,
        );

        // Update or add account
        _accounts.removeWhere((a) => a.id == accId);
        _accounts.insert(0, account);
        _currentAccount = account;
        _saveAccounts();

        // Set as active
        await _prefs.setString('active_account_id', accId);
        await _prefs.setBool('remember', remember);

        // Clear watch history on account switch
        final lastHost = _prefs.getString('last_host') ?? '';
        if (lastHost != host && lastHost.isNotEmpty) {
          _watchHistory.clear();
        }
        await _prefs.setString('last_host', host);

        _isLoggedIn = true;
        _loading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Login error: $e');
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _currentAccount = null;
    api.setToken('');
    // Clear active account so auto-login doesn't kick in
    await _prefs.remove('active_account_id');
    // DON'T remove saved accounts — user can switch between them
    notifyListeners();
  }

  // ====== Watch History (服务端驱动) ======

  /// 从服务端获取继续观看列表（替换本地缓存）
  Future<void> fetchServerPlayList() async {
    try {
      final resp = await api.getPlayList();
      if (resp['code'] == 0 && resp['data'] != null) {
        final serverList = resp['data'] as List;
        final newList = <WatchRecord>[];
        for (final item in serverList) {
          final guid = item['itemId'] ?? item['guid'] ?? '';
          if (guid.isEmpty) continue;
          final name = item['name'] ?? item['title'] ?? '';
          final poster = item['poster'] ?? '';
          final position = ((item['position'] ?? 0) as num).toInt();
          final duration = ((item['duration'] ?? 0) as num).toInt();
          final lastPlayTime = ((item['lastPlayTime'] ?? 0) as num).toInt();
          if (duration <= 0) continue;
          newList.add(WatchRecord(
            guid: guid,
            title: name,
            poster: poster,
            ts: position,
            duration: duration,
            updatedAt: lastPlayTime > 0 ? lastPlayTime * 1000 : DateTime.now().millisecondsSinceEpoch,
          ));
        }
        newList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        _watchHistory = newList;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchServerPlayList error: $e');
    }
  }

  /// 更新内存中的观看记录（用于UI即时刷新，不持久化）
  void addWatchRecord(WatchRecord record) {
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _watchHistory.removeWhere((r) => r.dedupKey == record.dedupKey);
    _watchHistory.insert(0, record);
    if (_watchHistory.length > 100) _watchHistory = _watchHistory.sublist(0, 100);
    notifyListeners();
  }

  // ====== Settings ======

  String get decoderMode => _prefs.getString('decoder_mode') ?? 'hardware';
  set decoderMode(String v) { _prefs.setString('decoder_mode', v); notifyListeners(); }

  int get seekStep => _prefs.getInt('seek_step') ?? 10;
  set seekStep(int v) { _prefs.setInt('seek_step', v); notifyListeners(); }

  bool get danmuOn => _prefs.getBool('danmu_on') ?? true;
  set danmuOn(bool v) { _prefs.setBool('danmu_on', v); notifyListeners(); }

  double get danmuOpacity => _prefs.getDouble('danmu_opacity') ?? 0.85;
  set danmuOpacity(double v) { _prefs.setDouble('danmu_opacity', v); notifyListeners(); }

  double get danmuFontSize => _prefs.getDouble('danmu_fontsize') ?? 22.0;
  set danmuFontSize(double v) { _prefs.setDouble('danmu_fontsize', v); notifyListeners(); }

  int get danmuArea => _prefs.getInt('danmu_area') ?? 35;
  set danmuArea(int v) { _prefs.setInt('danmu_area', v); notifyListeners(); }

  double get danmuSpeed => _prefs.getDouble('danmu_speed') ?? 1.0;
  set danmuSpeed(double v) { _prefs.setDouble('danmu_speed', v); notifyListeners(); }

  bool get danmuOutline => _prefs.getBool('danmu_outline') ?? true;
  set danmuOutline(bool v) { _prefs.setBool('danmu_outline', v); notifyListeners(); }

  int get danmuDensity => _prefs.getInt('danmu_density') ?? 100;
  set danmuDensity(int v) { _prefs.setInt('danmu_density', v); notifyListeners(); }

  bool get danmuScroll => _prefs.getBool('danmu_scroll') ?? true;
  set danmuScroll(bool v) { _prefs.setBool('danmu_scroll', v); notifyListeners(); }

  bool get danmuTop => _prefs.getBool('danmu_top') ?? true;
  set danmuTop(bool v) { _prefs.setBool('danmu_top', v); notifyListeners(); }

  bool get danmuBottom => _prefs.getBool('danmu_bottom') ?? true;
  set danmuBottom(bool v) { _prefs.setBool('danmu_bottom', v); notifyListeners(); }

  bool get danmuAntiOverlap => _prefs.getBool('danmu_anti_overlap') ?? false;
  set danmuAntiOverlap(bool v) { _prefs.setBool('danmu_anti_overlap', v); notifyListeners(); }

  bool get danmuMergeDuplicates => _prefs.getBool('danmu_merge_dup') ?? false;
  set danmuMergeDuplicates(bool v) { _prefs.setBool('danmu_merge_dup', v); notifyListeners(); }

  // ====== 字幕样式 (MPV) ======

  double get subtitleSize => _prefs.getDouble('subtitle_size') ?? 22.0;
  set subtitleSize(double v) { _prefs.setDouble('subtitle_size', v); notifyListeners(); }

  double get subtitleOutline => _prefs.getDouble('subtitle_outline') ?? 1.5;
  set subtitleOutline(double v) { _prefs.setDouble('subtitle_outline', v); notifyListeners(); }

  bool get subtitleBackground => _prefs.getBool('subtitle_background') ?? false;
  set subtitleBackground(bool v) { _prefs.setBool('subtitle_background', v); notifyListeners(); }

  int get subtitleColorValue => _prefs.getInt('subtitle_color') ?? 0xFFFFFFFF;
  set subtitleColorValue(int v) { _prefs.setInt('subtitle_color', v); notifyListeners(); }

  // ====== 弹幕服务器（独立于账号，app级存储） ======

  String get danmuUrl {
    final saved = _prefs.getString('danmu_url') ?? '';
    if (saved.isNotEmpty) return saved;
    return ''; // 不再自动派生，让用户自己设置
  }

  set danmuUrl(String v) { _prefs.setString('danmu_url', v); notifyListeners(); }

  // ====== Player Engine ======

  /// 'exo' or 'mpv'. Default: 'mpv' on all platforms.
  String get playerEngine => _prefs.getString('player_engine') ?? 'mpv';
  set playerEngine(String v) { _prefs.setString('player_engine', v); notifyListeners(); }
}
