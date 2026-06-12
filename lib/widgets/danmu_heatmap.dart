import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';
import '../utils/theme.dart';

/// 进度条上方的弹幕密度热力图。
class DanmuHeatmap extends StatelessWidget {
  final List<DanmuComment> comments;
  final Duration duration;
  final Duration position;
  final ValueChanged<double>? onSeekTap;

  const DanmuHeatmap({
    super.key,
    required this.comments,
    required this.duration,
    required this.position,
    this.onSeekTap,
  });

  static const int _bins = 120;

  List<double> _buildBins() {
    final bins = List<double>.filled(_bins, 0);
    if (comments.isEmpty) return bins;
    final durSec = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
    for (final c in comments) {
      if (c.time < 0) continue;
      final idx = ((c.time / durSec) * _bins).floor().clamp(0, _bins - 1);
      bins[idx] += 1;
    }
    final max = bins.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return bins;
    return bins.map((v) => (v / max).clamp(0.0, 1.0)).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty || duration.inSeconds <= 0) {
      return const SizedBox(height: 4);
    }
    final bins = _buildBins();
    final playRatio = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: onSeekTap == null
              ? null
              : (d) {
                  final ratio = (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                  onSeekTap!(ratio);
                },
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              size: Size(constraints.maxWidth, 22),
              painter: _HeatmapPainter(
                bins: bins,
                playRatio: playRatio,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<double> bins;
  final double playRatio;

  _HeatmapPainter({required this.bins, required this.playRatio});

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / bins.length;
    for (var i = 0; i < bins.length; i++) {
      final h = (bins[i] * size.height * 0.92).clamp(1.0, size.height);
      final x = i * barW;
      final opacity = (0.15 + bins[i] * 0.85).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = FnTheme.danmuGreen.withOpacity(opacity)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.5, size.height - h, barW - 1, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }

    final playX = playRatio * size.width;
    canvas.drawLine(
      Offset(playX, 0),
      Offset(playX, size.height),
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.playRatio != playRatio || old.bins != bins;
}
