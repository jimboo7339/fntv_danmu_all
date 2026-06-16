class AppReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final String apkUrl;
  final String apkFileName;
  final int apkSize;

  const AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkFileName,
    required this.apkSize,
  });

  String get versionLabel =>
      tagName.startsWith('v') ? tagName : 'v$tagName';

  String get apkSizeText {
    if (apkSize <= 0) return '';
    final mb = apkSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
