import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';
import '../utils/theme.dart';

/// 进度条上方的弹幕密度折线图（点击可 seek）
class DanmuHeatmap extends StatelessWidget {
  final List<DanmuComment> comments;
  final Duration duration;
  final ValueChanged<double>? onSeekTap;

  const DanmuHeatmap({
    super.key,
    required this.comments,
    required this.duration,
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
            height: 18,
            child: CustomPaint(
              size: Size(constraints.maxWidth, 18),
              painter: _LineHeatmapPainter(bins: bins),
            ),
          ),
        );
      },
    );
  }
}

class _LineHeatmapPainter extends CustomPainter {
  final List<double> bins;

  _LineHeatmapPainter({required this.bins});

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    final stepX = size.width / (bins.length - 1).clamp(1, bins.length);
    final path = Path();
    for (var i = 0; i < bins.length; i++) {
      final x = i * stepX;
      final y = size.height - (bins[i] * size.height * 0.88).clamp(1.0, size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FnTheme.danmuGreen.withOpacity(0.35),
            FnTheme.danmuGreen.withOpacity(0.04),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = FnTheme.danmuGreen.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineHeatmapPainter old) => old.bins != bins;
}
