import 'package:flutter/material.dart';
import '../models/subtitle_data.dart';

/// 软件字幕渲染覆盖层
/// 配合 ExoPlayer 等不支持内嵌字幕的播放器使用
class SubtitleOverlay extends StatelessWidget {
  final SubtitleData? subtitleData;
  final Duration currentPosition;
  final double fontSize;
  final double outline;
  final bool showBackground;
  final Color color;
  final FontWeight fontWeight;
  final double bottomMargin;

  const SubtitleOverlay({
    super.key,
    required this.subtitleData,
    required this.currentPosition,
    this.fontSize = 22,
    this.outline = 1.5,
    this.showBackground = false,
    this.color = Colors.white,
    this.fontWeight = FontWeight.w600,
    this.bottomMargin = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (subtitleData == null || subtitleData!.isEmpty) {
      return const SizedBox.shrink();
    }

    final entry = subtitleData!.getEntryAt(currentPosition);
    if (entry == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 20,
      right: 20,
      bottom: 40 + bottomMargin,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: showBackground
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : null,
            decoration: showBackground
                ? BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
                shadows: [
                  Shadow(blurRadius: outline, color: Colors.black),
                  Shadow(blurRadius: outline, color: Colors.black),
                  Shadow(blurRadius: outline, color: Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
