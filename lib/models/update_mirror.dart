/// GitHub Release 下载镜像 / API 加速源
class UpdateMirror {
  final String id;
  final String label;
  final String description;
  /// 为完整 URL 添加前缀；null 表示直连 GitHub
  final String? urlPrefix;

  const UpdateMirror({
    required this.id,
    required this.label,
    required this.description,
    this.urlPrefix,
  });

  String wrap(String url) {
    if (urlPrefix == null || urlPrefix!.isEmpty) return url;
    return '$urlPrefix$url';
  }

  static const repoOwner = 'jimboo7339';
  static const repoName = 'fntv_danmu_all';

  static String get releasesLatestApi =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// 常用 GitHub 加速 / 镜像（国内网络可切换）
  static const List<UpdateMirror> mirrors = [
    UpdateMirror(
      id: 'official',
      label: 'GitHub 官方',
      description: '直连 GitHub，海外或网络良好时推荐',
    ),
    UpdateMirror(
      id: 'ghproxy',
      label: '镜像加速 1 (ghproxy.net)',
      description: 'ghproxy.net 加速',
      urlPrefix: 'https://ghproxy.net/',
    ),
    UpdateMirror(
      id: 'ghproxy_com',
      label: '镜像加速 2 (ghproxy.com)',
      description: 'ghproxy.com 加速',
      urlPrefix: 'https://ghproxy.com/',
    ),
    UpdateMirror(
      id: 'mirror_ghproxy',
      label: '镜像加速 3 (mirror.ghproxy.com)',
      description: 'mirror.ghproxy.com 加速',
      urlPrefix: 'https://mirror.ghproxy.com/',
    ),
    UpdateMirror(
      id: 'ghps',
      label: '镜像加速 4 (ghps.cc)',
      description: 'ghps.cc 加速',
      urlPrefix: 'https://ghps.cc/',
    ),
    UpdateMirror(
      id: 'moeyy',
      label: '镜像加速 5 (github.moeyy.xyz)',
      description: 'moeyy 镜像加速',
      urlPrefix: 'https://github.moeyy.xyz/',
    ),
  ];
}
