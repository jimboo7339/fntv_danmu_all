import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/app_release_info.dart';
import '../models/update_mirror.dart';

class UpdateCheckResult {
  final AppReleaseInfo? release;
  final bool hasUpdate;
  final String currentVersion;
  final String? error;

  const UpdateCheckResult({
    this.release,
    required this.hasUpdate,
    required this.currentVersion,
    this.error,
  });
}

class UpdateService {
  static const _apkPrefix = 'FNTV_All_';
  static const _userAgent = 'FNTV-Update/1.0';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': _userAgent, 'Accept': 'application/vnd.github+json'},
  ));

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<UpdateCheckResult> checkForUpdate(String currentVersion) async {
    if (!isSupported) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVersion,
        error: '当前仅支持 Android 客户端检查更新',
      );
    }

    Object? lastError;
    for (final mirror in UpdateMirror.mirrors) {
      try {
        final release = await _fetchLatestRelease(mirror);
        if (release == null) continue;
        final hasUpdate = _isNewer(currentVersion, release.tagName);
        return UpdateCheckResult(
          release: release,
          hasUpdate: hasUpdate,
          currentVersion: currentVersion,
        );
      } catch (e) {
        lastError = e;
        debugPrint('Update check via ${mirror.label} failed: $e');
      }
    }

    return UpdateCheckResult(
      hasUpdate: false,
      currentVersion: currentVersion,
      error: '无法获取版本信息，请切换网络后重试${lastError != null ? '\n$lastError' : ''}',
    );
  }

  Future<AppReleaseInfo?> _fetchLatestRelease(UpdateMirror mirror) async {
    final url = mirror.wrap(UpdateMirror.releasesLatestApi);
    final resp = await _dio.get<Map<String, dynamic>>(url);
    final data = resp.data;
    if (data == null) return null;

    final tag = data['tag_name']?.toString() ?? '';
    if (tag.isEmpty) return null;

    final assets = data['assets'];
    if (assets is! List) return null;

    Map<String, dynamic>? apkAsset;
    for (final item in assets) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (name.endsWith('.apk') && name.startsWith(_apkPrefix)) {
        apkAsset = Map<String, dynamic>.from(item);
        break;
      }
    }
    if (apkAsset == null) {
      for (final item in assets) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        if (name.endsWith('.apk')) {
          apkAsset = Map<String, dynamic>.from(item);
          break;
        }
      }
    }
    if (apkAsset == null) return null;

    final downloadUrl = apkAsset['browser_download_url']?.toString() ?? '';
    if (downloadUrl.isEmpty) return null;

    return AppReleaseInfo(
      tagName: tag,
      name: data['name']?.toString() ?? tag,
      body: data['body']?.toString() ?? '',
      apkUrl: downloadUrl,
      apkFileName: apkAsset['name']?.toString() ?? 'update.apk',
      apkSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> downloadApk({
    required AppReleaseInfo release,
    required UpdateMirror mirror,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/${release.apkFileName}';
    final file = File(savePath);
    if (await file.exists()) {
      await file.delete();
    }

    final url = mirror.wrap(release.apkUrl);
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        headers: const {'User-Agent': _userAgent},
        receiveTimeout: const Duration(minutes: 30),
      ),
    );
    return savePath;
  }

  static bool _isNewer(String current, String latestTag) {
    final c = _parseVersion(current);
    final l = _parseVersion(latestTag.replaceFirst(RegExp(r'^v'), ''));
    for (var i = 0; i < 3; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    final cleaned = v.replaceFirst(RegExp(r'^v'), '');
    final parts = cleaned.split('.');
    int part(int i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0;
    return [part(0), part(1), part(2)];
  }
}
