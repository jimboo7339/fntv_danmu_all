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
      id: 'gh_llkk',
      label: '镜像加速 1 (gh.llkk.cc)',
      description: 'gh.llkk.cc 代理加速',
      urlPrefix: 'https://gh.llkk.cc/',
    ),
    UpdateMirror(
      id: 'ghproxy_link',
      label: '镜像加速 2 (ghproxy.link)',
      description: 'ghproxy.link 加速',
      urlPrefix: 'https://ghproxy.link/',
    ),
    UpdateMirror(
      id: 'mirror_ghproxy',
      label: '镜像加速 3 (mirror.ghproxy.com)',
      description: 'mirror.ghproxy.com 加速',
      urlPrefix: 'https://mirror.ghproxy.com/',
    ),
    UpdateMirror(
      id: 'ghproxy_cc',
      label: '镜像加速 4 (ghproxy.cc)',
      description: 'ghproxy.cc 加速',
      urlPrefix: 'https://ghproxy.cc/',
    ),
    UpdateMirror(
      id: 'gh_proxy',
      label: '镜像加速 5 (gh-proxy.com)',
      description: 'gh-proxy.com 加速',
      urlPrefix: 'https://gh-proxy.com/',
    ),
    UpdateMirror(
      id: 'ghfast',
      label: '镜像加速 6 (ghfast.top)',
      description: 'ghfast.top 代理加速',
      urlPrefix: 'https://ghfast.top/',
    ),
    UpdateMirror(
      id: 'akams',
      label: '镜像加速 7 (github.akams.cn)',
      description: '支持 API / Releases 加速',
      urlPrefix: 'https://github.akams.cn/',
    ),
  ];
}
