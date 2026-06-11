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
  // 每行的"弹幕完全移出屏幕的时间"（wall clock seconds）
  final Map<int, double> _rowBusyUntil = {};
  // 弹幕去重：danmu.time -> 上次尝试发射的 wall clock 时间
  final Map<double, double> _lastAttemptTime = {};
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
      _rowBusyUntil.clear();
      _lastAttemptTime.clear();
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
            rowBusyUntil: _rowBusyUntil,
            lastAttemptTime: _lastAttemptTime,
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
  final Map<int, double> rowBusyUntil;
  final Map<double, double> lastAttemptTime;
  final double lastRealTime;
  final Map<String, ui.Paragraph> paragraphCache;
  final void Function(double) onRealTimeUpdate;

  _DanmuPainter({
    required this.comments,
    required this.currentTime,
    required this.activeScroll,
    required this.activeStatic,
    required this.rowBusyUntil,
    required this.lastAttemptTime,
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

    // 统一速度：所有弹幕同一速度（px/second）
    final uniformSpeed = (size.width / 6.0) * speed;
    // 弹幕完全通过屏幕的时间
    final baseTransitTime = (size.width * 2.0) / uniformSpeed; // 留双倍屏幕宽度余量

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

      // 去重检查 — 先检查是否已成功发射到屏幕上（严格去重）
      final isDisplayed = activeScroll.any((a) => (a.time - c.time).abs() < 0.05) ||
                          activeStatic.any((a) => (a.time - c.time).abs() < 0.05);
      if (isDisplayed) continue;
      // 再检查最近是否尝试过（0.3s 内不重复尝试，给行调度器时间）
      final lastAttempt = lastAttemptTime[c.time];
      if (lastAttempt != null && (now - lastAttempt) < 0.3) continue;
      lastAttemptTime[c.time] = now;

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
        item.speed = uniformSpeed;
        item.x = size.width;

        // 找空闲行：用 wall clock 时间（now）来判断行是否可用
        // rowBusyUntil[row] = 该行上一条弹幕完全移出屏幕的 wall clock 时间
        int? selectedRow;
        for (int r = 0; r < maxRow; r++) {
          final busyUntil = rowBusyUntil[r] ?? 0.0;
          if (now >= busyUntil) {
            selectedRow = r;
            break;
          }
        }

        if (selectedRow != null) {
          // 计算弹幕从右侧完全通过屏幕左侧需要的时间
          final transitTime = (size.width + item.tw) / item.speed;
          // 更新该行的忙碌时间 = 当前 wall clock + 通过时间
          rowBusyUntil[selectedRow] = now + transitTime;

          item.y = topMargin + lnH + selectedRow * lnH;
          activeScroll.add(item);
        }
        // 没有空闲行则跳过此弹幕，下次 tick 会重新尝试
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
