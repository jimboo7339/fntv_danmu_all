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
      id: 'ghfast',
      label: '镜像加速 1 (ghfast.top)',
      description: 'ghfast.top 代理加速',
      urlPrefix: 'https://ghfast.top/',
    ),
    UpdateMirror(
      id: 'gh_proxy',
      label: '镜像加速 2 (gh-proxy.com)',
      description: 'gh-proxy.com 加速',
      urlPrefix: 'https://gh-proxy.com/',
    ),
    UpdateMirror(
      id: 'akams',
      label: '镜像加速 3 (github.akams.cn)',
      description: '支持 API / Releases 加速',
      urlPrefix: 'https://github.akams.cn/',
    ),
    UpdateMirror(
      id: 'homeboyc',
      label: '镜像加速 4 (ghproxy.homeboyc.cn)',
      description: '大文件 Release 下载稳定',
      urlPrefix: 'https://ghproxy.homeboyc.cn/',
    ),
    UpdateMirror(
      id: 'moeyy',
      label: '镜像加速 5 (moeyy.cn)',
      description: 'moeyy.cn/gh-proxy 加速',
      urlPrefix: 'https://moeyy.cn/gh-proxy/',
    ),
    UpdateMirror(
      id: 'ghp_ci',
      label: '镜像加速 6 (ghp.ci)',
      description: 'ghp.ci 文件加速',
      urlPrefix: 'https://ghp.ci/',
    ),
    UpdateMirror(
      id: 'ghproxy_net',
      label: '镜像加速 7 (ghproxy.net)',
      description: 'ghproxy.net 加速',
      urlPrefix: 'https://ghproxy.net/',
    ),
  ];
}
