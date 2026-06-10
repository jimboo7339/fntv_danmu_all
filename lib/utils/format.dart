String formatDuration(int seconds) {
  if (seconds <= 0) return "0:00";
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return "$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
  return "$m:${s.toString().padLeft(2, '0')}";
}

String formatBitrate(int bps) {
  if (bps >= 1000000) return "${(bps / 1000000).toStringAsFixed(1)} Mbps";
  return "${(bps / 1000).toStringAsFixed(0)} kbps";
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return "?";
  if (bytes >= 1073741824) return "${(bytes / 1073741824).toStringAsFixed(1)} GB";
  if (bytes >= 1048576) return "${(bytes / 1048576).toStringAsFixed(0)} MB";
  return "${(bytes ~/ 1024)} KB";
}
