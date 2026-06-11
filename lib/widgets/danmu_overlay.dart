import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';

class DanmuOverlay extends StatefulWidget {
  final List<DanmuComment> comments;
  final double currentTime;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;
  final double speed; // 弹幕速度倍率
  final double danmuDensity; // 弹幕密度 0.0~1.0
  final double topMargin; // 顶部偏移像素
  const DanmuOverlay({
    super.key,
    required this.comments,
    required this.currentTime,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
    this.speed = 1.0,
    this.danmuDensity = 1.0,
    this.topMargin = 0,
  });

  @override
  State<DanmuOverlay> createState() => _DanmuOverlayState();
}

class _DanmuOverlayState extends State<DanmuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  final List<_DanmuItem> _activeScroll = [];
  final List<_DanmuItem> _activeStatic = [];
  int _lastCommentCount = 0;
  double _lastRealTime = 0;

  // 缓存的TextPainter，避免每帧重建
  final Map<String, ui.Paragraph> _paragraphCache = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50), // 20fps update
    )..addListener(_tick);
    _animCtrl.repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _paragraphCache.clear();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.length != _lastCommentCount) {
      _activeScroll.clear();
      _activeStatic.clear();
      _paragraphCache.clear();
      _lastCommentCount = widget.comments.length;
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DanmuPainter(
            comments: widget.comments,
            currentTime: widget.currentTime,
            opacity: widget.opacity,
            fontSize: widget.fontSize,
            areaPercent: widget.areaPercent,
            showOutline: widget.showOutline,
            speed: widget.speed,
            danmuDensity: widget.danmuDensity,
            topMargin: widget.topMargin,
            activeScroll: _activeScroll,
            activeStatic: _activeStatic,
            lastRealTime: _lastRealTime,
            paragraphCache: _paragraphCache,
            onRealTimeUpdate: (t) => _lastRealTime = t,
          ),
          size: Size.infinite,
        ),
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
  double ttl = 6.0;
  _DanmuItem({required this.text, required this.time, this.color = 0xFFFFFFFF, this.type = 1});
}

class _DanmuPainter extends CustomPainter {
  final List<DanmuComment> comments;
  final double currentTime;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;
  final double speed;
  final double danmuDensity;
  final double topMargin;
  final List<_DanmuItem> activeScroll;
  final List<_DanmuItem> activeStatic;
  final double lastRealTime;
  final Map<String, ui.Paragraph> paragraphCache;
  final void Function(double) onRealTimeUpdate;

  _DanmuPainter({
    required this.comments,
    required this.currentTime,
    required this.activeScroll,
    required this.activeStatic,
    required this.lastRealTime,
    required this.paragraphCache,
    required this.onRealTimeUpdate,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
    this.speed = 1.0,
    this.danmuDensity = 1.0,
    this.topMargin = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (comments.isEmpty || size.width <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final dt = lastRealTime > 0 ? (now - lastRealTime).clamp(0.001, 0.2) : 0.05;
    onRealTimeUpdate(now);

    final areaH = size.height * areaPercent / 100;
    final lnH = fontSize * 1.5;
    final maxRow = max(1, (areaH / lnH).floor());
    final curSec = currentTime / 1000.0;
    final densityWindow = 0.5 * danmuDensity.clamp(0.1, 1.0);

    // 清除过期弹幕
    activeScroll.removeWhere((a) => a.x + a.tw < -100);
    activeStatic.removeWhere((a) => a.ttl <= 0);

    // 发射新弹幕 — 二分查找起始位置
    int startIdx = _lowerBound(curSec - densityWindow);
    for (int i = startIdx; i < comments.length; i++) {
      final c = comments[i];
      final diff = curSec - c.time;
      if (diff < -0.1) break;
      if (diff > densityWindow) continue;
      if (diff < 0) continue;

      // 去重检查（只检查最近的活跃弹幕）
      final already = activeScroll.any((a) => a.text == c.text && (a.time - c.time).abs() < densityWindow) ||
                      activeStatic.any((a) => a.text == c.text && (a.time - c.time).abs() < densityWindow);
      if (already) continue;

      if (c.type == 4 || c.type == 5) {
        final item = _DanmuItem(text: c.text, time: c.time, color: c.color, type: c.type);
        item.tw = _measureText(c.text);
        item.x = (size.width - item.tw) / 2;
        if (c.type == 5) {
          item.y = topMargin + lnH + activeStatic.where((a) => a.type == 5).length * lnH;
        } else {
          item.y = size.height - lnH * 0.2 - activeStatic.where((a) => a.type == 4).length * lnH;
        }
        activeStatic.add(item);
      } else {
        final item = _DanmuItem(text: c.text, time: c.time, color: c.color, type: c.type);
        item.tw = _measureText(c.text);
        item.speed = (size.width / 7.0 + c.text.length * 2.0) * speed;
        item.x = size.width;

        // 找空闲行（反重叠）
        for (int r = 0; r < maxRow; r++) {
          final rowY = topMargin + lnH + r * lnH;
          bool blocked = false;
          for (final a in activeScroll) {
            if ((a.y - rowY).abs() < lnH * 0.6 && a.x + a.tw > size.width * 0.15) {
              blocked = true;
              break;
            }
          }
          if (!blocked) { item.y = rowY; break; }
          if (r == maxRow - 1) item.y = -100;
        }
        if (item.y > 0) activeScroll.add(item);
      }
    }

    // 绘制滚动弹幕
    for (final a in activeScroll) {
      a.x -= a.speed * dt;
      _drawDanmu(canvas, a, size);
    }

    // 绘制静态弹幕
    for (final a in activeStatic) {
      a.ttl -= dt;
      _drawDanmu(canvas, a, size);
    }
  }

  double _measureText(String text) {
    final key = '${fontSize}_$text';
    if (paragraphCache.containsKey(key)) {
      return paragraphCache[key]!.longestLine + 10;
    }
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold))
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF), fontSize: fontSize))
      ..addText(text);
    final p = builder.build()..layout(ui.ParagraphConstraints(width: double.infinity));
    paragraphCache[key] = p;
    return p.longestLine + 10;
  }

  void _drawDanmu(Canvas canvas, _DanmuItem a, Size size) {
    if (a.x < -a.tw - 50 || a.x > size.width + 50) return;

    final key = '${fontSize}_${a.text}';
    final cachedP = paragraphCache[key];

    if (showOutline) {
      // 描边：用 Paint 的 foreground
      final outlineBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black.withAlpha(((opacity) * 255).toInt().clamp(0, 255)),
        ))
        ..addText(a.text);
      final outlineP = outlineBuilder.build()
        ..layout(ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(outlineP, Offset(a.x, a.y));
    }

    // 正文
    if (cachedP != null) {
      // 复用缓存但需要重新着色
      final c = Color(a.color);
      final alpha = (c.alpha * opacity).toInt().clamp(0, 255);
      final drawColor = c.withAlpha(alpha);
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(color: drawColor, fontSize: fontSize))
        ..addText(a.text);
      final p = builder.build()
        ..layout(ui.ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(p, Offset(a.x, a.y));
    } else {
      final c = Color(a.color);
      final alpha = (c.alpha * opacity).toInt().clamp(0, 255);
      final drawColor = c.withAlpha(alpha);
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(color: drawColor, fontSize: fontSize))
        ..addText(a.text);
      final p = builder.build()
        ..layout(ui.ParagraphConstraints(width: double.infinity));
      paragraphCache[key] = p;
      canvas.drawParagraph(p, Offset(a.x, a.y));
    }
  }

  int _lowerBound(double target) {
    int lo = 0, hi = comments.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (comments[mid].time < target) lo = mid + 1;
      else hi = mid;
    }
    return max(0, lo - 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
