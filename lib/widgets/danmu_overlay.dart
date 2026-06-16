import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/danmu_comment.dart';

/// 弹幕覆盖层（参考 canvas_danmaku / NSDanmaku 轨道碰撞算法）。
/// 位置由播放器时间轴驱动，暂停时冻结画面，恢复后从当前位置继续。
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
  static const _maxActiveScroll = 200;
  static const _maxParagraphCache = 800;
  static const _maxLateSec = 12.0;
  static const _maxPending = 500;
  static const _crossBaseSeconds = 12.0;

  late final Ticker _ticker;
  final ValueNotifier<int> _frameTick = ValueNotifier(0);
  final List<_ScrollDanmu> _scroll = [];
  final List<_StaticDanmu> _static = [];
  final List<_PendingDanmu> _pending = [];
  final Set<int> _queued = {};
  final Map<String, _DanmuParagraphs> _paragraphCache = {};

  Size _size = Size.zero;
  int _lastCommentCount = 0;
  int _scanIdx = 0;
  double _lastVideoSec = 0;
  double? _frozenVideoSec;
  int _staticTopSlots = 0;
  int _staticBottomSlots = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    if (widget.isPlaying) _ticker.start();
    widget.positionListenable?.addListener(_onPositionJump);
  }

  void _onPositionJump() {
    if (!widget.isPlaying) return;
    final sec = _videoSec();
    if (sec < _lastVideoSec - 0.6) {
      _resetEngine(keepCache: true);
      _scanIdx = _lowerBound(widget.comments, sec - 0.5);
      _lastVideoSec = sec;
    }
  }

  double _videoSec() {
    if (!widget.isPlaying) {
      return _frozenVideoSec ?? _secFromPlayer();
    }
    return _secFromPlayer();
  }

  double _secFromPlayer() =>
      widget.getCurrentTime().inMilliseconds / 1000.0;

  double _pxPerSec() {
    final rate = widget.speed.clamp(0.08, 3.0);
    return (_size.width / _crossBaseSeconds) * rate;
  }

  double _rowGapPx() {
    final density = widget.danmuDensity.clamp(0.1, 1.0);
    final chars = 2.5 + (1.0 - density) * 3.5;
    final gap = widget.fontSize * chars;
    return widget.antiOverlap ? gap * 1.4 : gap;
  }

  double _lineHeight() => widget.fontSize * 1.5;

  int _trackCount() {
    final h = _size.height * widget.areaPercent / 100;
    return max(1, (h / _lineHeight()).floor());
  }

  void _onFrame(Duration _) {
    if (_size.width <= 0 || widget.comments.isEmpty) return;
    if (!widget.isPlaying) return;
    _step(_videoSec());
    _frameTick.value++;
  }

  void _step(double videoSec) {
    final comments = widget.comments;
    final px = _pxPerSec();
    final sw = _size.width;
    final lnH = _lineHeight();
    final tracks = _trackCount();
    final gap = _rowGapPx();

    if (videoSec < _lastVideoSec - 0.6) {
      _resetEngine(keepCache: true);
      _scanIdx = _lowerBound(comments, videoSec - 0.5);
    }
    _lastVideoSec = videoSec;

    _scroll.removeWhere((d) => d.isOffLeft(videoSec, sw, px));

    if (widget.isPlaying) {
      _static.removeWhere((d) {
        d.ttl -= 1 / 60.0;
        if (d.ttl <= 0) {
          if (d.type == 5) _staticTopSlots = max(0, _staticTopSlots - 1);
          if (d.type == 4) _staticBottomSlots = max(0, _staticBottomSlots - 1);
          return true;
        }
        return false;
      });
    }

    while (_scanIdx < comments.length && comments[_scanIdx].time < videoSec - _maxLateSec) {
      _scanIdx++;
    }

    while (_scanIdx < comments.length) {
      final c = comments[_scanIdx];
      if (c.time > videoSec + 0.08) break;
      if (_typeVisible(c.type) && !_queued.contains(_scanIdx)) {
        if (_pending.length < _maxPending) {
          _pending.add(_PendingDanmu(index: _scanIdx, comment: c));
          _queued.add(_scanIdx);
        }
      }
      _scanIdx++;
    }

    if (_pending.isEmpty || _scroll.length >= _maxActiveScroll) return;

    var progressed = true;
    while (progressed && _pending.isNotEmpty && _scroll.length < _maxActiveScroll) {
      progressed = false;
      final p = _pending.first;
      final c = p.comment;

      if (c.type == 4 || c.type == 5) {
        _pending.removeAt(0);
        progressed = true;
        final w = _measureText(c.text);
        final item = _StaticDanmu(
          text: c.text,
          color: c.color,
          type: c.type,
          width: w,
        );
        if (c.type == 5) {
          item.y = widget.topMargin + lnH + _staticTopSlots * lnH;
          item.x = (sw - w) / 2;
          _staticTopSlots++;
        } else {
          item.y = _size.height - lnH * 0.2 - _staticBottomSlots * lnH;
          item.x = (sw - w) / 2;
          _staticBottomSlots++;
        }
        _static.add(item);
        continue;
      }

      final tw = _measureText(c.text);
      int? row;
      for (var r = 0; r < tracks; r++) {
        if (_canAddScroll(r, tw, videoSec, px, gap)) {
          row = r;
          break;
        }
      }
      if (row == null) break;

      _pending.removeAt(0);
      progressed = true;
      final late = videoSec > c.time + 0.15;
      _scroll.add(_ScrollDanmu(
        comment: c,
        sourceIndex: p.index,
        videoTime: c.time,
        releaseSec: late ? videoSec : null,
        row: row,
        width: tw,
        y: widget.topMargin + lnH + row * lnH,
      ));
    }
  }

  /// canvas_danmaku / B 站轨道碰撞：入屏不重叠，且长弹幕不追尾短弹幕
  bool _canAddScroll(int row, double newW, double videoSec, double px, double gap) {
    final sw = _size.width;
    for (final d in _scroll) {
      if (d.row != row) continue;
      final x = d.xAt(videoSec, sw, px);
      final end = x + d.width;
      if (sw - end < gap) return false;
      if (d.width < newW) {
        final traveled = sw - x;
        final total = d.width + sw;
        final progress = traveled / total;
        final newRatio = sw / (sw + newW);
        if (progress > 1 - newRatio) return false;
      }
    }
    return true;
  }

  void _resetEngine({bool keepCache = false}) {
    _scroll.clear();
    _static.clear();
    _pending.clear();
    _queued.clear();
    _scanIdx = 0;
    _staticTopSlots = 0;
    _staticBottomSlots = 0;
    _lastVideoSec = 0;
    _frozenVideoSec = null;
    if (!keepCache) _paragraphCache.clear();
  }

  bool _typeVisible(int type) {
    if (type == 4) return widget.showBottom;
    if (type == 5) return widget.showTop;
    return widget.showScroll;
  }

  double _measureText(String text) => _paragraphs(text, 0xFFFFFFFF).width;

  _DanmuParagraphs _paragraphs(String text, int colorValue) {
    final key = '${widget.fontSize}_${widget.showOutline}_${widget.opacity}_${colorValue}_$text';
    final hit = _paragraphCache[key];
    if (hit != null) return hit;

    if (_paragraphCache.length > _maxParagraphCache) {
      _paragraphCache.remove(_paragraphCache.keys.first);
    }

    ui.Paragraph? outlineP;
    if (widget.showOutline) {
      final b = ui.ParagraphBuilder(
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
      outlineP = b.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    }

    final c = Color(colorValue);
    final alpha = (c.alpha * widget.opacity).toInt().clamp(0, 255);
    final fillB = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: widget.fontSize, fontWeight: FontWeight.bold),
    )
      ..pushStyle(ui.TextStyle(color: c.withAlpha(alpha), fontSize: widget.fontSize))
      ..addText(text);
    final fillP = fillB.build()..layout(const ui.ParagraphConstraints(width: double.infinity));

    final result = _DanmuParagraphs(
      fill: fillP,
      outline: outlineP,
      width: fillP.longestLine + 10,
    );
    _paragraphCache[key] = result;
    return result;
  }

  void _prewarmCache() {
    final list = widget.comments;
    if (list.isEmpty) return;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (!mounted) return;
      final step = max(1, list.length ~/ 200);
      for (var i = 0; i < list.length; i += step) {
        _measureText(list[i].text);
      }
    });
  }

  static int _lowerBound(List<DanmuComment> list, double t) {
    int lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (list[mid].time < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return max(0, lo - 1);
  }

  @override
  void dispose() {
    widget.positionListenable?.removeListener(_onPositionJump);
    _ticker.dispose();
    _frameTick.dispose();
    _paragraphCache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DanmuOverlay old) {
    super.didUpdateWidget(old);
    if (widget.positionListenable != old.positionListenable) {
      old.positionListenable?.removeListener(_onPositionJump);
      widget.positionListenable?.addListener(_onPositionJump);
    }
    if (widget.comments.length != old.comments.length ||
        widget.fontSize != old.fontSize ||
        widget.showOutline != old.showOutline ||
        widget.opacity != old.opacity ||
        widget.speed != old.speed) {
      _resetEngine();
      _lastCommentCount = widget.comments.length;
      _prewarmCache();
    }
    if (!widget.isPlaying && old.isPlaying) {
      _frozenVideoSec = _videoSec();
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
    } else if (widget.isPlaying && !old.isPlaying) {
      _frozenVideoSec = null;
      _lastVideoSec = _secFromPlayer();
      if (!_ticker.isActive) _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.length != _lastCommentCount) {
      _resetEngine();
      _lastCommentCount = widget.comments.length;
      _prewarmCache();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          if (w > 0 && h > 0) _size = Size(w, h);

          return RepaintBoundary(
            child: CustomPaint(
              painter: _DanmuPainter(
                videoSec: _videoSec,
                pxPerSec: _pxPerSec,
                getParagraphs: _paragraphs,
                scroll: _scroll,
                staticItems: _static,
                repaint: _frameTick,
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
  const _PendingDanmu({required this.index, required this.comment});
}

class _ScrollDanmu {
  final DanmuComment comment;
  final int sourceIndex;
  final double videoTime;
  final double? releaseSec;
  final int row;
  final double width;
  final double y;

  _ScrollDanmu({
    required this.comment,
    required this.sourceIndex,
    required this.videoTime,
    required this.releaseSec,
    required this.row,
    required this.width,
    required this.y,
  });

  double get _startSec => releaseSec ?? videoTime;

  double xAt(double videoSec, double screenW, double pxPerSec) {
    final elapsed = max(0.0, videoSec - _startSec);
    return screenW - elapsed * pxPerSec;
  }

  bool isOffLeft(double videoSec, double screenW, double pxPerSec) =>
      xAt(videoSec, screenW, pxPerSec) + width < -8;
}

class _StaticDanmu {
  final String text;
  final int color;
  final int type;
  final double width;
  double x = 0;
  double y = 0;
  double ttl = 6.0;

  _StaticDanmu({
    required this.text,
    required this.color,
    required this.type,
    required this.width,
  });
}

class _DanmuParagraphs {
  final ui.Paragraph fill;
  final ui.Paragraph? outline;
  final double width;
  const _DanmuParagraphs({required this.fill, this.outline, required this.width});
}

class _DanmuPainter extends CustomPainter {
  final double Function() videoSec;
  final double Function() pxPerSec;
  final _DanmuParagraphs Function(String, int) getParagraphs;
  final List<_ScrollDanmu> scroll;
  final List<_StaticDanmu> staticItems;

  _DanmuPainter({
    required this.videoSec,
    required this.pxPerSec,
    required this.getParagraphs,
    required this.scroll,
    required this.staticItems,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final t = videoSec();
    final px = pxPerSec();
    final sw = size.width;

    for (final d in scroll) {
      final x = d.xAt(t, sw, px);
      if (x > sw + 4) continue;
      final paras = getParagraphs(d.comment.text, d.comment.color);
      final offset = Offset(x, d.y);
      if (paras.outline != null) canvas.drawParagraph(paras.outline!, offset);
      canvas.drawParagraph(paras.fill, offset);
    }

    for (final d in staticItems) {
      final paras = getParagraphs(d.text, d.color);
      final offset = Offset(d.x, d.y);
      if (paras.outline != null) canvas.drawParagraph(paras.outline!, offset);
      canvas.drawParagraph(paras.fill, offset);
    }
  }

  @override
  bool shouldRepaint(covariant _DanmuPainter old) => false;
}
