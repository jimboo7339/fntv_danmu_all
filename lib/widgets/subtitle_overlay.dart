import 'package:flutter/material.dart';
import '../models/subtitle_data.dart';

/// 软件字幕渲染覆盖层（ExoPlayer 等不支持内嵌字幕时使用）
class SubtitleOverlay extends StatefulWidget {
  final SubtitleData? subtitleData;
  final Duration Function() getCurrentTime;
  final double fontSize;
  final double outline;
  final bool showBackground;
  final Color color;
  final FontWeight fontWeight;
  final double bottomMargin;

  const SubtitleOverlay({
    super.key,
    required this.subtitleData,
    required this.getCurrentTime,
    this.fontSize = 22,
    this.outline = 1.5,
    this.showBackground = false,
    this.color = Colors.white,
    this.fontWeight = FontWeight.w600,
    this.bottomMargin = 0,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickCtrl;
  SubtitleEntry? _currentEntry;

  @override
  void initState() {
    super.initState();
    _tickCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_onTick);
    _tickCtrl.repeat();
  }

  @override
  void dispose() {
    _tickCtrl.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted || widget.subtitleData == null) return;
    final entry = widget.subtitleData!.getEntryAt(widget.getCurrentTime());
    if (entry?.index != _currentEntry?.index || entry?.text != _currentEntry?.text) {
      setState(() => _currentEntry = entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _currentEntry;
    if (entry == null) return const SizedBox.shrink();

    return Positioned(
      left: 20,
      right: 20,
      bottom: 40 + widget.bottomMargin,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: widget.showBackground
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : null,
            decoration: widget.showBackground
                ? BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: widget.fontWeight,
                color: widget.color,
                shadows: [
                  Shadow(blurRadius: widget.outline, color: Colors.black),
                  Shadow(blurRadius: widget.outline, color: Colors.black),
                  Shadow(blurRadius: widget.outline, color: Colors.black),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
