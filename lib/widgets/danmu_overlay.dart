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

class _DanmuOverlayState extends State<DanmuOverlay> {
  // Persistent state across rebuilds
  final List<_DanmuItem> _activeScroll = [];
  final List<_DanmuItem> _activeStatic = [];
  int _lastCommentCount = 0;
  double _lastPaintTime = 0;

  @override
  Widget build(BuildContext context) {
    // Clear active items when comments list changes (episode switch)
    if (widget.comments.length != _lastCommentCount) {
      _activeScroll.clear();
      _activeStatic.clear();
      _lastCommentCount = widget.comments.length;
    }

    return IgnorePointer(
      child: CustomPaint(
        painter: _DanmuPainter(
          comments: widget.comments,
          currentTime: widget.currentTime,
          opacity: widget.opacity,
          fontSize: widget.fontSize,
          areaPercent: widget.areaPercent,
          showOutline: widget.showOutline,
          activeScroll: _activeScroll,
          activeStatic: _activeStatic,
          lastPaintTime: _lastPaintTime,
          onPaintTimeUpdate: (t) => _lastPaintTime = t,
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
  final List<_DanmuItem> activeScroll;
  final List<_DanmuItem> activeStatic;
  final double lastPaintTime;
  final void Function(double) onPaintTimeUpdate;

  _DanmuPainter({
    required this.comments,
    required this.currentTime,
    required this.activeScroll,
    required this.activeStatic,
    required this.lastPaintTime,
    required this.onPaintTimeUpdate,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (comments.isEmpty || size.width <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final dt = lastPaintTime > 0 ? (now - lastPaintTime).clamp(0.001, 0.5) : 0.016;
    onPaintTimeUpdate(now);

    final paint = Paint()..isAntiAlias = true;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final areaH = size.height * areaPercent / 100;
    final lnH = fontSize * 1.5;
    final maxRow = max(1, (areaH / lnH).floor());

    final curSec = currentTime / 1000.0;

    // Clean expired
    activeScroll.removeWhere((a) => a.x + a.tw < -50);
    activeStatic.removeWhere((a) => a.ttl <= 0);

    // Find and emit comments near current time
    // Binary search for efficiency with large comment lists
    int startIdx = _lowerBound(curSec - 0.5);
    for (int i = startIdx; i < comments.length; i++) {
      final c = comments[i];
      final diff = curSec - c.time;
      if (diff < -0.1) break; // sorted by time, future comments
      if (diff > 0.5) continue; // too old, skip
      if (diff < 0) continue; // slightly future

      // Check if already emitted
      final already = activeScroll.any((a) => a.text == c.text && (a.time - c.time).abs() < 0.1) ||
                      activeStatic.any((a) => a.text == c.text && (a.time - c.time).abs() < 0.1);
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
          item.y = lnH + activeStatic.where((a) => a.type == 5).length * lnH;
        } else {
          item.y = size.height - lnH * 0.2 - activeStatic.where((a) => a.type == 4).length * lnH;
        }
        activeStatic.add(item);
      } else {
        // Scroll danmu
        final item = _DanmuItem(text: c.text, time: c.time, color: c.color, type: c.type);
        final tp = TextPainter(
          text: TextSpan(text: c.text, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        item.tw = tp.width;
        // Speed: traverse screen width in ~8 seconds
        item.speed = size.width / 8.0 + c.text.length * 3.0;
        item.x = size.width;
        // Find free row (anti-overlap)
        for (int r = 0; r < maxRow; r++) {
          final rowY = lnH + r * lnH;
          bool blocked = false;
          for (final a in activeScroll) {
            if ((a.y - rowY).abs() < lnH * 0.5 && a.x + a.tw + 30 > size.width * 0.7) {
              blocked = true;
              break;
            }
          }
          if (!blocked) { item.y = rowY; break; }
          if (r == maxRow - 1) item.y = -100; // no space, hide
        }
        if (item.y > 0) activeScroll.add(item);
      }
    }

    // Draw scroll danmu with real delta time
    for (final a in activeScroll) {
      a.x -= a.speed * dt;
      _drawText(canvas, a.text, a.x, a.y, a.color, paint, textPainter);
    }

    // Draw static danmu with real delta time
    for (final a in activeStatic) {
      a.ttl -= dt;
      _drawText(canvas, a.text, a.x, a.y, a.color, paint, textPainter);
    }
  }

  /// Binary search for the first comment with time >= target - 0.5
  int _lowerBound(double target) {
    int lo = 0, hi = comments.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (comments[mid].time < target) lo = mid + 1;
      else hi = mid;
    }
    return max(0, lo - 1);
  }

  void _drawText(Canvas canvas, String text, double x, double y, int color,
      Paint paint, TextPainter tp) {
    if (x < -200) return; // off-screen, skip
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
