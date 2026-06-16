import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_record.dart';
import '../models/mpv_player_settings.dart';
import '../services/api_client.dart';
import '../utils/secure_storage.dart';
import '../utils/log_buffer.dart';

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
    this.pass = '',
    this.token = '',
    String? label,
  }) : label = label ?? '$user@${_shortHost(host)}';

  static String _shortHost(String host) {
    var h = host.replaceAll(RegExp(r'^https?://'), '');
    h = h.replaceAll(RegExp(r':\d+$'), '');
    return h;
  }

  /// 持久化元数据（不含 token / 密码）
  Map<String, dynamic> toJson() => {
    'id': id, 'host': host, 'user': user, 'label': label,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    id: j['id'] ?? '', host: j['host'] ?? '', user: j['user'] ?? '',
    label: j['label'],
  );

  SavedAccount copyWith({String? pass, String? token}) => SavedAccount(
    id: id, host: host, user: user, pass: pass ?? this.pass,
    token: token ?? this.token, label: label,
  );
}

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();
  late SharedPreferences _prefs;
  bool _isLoggedIn = false;
  bool _loading = false;
  bool _initDone = false;
  bool _sessionRestoring = false;
  bool _restoreCancelled = false;
  List<WatchRecord> _watchHistory = [];
  List<SavedAccount> _accounts = [];
  SavedAccount? _currentAccount;
  Map<String, Map<String, dynamic>>? _danmuSourceCacheMem;
  int _sessionVersion = 0;
  int _goHomeToken = 0;

  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  bool get initDone => _initDone;
  int get sessionVersion => _sessionVersion;
  int get goHomeToken => _goHomeToken;
  bool get sessionRestoring => _sessionRestoring;
  List<WatchRecord> get watchHistory => _watchHistory;
  List<SavedAccount> get accounts => _accounts;
  SavedAccount? get currentAccount => _currentAccount;
  String get serverHost => _currentAccount?.host ?? '';

  /// 账号切换 / 登录成功后递增，用于重建首页与媒体库
  void _bumpSession() {
    _sessionVersion++;
    _danmuSourceCacheMem = null;
    notifyListeners();
  }

  /// 通知主界面跳转到首页 Tab
  void requestGoHome() {
    _goHomeToken++;
    notifyListeners();
  }

  void _onAccountSessionChanged() {
    _bumpSession();
    requestGoHome();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    LogBuffer.instance.enabled = _prefs.getBool('debug_log_enabled') ?? false;
    await _migrateMpvDefaults();
    await _migrateLegacySecrets();
    await _loadAccountsWithSecrets();

    final activeId = _prefs.getString('active_account_id') ?? '';
    final hasActiveAccount = activeId.isNotEmpty &&
        _accounts.any((a) => a.id == activeId);
    _sessionRestoring = hasActiveAccount;

    _initDone = true;
    notifyListeners();

    if (hasActiveAccount) {
      await _tryRestoreSession();
      if (!_restoreCancelled) {
        _sessionRestoring = false;
        notifyListeners();
      }
    }
  }

  /// 启动自动登录等待期间，用户主动切换账号。
  void cancelSessionRestore() {
    if (!_sessionRestoring) return;
    _restoreCancelled = true;
    _sessionRestoring = false;
    _isLoggedIn = false;
    _currentAccount = null;
    _loading = false;
    api.setToken('');
    notifyListeners();
  }

  Future<void> _tryRestoreSession() async {
    if (_restoreCancelled) return;

    final activeId = _prefs.getString('active_account_id') ?? '';
    if (activeId.isEmpty) return;

    final matches = _accounts.where((a) => a.id == activeId).toList();
    if (matches.isEmpty) return;
    final acc = matches.first;

    if (acc.token.isNotEmpty) {
      api.updateBaseUrl(acc.host);
      api.setToken(acc.token);
      try {
        final resp = await api.getUserInfo()
            .timeout(const Duration(seconds: 6));
        if (_restoreCancelled) return;
        if (resp['code'] == 0) {
          _currentAccount = acc;
          _isLoggedIn = true;
          return;
        }
      } catch (e) {
        debugPrint('restore session token check failed: $e');
      }
    }

    if (_restoreCancelled) return;

    if (acc.pass.isNotEmpty) {
      bool ok = false;
      try {
        ok = await login(acc.host, acc.user, acc.pass, true)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('restore session auto login failed: $e');
      }
      if (_restoreCancelled) return;
      if (!ok) {
        _isLoggedIn = false;
        _currentAccount = null;
      }
      return;
    }

    _isLoggedIn = false;
    _currentAccount = null;
  }

  Future<void> _migrateLegacySecrets() async {
    final json = _prefs.getString('accounts');
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List;
      final secure = SecureStore.instance;
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final token = item['token']?.toString() ?? '';
        final pass = item['pass']?.toString() ?? '';
        if (token.isNotEmpty) await secure.writeToken(id, token);
        if (pass.isNotEmpty) await secure.writePass(id, pass);
      }
    } catch (_) {}
  }

  Future<void> _loadAccountsWithSecrets() async {
    final json = _prefs.getString('accounts');
    if (json == null) {
      _accounts = [];
      return;
    }
    try {
      final list = jsonDecode(json) as List;
      final secure = SecureStore.instance;
      final loaded = <SavedAccount>[];
      for (final item in list) {
        if (item is! Map) continue;
        var acc = SavedAccount.fromJson(Map<String, dynamic>.from(item));
        var token = await secure.readToken(acc.id) ?? '';
        var pass = await secure.readPass(acc.id) ?? '';
        // secure storage 读失败时回退旧版明文字段
        if (token.isEmpty) token = item['token']?.toString() ?? '';
        if (pass.isEmpty) pass = item['pass']?.toString() ?? '';
        acc = acc.copyWith(token: token, pass: pass);
        loaded.add(acc);
      }
      _accounts = loaded;
    } catch (_) {
      _accounts = [];
    }
  }

  void _saveAccounts() {
    _prefs.setString('accounts', jsonEncode(_accounts.map((a) => a.toJson()).toList()));
  }

  Future<void> _persistAccountSecrets(SavedAccount account, {bool rememberPass = false}) async {
    final secure = SecureStore.instance;
    await secure.writeToken(account.id, account.token);
    if (rememberPass && account.pass.isNotEmpty) {
      await secure.writePass(account.id, account.pass);
    } else {
      await secure.deletePass(account.id);
    }
  }

  Future<bool> switchAccount(String accountId) async {
    final acc = _accounts.where((a) => a.id == accountId).toList();
    if (acc.isEmpty) return false;
    final account = acc.first;

    if (account.token.isNotEmpty) {
      api.updateBaseUrl(account.host);
      api.setToken(account.token);
      try {
        final resp = await api.getUserInfo();
        if (resp['code'] == 0) {
          _currentAccount = account;
          await _prefs.setString('active_account_id', account.id);
          _watchHistory.clear();
          _isLoggedIn = true;
          _onAccountSessionChanged();
          return true;
        }
      } catch (e) {
        debugPrint('switchAccount token check failed: $e');
      }
      if (account.pass.isNotEmpty) {
        return login(account.host, account.user, account.pass, true);
      }
      return false;
    }

    if (account.pass.isNotEmpty) {
      return login(account.host, account.user, account.pass, true);
    }
    return false;
  }

  void removeAccount(String accountId) {
    _accounts.removeWhere((a) => a.id == accountId);
    _saveAccounts();
    SecureStore.instance.deleteAccount(accountId);
    notifyListeners();
  }

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

        final accId = '$host|$user';
        final account = SavedAccount(
          id: accId, host: host, user: user,
          pass: remember ? pass : '', token: token,
        );

        _accounts.removeWhere((a) => a.id == accId);
        _accounts.insert(0, account);
        _saveAccounts();
        await _persistAccountSecrets(account, rememberPass: remember);

        await _prefs.setString('active_account_id', accId);
        await _prefs.setBool('remember', remember);

        final lastHost = _prefs.getString('last_host') ?? '';
        if (lastHost != host && lastHost.isNotEmpty) {
          _watchHistory.clear();
        }
        await _prefs.setString('last_host', host);

        if (_restoreCancelled) {
          _loading = false;
          notifyListeners();
          return false;
        }

        _currentAccount = account;
        _isLoggedIn = true;
        _loading = false;
        _onAccountSessionChanged();
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
    await _prefs.remove('active_account_id');
    notifyListeners();
  }

  Future<void> fetchServerPlayList() async {
    try {
      final resp = await api.getPlayList();
      if (resp['code'] == 0 && resp['data'] != null) {
        final serverList = resp['data'] as List;
        final newList = <WatchRecord>[];
        for (final item in serverList) {
          final guid = item['guid'] ?? item['itemId'] ?? '';
          if (guid.isEmpty) continue;
          final name = item['title'] ?? item['name'] ?? '';
          final tvTitle = item['tv_title'] ?? '';
          final poster = item['poster'] ?? '';
          final ts = ((item['ts'] ?? item['position'] ?? 0) as num).toInt();
          final duration = ((item['duration'] ?? 0) as num).toInt();
          final episodeNumber = item['episode_number'] ?? 0;
          final parentGuid = item['parent_guid'] ?? '';
          if (duration <= 0) continue;
          newList.add(WatchRecord(
            guid: guid,
            title: name,
            tvTitle: tvTitle.isNotEmpty ? tvTitle : null,
            episodeNumber: episodeNumber,
            poster: poster,
            parentGuid: parentGuid.isNotEmpty ? parentGuid : null,
            ts: ts,
            duration: duration,
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

  void addWatchRecord(WatchRecord record) {
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _watchHistory.removeWhere((r) => r.dedupKey == record.dedupKey);
    _watchHistory.insert(0, record);
    if (_watchHistory.length > 100) _watchHistory = _watchHistory.sublist(0, 100);
    notifyListeners();
  }

  Future<void> _migrateMpvDefaults() async {
    const version = 3;
    if ((_prefs.getInt('mpv_defaults_version') ?? 0) >= version) return;
    final sync = _prefs.getString('mpv_video_sync');
    if (sync == null || sync == 'display-resample') {
      await _prefs.setString('mpv_video_sync', 'audio');
    }
    if (!kIsWeb && Platform.isAndroid) {
      final hw = _prefs.getString('mpv_hwdec');
      if (hw == null || hw == 'auto-copy' || hw == 'auto') {
        await _prefs.setString('mpv_hwdec', 'mediacodec-copy');
      }
    }
    await _prefs.setInt('mpv_defaults_version', version);
  }

  String get decoderMode => mpvHwdec == 'no' ? 'software' : 'hardware';
  set decoderMode(String v) { mpvHwdec = v == 'software' ? 'no' : 'mediacodec-copy'; }

  String get mpvHwdec {
    final saved = _prefs.getString('mpv_hwdec');
    if (saved != null) return saved;
    if (!kIsWeb && Platform.isAndroid) return 'mediacodec-copy';
    return _prefs.getString('decoder_mode') == 'software' ? 'no' : 'auto-copy';
  }
  set mpvHwdec(String v) { _prefs.setString('mpv_hwdec', v); notifyListeners(); }

  String get mpvVo => _prefs.getString('mpv_vo') ?? 'gpu';
  set mpvVo(String v) { _prefs.setString('mpv_vo', v); notifyListeners(); }

  String get mpvVideoSync => _prefs.getString('mpv_video_sync') ?? 'audio';
  set mpvVideoSync(String v) { _prefs.setString('mpv_video_sync', v); notifyListeners(); }

  int get mpvBufferMb => _prefs.getInt('mpv_buffer_mb') ?? 192;
  set mpvBufferMb(int v) { _prefs.setInt('mpv_buffer_mb', v.clamp(50, 512)); notifyListeners(); }

  int get mpvCacheSecs => _prefs.getInt('mpv_cache_secs') ?? 25;
  set mpvCacheSecs(int v) { _prefs.setInt('mpv_cache_secs', v.clamp(10, 300)); notifyListeners(); }

  bool get mpvInterpolation => _prefs.getBool('mpv_interpolation') ?? false;
  set mpvInterpolation(bool v) { _prefs.setBool('mpv_interpolation', v); notifyListeners(); }

  MpvPlayerSettings get mpvSettings => MpvPlayerSettings(
        hwdec: mpvHwdec,
        vo: mpvVo,
        videoSync: mpvVideoSync,
        bufferMb: mpvBufferMb,
        cacheSecs: mpvCacheSecs,
        interpolation: mpvInterpolation,
      );

  int get seekStep => _prefs.getInt('seek_step') ?? 10;
  set seekStep(int v) { _prefs.setInt('seek_step', v); notifyListeners(); }

  bool get showNetworkSpeed => _prefs.getBool('show_network_speed') ?? false;
  set showNetworkSpeed(bool v) { _prefs.setBool('show_network_speed', v); notifyListeners(); }

  bool get debugLogEnabled => _prefs.getBool('debug_log_enabled') ?? false;
  set debugLogEnabled(bool v) {
    _prefs.setBool('debug_log_enabled', v);
    LogBuffer.instance.enabled = v;
    notifyListeners();
  }

  bool get danmuOn => _prefs.getBool('danmu_on') ?? true;
  set danmuOn(bool v) { _prefs.setBool('danmu_on', v); notifyListeners(); }

  double get danmuOpacity => _prefs.getDouble('danmu_opacity') ?? 0.85;
  set danmuOpacity(double v) { _prefs.setDouble('danmu_opacity', v); notifyListeners(); }

  double get danmuFontSize => _prefs.getDouble('danmu_fontsize') ?? 22.0;
  set danmuFontSize(double v) { _prefs.setDouble('danmu_fontsize', v); notifyListeners(); }

  int get danmuArea => _prefs.getInt('danmu_area') ?? 35;
  set danmuArea(int v) { _prefs.setInt('danmu_area', v); notifyListeners(); }

  double get danmuSpeed => _prefs.getDouble('danmu_speed') ?? 0.6;
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

  double get danmuTopMargin => _prefs.getDouble('danmu_top_margin') ?? 0.0;
  set danmuTopMargin(double v) { _prefs.setDouble('danmu_top_margin', v); notifyListeners(); }

  double get subtitleSize => _prefs.getDouble('subtitle_size') ?? 22.0;
  set subtitleSize(double v) { _prefs.setDouble('subtitle_size', v); notifyListeners(); }

  double get subtitleOutline => _prefs.getDouble('subtitle_outline') ?? 1.5;
  set subtitleOutline(double v) { _prefs.setDouble('subtitle_outline', v); notifyListeners(); }

  bool get subtitleBackground => _prefs.getBool('subtitle_background') ?? false;
  set subtitleBackground(bool v) { _prefs.setBool('subtitle_background', v); notifyListeners(); }

  int get subtitleColorValue => _prefs.getInt('subtitle_color') ?? 0xFFFFFFFF;
  set subtitleColorValue(int v) { _prefs.setInt('subtitle_color', v); notifyListeners(); }

  double get subtitleWeight => _prefs.getDouble('subtitle_weight') ?? 600;
  set subtitleWeight(double v) { _prefs.setDouble('subtitle_weight', v); notifyListeners(); }

  double get subtitleBottomMargin => _prefs.getDouble('subtitle_bottom_margin') ?? 0.0;
  set subtitleBottomMargin(double v) { _prefs.setDouble('subtitle_bottom_margin', v); notifyListeners(); }

  String get danmuUrl {
    final saved = _prefs.getString('danmu_url') ?? '';
    if (saved.isNotEmpty) return saved;
    return '';
  }

  set danmuUrl(String v) { _prefs.setString('danmu_url', v); notifyListeners(); }

  Map<String, Map<String, dynamic>> get danmuSourceCache {
    if (_danmuSourceCacheMem != null) return _danmuSourceCacheMem!;
    final raw = _prefs.getString('danmu_source_cache');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _danmuSourceCacheMem = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
        return _danmuSourceCacheMem!;
      } catch (_) {}
    }
    _danmuSourceCacheMem = {};
    return _danmuSourceCacheMem!;
  }

  set danmuSourceCache(Map<String, Map<String, dynamic>> v) {
    _danmuSourceCacheMem = v;
    _prefs.setString('danmu_source_cache', jsonEncode(v));
    notifyListeners();
  }

  Map<String, dynamic>? getDanmuSource(String showName) => danmuSourceCache[showName];

  void setDanmuSource(String showName, Map<String, dynamic> data) {
    final cache = Map<String, Map<String, dynamic>>.from(danmuSourceCache);
    cache[showName] = data;
    danmuSourceCache = cache;
  }

  double get danmuLongPressSpeed => _prefs.getDouble('danmu_lp_speed') ?? 2.0;
  set danmuLongPressSpeed(double v) { _prefs.setDouble('danmu_lp_speed', v); notifyListeners(); }
}
