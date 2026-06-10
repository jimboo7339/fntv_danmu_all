import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/watch_record.dart';
import '../services/api_client.dart';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();
  late SharedPreferences _prefs;
  bool _isLoggedIn = false;
  bool _loading = false;
  List<WatchRecord> _watchHistory = [];

  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  List<WatchRecord> get watchHistory => _watchHistory;
  String get serverHost => _prefs.getString('host') ?? '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final host = _prefs.getString('host') ?? '';
    final token = _prefs.getString('token') ?? '';
    final remember = _prefs.getBool('remember') ?? false;
    if (remember && host.isNotEmpty && token.isNotEmpty) {
      api.updateBaseUrl(host);
      api.setToken(token);
      _isLoggedIn = true;
    }
    _loadWatchHistory();
  }

  Future<bool> login(String host, String user, String pass, bool remember) async {
    _loading = true;
    notifyListeners();
    try {
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        host = 'http://\$host';
      }
      api.updateBaseUrl(host);
      final resp = await api.login(user, pass);
      if (resp['code'] == 0) {
        final token = resp['data']['token'] as String;
        api.setToken(token);
        await _prefs.setString('host', host);
        await _prefs.setString('user', user);
        await _prefs.setString('token', token);
        await _prefs.setBool('remember', remember);
        if (remember) {
          await _prefs.setString('pass', pass);
        } else {
          await _prefs.remove('pass');
        }
        // Clear history on server change
        final lastHost = _prefs.getString('last_host') ?? '';
        if (lastHost != host && lastHost.isNotEmpty) {
          await _prefs.remove('watch_history');
          _watchHistory.clear();
        }
        await _prefs.setString('last_host', host);
        _isLoggedIn = true;
        _loading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Login error: \$e');
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    await _prefs.remove('token');
    api.setToken('');
    notifyListeners();
  }

  // ====== Watch History ======

  void _loadWatchHistory() {
    final json = _prefs.getString('watch_history');
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        _watchHistory = list.map((e) => WatchRecord.fromJson(e)).toList();
        _watchHistory.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _watchHistory = [];
      }
    }
  }

  void addWatchRecord(WatchRecord record) {
    record.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _watchHistory.removeWhere((r) => r.dedupKey == record.dedupKey);
    _watchHistory.insert(0, record);
    if (_watchHistory.length > 100) _watchHistory = _watchHistory.sublist(0, 100);
    _saveWatchHistory();
    notifyListeners();
  }

  void _saveWatchHistory() {
    final json = jsonEncode(_watchHistory.map((r) => r.toJson()).toList());
    _prefs.setString('watch_history', json);
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

  String get danmuUrl {
    final saved = _prefs.getString('danmu_url') ?? '';
    if (saved.isNotEmpty) return saved;
    final host = serverHost.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/.*\$'), '').replaceAll(RegExp(r':\d+\$'), '');
    return 'http://\$host:9321';
  }

  set danmuUrl(String v) { _prefs.setString('danmu_url', v); notifyListeners(); }
}
