import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/danmu_comment.dart';

/// 弹幕覆盖层：轨道队列 + 字间距跟发，显示区域内不丢弹幕、不重叠。
class DanmuOverlay extends StatefulWidget {
  final List<DanmuComment> comments;
  final Duration Function() getCurrentTime;
  final Listenable? positionListenable;
  final bool isPlaying;
  final double playbackSpeed;
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
    this.isPlaying = true,
    this.playbackSpeed = 1.0,
    this.opacity = 0.85,
    this.fontSize = 22,
    this.areaPercent = 35,
    this.showOutline = true,
    this.speed = 0.6,
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

class _DanmuOverlayState extends State<DanmuOverlay> with SingleTickerProviderStateMixin {
  static const _maxActiveScroll = 150;
  static const _maxParagraphCache = 800;
  static const _maxLateSec = 8.0;
  static const _maxPending = 400;

  late AnimationController _repaintCtrl;
  final List<_DanmuItem> _activeScroll = [];
  final List<_DanmuItem> _activeStatic = [];
  final List<_PendingDanmu> _pending = [];
  final Set<int> _queuedIndices = {};
  final Map<String, _DanmuParagraphs> _paragraphCache = {};

  Size _size = Size.zero;
  int _lastCommentCount = 0;
  int _scanIdx = 0;
  int _topStaticCount = 0;
  int _bottomStaticCount = 0;
  double _lastCurSec = 0;
  double _anchorVideoSec = 0;
  double _anchorWallSec = 0;
  int _lastSyncMs = 0;

  @override
  void initState() {
    super.initState();
    _resetAnchor();
    _repaintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick)
      ..repeat();
    widget.positionListenable?.addListener(_onPositionTick);
  }

  void _onPositionTick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSyncMs < 400) return;
    _lastSyncMs = now;
    _softSyncAnchor();
  }

  void _resetAnchor() {
    _anchorVideoSec = widget.getCurrentTime().inMilliseconds / 1000.0;
    _anchorWallSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
  }

  /// 仅快退/大偏差时硬同步，避免正常播放时 position 回调造成回弹
  void _softSyncAnchor() {
    final actual = widget.getCurrentTime().inMilliseconds / 1000.0;
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (!widget.isPlaying) {
      _anchorVideoSec = actual;
      _anchorWallSec = wallNow;
      return;
    }
    final extrapolated = _anchorVideoSec + (wallNow - _anchorWallSec) * widget.playbackSpeed.clamp(0.1, 4.0);
    if (actual < extrapolated - 0.8) {
      _anchorVideoSec = actual;
      _anchorWallSec = wallNow;
    }
  }

  double _videoSec() {
    if (!widget.isPlaying) {
      return widget.getCurrentTime().inMilliseconds / 1000.0;
    }
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final rate = widget.playbackSpeed.clamp(0.1, 4.0);
    return _anchorVideoSec + (wallNow - _anchorWallSec) * rate;
  }

  void _onTick() {
    if (_size.width <= 0 || widget.comments.isEmpty) return;
    final curSec = _videoSec();
    _updateDanmu(curSec);
  }

  void _resetDanmuState() {
    _activeScroll.clear();
    _activeStatic.clear();
    _pending.clear();
    _queuedIndices.clear();
    _scanIdx = 0;
    _topStaticCount = 0;
    _bottomStaticCount = 0;
    _lastCurSec = 0;
    _paragraphCache.clear();
    _resetAnchor();
  }

  double _rowGap() {
    final density = widget.danmuDensity.clamp(0.1, 1.0);
    final baseChars = 2.5 + (1.0 - density) * 3.5;
    final gap = widget.fontSize * baseChars;
    return widget.antiOverlap ? gap * 1.4 : gap;
  }

  int _maxRows(double lnH) {
    final areaH = _size.height * widget.areaPercent / 100;
    return max(1, (areaH / lnH).floor());
  }

  void _trimParagraphCache() {
    if (_paragraphCache.length <= _maxParagraphCache) return;
    final keys = _paragraphCache.keys.toList(growable: false);
    for (var i = 0; i < keys.length ~/ 2; i++) {
      _paragraphCache.remove(keys[i]);
    }
  }

  void _prewarmParagraphCache() {
    final comments = widget.comments;
    if (comments.isEmpty) return;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted) return;
      final step = max(1, comments.length ~/ 200);
      for (var i = 0; i < comments.length; i += step) {
        _measureText(comments[i].text);
      }
    });
  }

  @override
  void dispose() {
    widget.positionListenable?.removeListener(_onPositionTick);
    _repaintCtrl.removeListener(_onTick);
    _repaintCtrl.dispose();
    _paragraphCache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DanmuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positionListenable != oldWidget.positionListenable) {
      oldWidget.positionListenable?.removeListener(_onPositionTick);
      widget.positionListenable?.addListener(_onPositionTick);
    }
    if (widget.comments.length != oldWidget.comments.length ||
        widget.fontSize != oldWidget.fontSize ||
        widget.showOutline != oldWidget.showOutline ||
        widget.opacity != oldWidget.opacity ||
        widget.speed != oldWidget.speed) {
      _resetDanmuState();
      _lastCommentCount = widget.comments.length;
      _prewarmParagraphCache();
    }
    if (!widget.isPlaying && oldWidget.isPlaying) {
      _resetAnchor();
    }
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _resetAnchor();
    }
  }

  void _updateDanmu(double curSec) {
    final comments = widget.comments;
    final lnH = widget.fontSize * 1.5;
    final maxRow = _maxRows(lnH);
    final pxPerSec = _DanmuPainter.pixelsPerVideoSecond(_size.width, widget.speed);
    final gap = _rowGap();

    if (curSec < _lastCurSec - 0.8) {
      _resetDanmuState();
      _scanIdx = _lowerBound(comments, curSec - 1.0);
    }
    _lastCurSec = curSec;

    _activeScroll.removeWhere((a) {
      final elapsed = curSec - a.spawnSec;
      if (elapsed < 0) return true;
      final x = _size.width - elapsed * pxPerSec;
      return x + a.tw < -120;
    });

    _activeStatic.removeWhere((a) {
      a.ttl -= 1 / 60.0;
      if (a.ttl <= 0) {
        if (a.type == 5) {
          _topStaticCount = max(0, _topStaticCount - 1);
        } else if (a.type == 4) {
          _bottomStaticCount = max(0, _bottomStaticCount - 1);
        }
        return true;
      }
      return false;
    });

    while (_scanIdx < comments.length && comments[_scanIdx].time < curSec - _maxLateSec) {
      _scanIdx++;
    }

    while (_scanIdx < comments.length) {
      final c = comments[_scanIdx];
      if (c.time > curSec + 0.05) break;
      if (!_typeVisible(c.type)) {
        _scanIdx++;
        continue;
      }
      if (!_queuedIndices.contains(_scanIdx)) {
        if (_pending.length < _maxPending) {
          _pending.add(_PendingDanmu(index: _scanIdx, comment: c));
          _queuedIndices.add(_scanIdx);
        }
      }
      _scanIdx++;
    }

    if (_pending.isEmpty || _activeScroll.length >= _maxActiveScroll) return;

    var progressed = true;
    while (progressed && _pending.isNotEmpty && _activeScroll.length < _maxActiveScroll) {
      progressed = false;
      final p = _pending.first;
      final c = p.comment;

      if (c.type == 4 || c.type == 5) {
        _pending.removeAt(0);
        progressed = true;
        final item = _DanmuItem(
          text: c.text,
          videoTime: c.time,
          spawnSec: curSec,
          color: c.color,
          type: c.type,
        );
        item.tw = _measureText(c.text);
        item.x = (_size.width - item.tw) / 2;
        if (c.type == 5) {
          item.y = widget.topMargin + lnH + _topStaticCount * lnH;
          _topStaticCount++;
        } else {
          item.y = _size.height - lnH * 0.2 - _bottomStaticCount * lnH;
          _bottomStaticCount++;
        }
        _activeStatic.add(item);
        continue;
      }

      final tw = _measureText(c.text);
      int? row;
      for (var r = 0; r < maxRow; r++) {
        if (_rowCanRelease(r, tw, curSec, pxPerSec, gap)) {
          row = r;
          break;
        }
      }

      if (row == null) break;

      _pending.removeAt(0);
      progressed = true;
      final item = _DanmuItem(
        text: c.text,
        videoTime: c.time,
        spawnSec: curSec,
        color: c.color,
        type: c.type,
        row: row,
      );
      item.tw = tw;
      item.y = widget.topMargin + lnH + row * lnH;
      _activeScroll.add(item);
    }
  }

  /// 该行尾部已留出 [gap] 空隙，可从右侧跟发下一条
  bool _rowCanRelease(int row, double tw, double curSec, double pxPerSec, double gap) {
    double maxRight = 0;
    var has = false;
    for (final a in _activeScroll) {
      if (a.row != row) continue;
      final elapsed = curSec - a.spawnSec;
      if (elapsed < 0) continue;
      final x = _size.width - elapsed * pxPerSec;
      final right = x + a.tw;
      if (!has || right > maxRight) {
        maxRight = right;
        has = true;
      }
    }
    if (!has) return true;
    return maxRight + gap <= _size.width + 2;
  }

  bool _typeVisible(int type) {
    if (type == 4) return widget.showBottom;
    if (type == 5) return widget.showTop;
    return widget.showScroll;
  }

  double _measureText(String text) => _getParagraphs(text, 0xFFFFFFFF).width;

  _DanmuParagraphs _getParagraphs(String text, int colorValue) {
    final key = '${widget.fontSize}_${widget.showOutline}_${widget.opacity}_${colorValue}_$text';
    final cached = _paragraphCache[key];
    if (cached != null) return cached;

    _trimParagraphCache();

    ui.Paragraph? outlineP;
    if (widget.showOutline) {
      final outlineBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: widget.fontSize, fontWeight: FontWeight.bold),
      )
        ..pushStyle(ui.TextStyle(
          fontSize: widget.fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.black.withAlpha((widget.opacity * 255).toInt().clamp(0, 255)),
        ))
        ..addText(text);
      outlineP = outlineBuilder.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
    }

    final c = Color(colorValue);
    final alpha = (c.alpha * widget.opacity).toInt().clamp(0, 255);
    final fillBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: widget.fontSize, fontWeight: FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: c.withAlpha(alpha), fontSize: widget.fontSize))
      ..addText(text);
    final fillP = fillBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final result = _DanmuParagraphs(
      fill: fillP,
      outline: outlineP,
      width: fillP.longestLine + 10,
    );
    _paragraphCache[key] = result;
    return result;
  }

  static int _lowerBound(List<DanmuComment> comments, double target) {
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
  Widget build(BuildContext context) {
    if (widget.comments.length != _lastCommentCount) {
      _resetDanmuState();
      _lastCommentCount = widget.comments.length;
      _prewarmParagraphCache();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          if (w > 0 && h > 0 && (w != _size.width || h != _size.height)) {
            _size = Size(w, h);
          }
          return RepaintBoundary(
            child: CustomPaint(
              painter: _DanmuPainter(
                videoSec: _videoSec,
                speed: widget.speed,
                getParagraphs: _getParagraphs,
                activeScroll: _activeScroll,
                activeStatic: _activeStatic,
                repaint: _repaintCtrl,
              ),
              size: Size.infinite,
            ),
          );
        },
      ),
    );
  }
}

class _PendingDanmu {
  final int index;
  final DanmuComment comment;
  _PendingDanmu({required this.index, required this.comment});
}

class _DanmuParagraphs {
  final ui.Paragraph fill;
  final ui.Paragraph? outline;
  final double width;

  _DanmuParagraphs({required this.fill, this.outline, required this.width});
}

class _DanmuItem {
  String text;
  double videoTime;
  double spawnSec;
  int color;
  int type;
  int row;
  double x = 0, y = 0, tw = 0;
  double ttl = 6.0;

  _DanmuItem({
    required this.text,
    required this.videoTime,
    required this.spawnSec,
    this.color = 0xFFFFFFFF,
    this.type = 1,
    this.row = 0,
  });
}

class _DanmuPainter extends CustomPainter {
  static const _crossBaseSeconds = 14.0;

  final double Function() videoSec;
  final double speed;
  final _DanmuParagraphs Function(String text, int colorValue) getParagraphs;
  final List<_DanmuItem> activeScroll;
  final List<_DanmuItem> activeStatic;

  _DanmuPainter({
    required this.videoSec,
    required this.speed,
    required this.getParagraphs,
    required this.activeScroll,
    required this.activeStatic,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static double pixelsPerVideoSecond(double screenWidth, double speed) {
    final rate = speed.clamp(0.08, 3.0);
    return (screenWidth / _crossBaseSeconds) * rate;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;

    final t = videoSec();
    final pxPerSec = pixelsPerVideoSecond(size.width, speed);
    final right = size.width + 80;
    const left = -160.0;

    for (final a in activeScroll) {
      final elapsed = t - a.spawnSec;
      if (elapsed < 0) continue;
      final x = size.width - elapsed * pxPerSec;
      if (x < left || x > right) continue;
      final paras = getParagraphs(a.text, a.color);
      final offset = Offset(x, a.y);
      if (paras.outline != null) {
        canvas.drawParagraph(paras.outline!, offset);
      }
      canvas.drawParagraph(paras.fill, offset);
    }

    for (final a in activeStatic) {
      final paras = getParagraphs(a.text, a.color);
      final offset = Offset(a.x, a.y);
      if (paras.outline != null) {
        canvas.drawParagraph(paras.outline!, offset);
      }
      canvas.drawParagraph(paras.fill, offset);
    }
  }

  @override
  bool shouldRepaint(covariant _DanmuPainter oldDelegate) => false;
}
