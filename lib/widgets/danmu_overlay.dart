import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';

class DanmuOverlay extends StatefulWidget {
  final List<DanmuComment> comments;
  final Duration Function() getCurrentTime;
  final Listenable? positionListenable;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;
  final double speed;
  final double danmuDensity;
  final double topMargin;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool antiOverlap;

  const DanmuOverlay({
    super.key,
    required this.comments,
    required this.getCurrentTime,
    this.positionListenable,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
    this.speed = 1.0,
    this.danmuDensity = 1.0,
    this.topMargin = 0,
    this.showScroll = true,
    this.showTop = true,
    this.showBottom = true,
    this.antiOverlap = false,
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
  final Map<String, _DanmuParagraphs> _paragraphCache = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _paragraphCache.clear();
    super.dispose();
  }

  Listenable get _repaintListenable => widget.positionListenable != null
      ? Listenable.merge([_animCtrl, widget.positionListenable!])
      : _animCtrl;

  @override
  void didUpdateWidget(covariant DanmuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.comments.length != oldWidget.comments.length ||
        widget.fontSize != oldWidget.fontSize ||
        widget.showOutline != oldWidget.showOutline ||
        widget.opacity != oldWidget.opacity ||
        widget.speed != oldWidget.speed) {
      _activeScroll.clear();
      _activeStatic.clear();
      _paragraphCache.clear();
      _lastCommentCount = widget.comments.length;
    }
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
            getCurrentTime: widget.getCurrentTime,
            opacity: widget.opacity,
            fontSize: widget.fontSize,
            areaPercent: widget.areaPercent,
            showOutline: widget.showOutline,
            speed: widget.speed,
            danmuDensity: widget.danmuDensity,
            topMargin: widget.topMargin,
            showScroll: widget.showScroll,
            showTop: widget.showTop,
            showBottom: widget.showBottom,
            antiOverlap: widget.antiOverlap,
            activeScroll: _activeScroll,
            activeStatic: _activeStatic,
            lastRealTime: _lastRealTime,
            paragraphCache: _paragraphCache,
            onRealTimeUpdate: (t) => _lastRealTime = t,
            repaint: _repaintListenable,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DanmuParagraphs {
  final ui.Paragraph fill;
  final ui.Paragraph? outline;
  final double width;

  _DanmuParagraphs({required this.fill, this.outline, required this.width});
}

class _DanmuItem {
  String text;
  double time;
  int color;
  int type;
  double x = 0, y = 0, speed = 0, tw = 0;
  double ttl = 6.0;
  double launchedAt = 0;
  _DanmuItem({required this.text, required this.time, this.color = 0xFFFFFFFF, this.type = 1});
}

class _DanmuPainter extends CustomPainter {
  final List<DanmuComment> comments;
  final Duration Function() getCurrentTime;
  final double opacity;
  final double fontSize;
  final int areaPercent;
  final bool showOutline;
  final double speed;
  final double danmuDensity;
  final double topMargin;
  final bool showScroll;
  final bool showTop;
  final bool showBottom;
  final bool antiOverlap;
  final List<_DanmuItem> activeScroll;
  final List<_DanmuItem> activeStatic;
  final double lastRealTime;
  final Map<String, _DanmuParagraphs> paragraphCache;
  final void Function(double) onRealTimeUpdate;

  _DanmuPainter({
    required this.comments,
    required this.getCurrentTime,
    required this.activeScroll,
    required this.activeStatic,
    required this.lastRealTime,
    required this.paragraphCache,
    required this.onRealTimeUpdate,
    Listenable? repaint,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
    this.speed = 1.0,
    this.danmuDensity = 1.0,
    this.topMargin = 0,
    this.showScroll = true,
    this.showTop = true,
    this.showBottom = true,
    this.antiOverlap = false,
  }) : super(repaint: repaint);

  bool _typeVisible(int type) {
    if (type == 4) return showBottom;
    if (type == 5) return showTop;
    return showScroll;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (comments.isEmpty || size.width <= 0) return;

    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final dt = lastRealTime > 0 ? (now - lastRealTime).clamp(0.001, 0.2) : 0.05;
    onRealTimeUpdate(now);

    final areaH = size.height * areaPercent / 100;
    final lnH = fontSize * 1.5;
    final maxRow = max(1, (areaH / lnH).floor());
    final curSec = getCurrentTime().inMilliseconds / 1000.0;
    final densityWindow = 0.5 * danmuDensity.clamp(0.1, 1.0);
    final uniformSpeed = (size.width / 10.0) * speed;

    activeScroll.removeWhere((a) => a.x + a.tw < -50);
    activeStatic.removeWhere((a) => a.ttl <= 0);

    final rowLastItem = <int, _DanmuItem?>{};
    for (final a in activeScroll) {
      if (a.launchedAt <= 0) continue;
      final row = ((a.y - topMargin - lnH) / lnH).round();
      if (row < 0 || row >= maxRow) continue;
      final existing = rowLastItem[row];
      if (existing == null || a.launchedAt > existing.launchedAt) {
        rowLastItem[row] = a;
      }
    }

    int startIdx = _lowerBound(curSec - densityWindow);
    for (int i = startIdx; i < comments.length; i++) {
      final c = comments[i];
      if (!_typeVisible(c.type)) continue;

      final diff = curSec - c.time;
      if (diff < -0.1) break;
      if (diff > densityWindow || diff < 0) continue;

      final isDisplayed = activeScroll.any((a) => (a.time - c.time).abs() < 0.05) ||
          activeStatic.any((a) => (a.time - c.time).abs() < 0.05);
      if (isDisplayed) continue;

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

        int? selectedRow;
        for (int r = 0; r < maxRow; r++) {
          if (_rowHasOverlap(r, lnH, size.width, item.tw)) continue;
          final lastInRow = rowLastItem[r];
          if (lastInRow == null) {
            selectedRow = r;
            break;
          }
          final gapWidth = size.width * 0.15;
          if (lastInRow.x + lastInRow.tw < size.width - gapWidth) {
            selectedRow = r;
            break;
          }
        }

        if (selectedRow != null) {
          item.x = size.width;
          item.y = topMargin + lnH + selectedRow * lnH;
          item.launchedAt = now;
          activeScroll.add(item);
          rowLastItem[selectedRow] = item;
        }
      }
    }

    for (final a in activeScroll) {
      a.x -= a.speed * dt;
      _drawDanmu(canvas, a, size);
    }
    for (final a in activeStatic) {
      a.ttl -= dt;
      _drawDanmu(canvas, a, size);
    }
  }

  bool _rowHasOverlap(int row, double lnH, double screenW, double tw) {
    if (!antiOverlap) return false;
    final y = topMargin + lnH + row * lnH;
    for (final a in activeScroll) {
      if ((a.y - y).abs() > lnH * 0.5) continue;
      if (a.x < screenW && a.x + a.tw > screenW - tw * 0.5) return true;
    }
    return false;
  }

  double _measureText(String text) {
    return _getParagraphs(text, 0xFFFFFFFF).width;
  }

  _DanmuParagraphs _getParagraphs(String text, int colorValue) {
    final key = '${fontSize}_${showOutline}_${opacity}_${colorValue}_$text';
    if (paragraphCache.containsKey(key)) return paragraphCache[key]!;

    ui.Paragraph? outlineP;
    if (showOutline) {
      final outlineBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFF000000),
          fontSize: fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black.withAlpha((opacity * 255).toInt().clamp(0, 255)),
        ))
        ..addText(text);
      outlineP = outlineBuilder.build()
        ..layout(ui.ParagraphConstraints(width: double.infinity));
    }

    final c = Color(colorValue);
    final alpha = (c.alpha * opacity).toInt().clamp(0, 255);
    final fillBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: c.withAlpha(alpha), fontSize: fontSize))
      ..addText(text);
    final fillP = fillBuilder.build()
      ..layout(ui.ParagraphConstraints(width: double.infinity));

    final result = _DanmuParagraphs(
      fill: fillP,
      outline: outlineP,
      width: fillP.longestLine + 10,
    );
    paragraphCache[key] = result;
    return result;
  }

  void _drawDanmu(Canvas canvas, _DanmuItem a, Size size) {
    if (a.x < -a.tw - 50 || a.x > size.width + 50) return;
    final paras = _getParagraphs(a.text, a.color);
    if (paras.outline != null) {
      canvas.drawParagraph(paras.outline!, Offset(a.x, a.y));
    }
    canvas.drawParagraph(paras.fill, Offset(a.x, a.y));
  }

  int _lowerBound(double target) {
    int lo = 0, hi = comments.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (comments[mid].time < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return max(0, lo - 1);
  }

  @override
  bool shouldRepaint(covariant _DanmuPainter oldDelegate) {
    // 动画帧由 repaint: _animCtrl 驱动；此处仅比较静态属性
    return oldDelegate.comments != comments ||
        oldDelegate.opacity != opacity ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.areaPercent != areaPercent ||
        oldDelegate.showOutline != showOutline ||
        oldDelegate.speed != speed ||
        oldDelegate.danmuDensity != danmuDensity ||
        oldDelegate.topMargin != topMargin ||
        oldDelegate.showScroll != showScroll ||
        oldDelegate.showTop != showTop ||
        oldDelegate.showBottom != showBottom ||
        oldDelegate.antiOverlap != antiOverlap;
  }
}
