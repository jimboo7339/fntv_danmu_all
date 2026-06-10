import 'dart:math';
import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';

class DanmuOverlay extends StatefulWidget {
  final List<DanmuComment> comments;
  final double currentTime;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;

  const DanmuOverlay({
    super.key,
    required this.comments,
    required this.currentTime,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
  });

  @override
  State<DanmuOverlay> createState() => _DanmuOverlayState();
}

class _DanmuOverlayState extends State<DanmuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  final List<_DanmuItem> _activeItems = [];
  int _nextIndex = 0;
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..addListener(_tick);
    _animCtrl.repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DanmuPainter(
          comments: widget.comments,
          currentTime: widget.currentTime,
          opacity: widget.opacity,
          fontSize: widget.fontSize,
          areaPercent: widget.areaPercent,
          showOutline: widget.showOutline,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DanmuItem {
  String text;
  double time;
  int color;
  int type;
  double x = 0, y = 0, speed = 0, tw = 0;
  double ttl = 5.0;
  _DanmuItem({required this.text, required this.time, this.color = 0xFFFFFFFF, this.type = 1});
}

class _DanmuPainter extends CustomPainter {
  final List<DanmuComment> comments;
  final double currentTime;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;

  static final Map<double, List<_DanmuItem>> _activeScroll = {};
  static final Map<double, List<_DanmuItem>> _activeStatic = {};
  static int _lastEmitMs = 0;

  _DanmuPainter({
    required this.comments,
    required this.currentTime,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (comments.isEmpty || size.width <= 0) return;

    final paint = Paint()..isAntiAlias = true;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final areaH = size.height * areaPercent / 100;
    final lnH = fontSize * 1.5;
    final maxRow = max(1, (areaH / lnH).floor());

    final curMs = currentTime;
    final curSec = curMs / 1000.0;
    final key = 0.0; // single instance key

    // Emit new danmu
    final active = _activeScroll.putIfAbsent(key, () => []);
    final staticActive = _activeStatic.putIfAbsent(key, () => []);

    // Clean expired
    active.removeWhere((a) => a.x + a.tw < -50);
    staticActive.removeWhere((a) => a.ttl <= 0);

    // Find and emit comments near current time
    for (int i = 0; i < comments.length; i++) {
      final c = comments[i];
      final diff = curSec - c.time;
      if (diff < -0.1) break; // sorted by time
      if (diff > 0.5) continue;
      if (diff < 0) continue;
      // Check if already emitted (by text+time match)
      final already = active.any((a) => a.text == c.text && (a.time - c.time).abs() < 0.1) ||
                      staticActive.any((a) => a.text == c.text && (a.time - c.time).abs() < 0.1);
      if (already) continue;

      if (c.type == 4 || c.type == 5) {
        // Static danmu
        final item = _DanmuItem(text: c.text, time: c.time, color: c.color, type: c.type);
        final tp = TextPainter(
          text: TextSpan(text: c.text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        item.tw = tp.width;
        item.x = (size.width - item.tw) / 2;
        if (c.type == 5) {
          item.y = lnH + staticActive.where((a) => a.type == 5).length * lnH;
        } else {
          item.y = size.height - lnH * 0.2 - staticActive.where((a) => a.type == 4).length * lnH;
        }
        staticActive.add(item);
      } else {
        // Scroll danmu
        final item = _DanmuItem(text: c.text, time: c.time, color: c.color, type: c.type);
        final tp = TextPainter(
          text: TextSpan(text: c.text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        item.tw = tp.width;
        item.speed = 200 + c.text.length * 4.0;
        item.x = size.width;
        // Find free row
        final len = max(1, c.text.length);
        for (int r = 0; r < maxRow; r++) {
          final rowY = lnH + r * lnH;
          bool blocked = false;
          for (final a in active) {
            if ((a.y - rowY).abs() < lnH * 0.5 && a.x + a.tw + 40 > size.width) {
              blocked = true;
              break;
            }
          }
          if (!blocked) { item.y = rowY; break; }
          if (r == maxRow - 1) item.y = -100; // no space, hide
        }
        if (item.y > 0) active.add(item);
      }
    }

    // Draw scroll danmu
    for (final a in active) {
      a.x -= a.speed * 0.016; // ~60fps
      _drawText(canvas, a.text, a.x, a.y, a.color, paint, textPainter);
    }

    // Draw static danmu
    for (final a in staticActive) {
      a.ttl -= 0.016;
      _drawText(canvas, a.text, a.x, a.y, a.color, paint, textPainter);
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, int color,
      Paint paint, TextPainter tp) {
    final c = Color(color);
    final alpha = (c.alpha * opacity).toInt().clamp(0, 255);
    final drawColor = c.withAlpha(alpha);

    if (showOutline) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black.withAlpha(alpha),
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(x, y));
    }

    tp.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: drawColor,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
