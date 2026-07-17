import 'dart:math';
import 'package:flutter/material.dart';
import '../models/danmu_comment.dart';

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

class _DanmuOverlayState extends State<DanmuOverlay>
    with SingleTickerProviderStateMixin {
  static const _maxActive = 40;
  static const _maxLateSec = 12.0;
  static const _crossBaseSeconds = 10.0;

  late final Ticker _ticker;
  final List<_LiveDanmu> _live = [];
  final List<_LiveDanmu> _static = [];
  final List<_PendingDanmu> _pending = [];
  final Set<int> _queued = {};

  Size _size = Size.zero;
  int _lastCount = 0;
  int _scanIdx = 0;
  double _lastSec = 0;
  double? _frozenSec;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    if (widget.isPlaying) _ticker.start();
    widget.positionListenable?.addListener(_onPositionJump);
  }

  @override
  void dispose() {
    widget.positionListenable?.removeListener(_onPositionJump);
    _ticker.dispose();
    super.dispose();
  }

  void _onPositionJump() {
    if (!widget.isPlaying) return;
    final s = _sec();
    if (s < _lastSec - 0.6) {
      _reset(keepCache: true);
      _scanIdx = _lowerBound(widget.comments, s - 0.5);
      _lastSec = s;
    }
  }

  double _sec() {
    if (!widget.isPlaying) return _frozenSec ?? _rawSec();
    return _rawSec();
  }

  double _rawSec() => widget.getCurrentTime().inMilliseconds / 1000.0;

  double _pxPerSec() {
    final rate = widget.speed.clamp(0.08, 3.0);
    return (_size.width / _crossBaseSeconds) * rate;
  }

  double _rowGap() {
    final density = widget.danmuDensity.clamp(0.1, 1.0);
    final chars = 3.2 + (1.0 - density) * 3.0;
    return widget.fontSize * chars * (widget.antiOverlap ? 1.25 : 1.05);
  }

  double _lineH() => widget.fontSize * 1.5;

  int _tracks() {
    final h = _size.height * widget.areaPercent / 100;
    return max(1, (h / _lineH()).floor());
  }

  void _onFrame(Duration _) {
    if (_size.width <= 0 || widget.comments.isEmpty) return;
    if (!widget.isPlaying) return;
    _step(_sec());
  }

  void _step(double sec) {
    final list = widget.comments;
    final px = _pxPerSec();
    final sw = _size.width;
    final lnH = _lineH();
    final tracks = _tracks();
    final gap = _rowGap();

    if (sec < _lastSec - 0.6) {
      _reset(keepCache: true);
      _scanIdx = _lowerBound(list, sec - 0.5);
    }
    _lastSec = sec;

    _live.removeWhere((d) => d.x(sec, sw, px) + d.width < -6);

    _static.removeWhere((d) {
      d.ttl -= 1 / 60.0;
      return d.ttl <= 0;
    });

    while (_scanIdx < list.length && list[_scanIdx].time < sec - _maxLateSec) {
      _scanIdx++;
    }

    while (_scanIdx < list.length) {
      final c = list[_scanIdx];
      if (c.time > sec + 0.08) break;
      if (_visible(c.type) &&
          !_queued.contains(_scanIdx) &&
          _pending.length < 200) {
        _pending.add(_PendingDanmu(index: _scanIdx, comment: c));
        _queued.add(_scanIdx);
      }
      _scanIdx++;
    }

    if (_pending.isEmpty || _live.length >= _maxActive) return;

    final emitCap = 2;
    var emitted = 0;
    while (
        _pending.isNotEmpty && _live.length < _maxActive && emitted < emitCap) {
      final p = _pending.first;
      final c = p.comment;
      if (c.type == 4 || c.type == 5) {
        _pending.removeAt(0);
        emitted++;
        final w = _measure(c.text);
        final item = _LiveDanmu(
          text: c.text,
          color: c.color,
          type: c.type,
          width: w,
          x: (sw - w) / 2,
          y: c.type == 5
              ? widget.topMargin + lnH + _static.length * lnH
              : _size.height - lnH * 0.2 - _static.length * lnH,
          ttl: 6.0,
        );
        _static.add(item);
        continue;
      }

      final tw = _measure(c.text);
      int? row;
      for (var r = 0; r < tracks; r++) {
        if (_canAdd(r, tw, sec, px, gap)) {
          row = r;
          break;
        }
      }
      if (row == null) break;

      _pending.removeAt(0);
      emitted++;
      final late = sec > c.time + 0.15;
      _live.add(_LiveDanmu(
        text: c.text,
        color: c.color,
        type: c.type,
        width: tw,
        row: row,
        y: widget.topMargin + lnH + row * lnH,
        videoTime: c.time,
        releaseSec: late ? sec : null,
      ));
    }
  }

  bool _canAdd(int row, double newW, double sec, double px, double gap) {
    final sw = _size.width;
    for (final d in _live) {
      if (d.row != row) continue;
      final x = d.x(sec, sw, px);
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

  void _reset({bool keepCache = false}) {
    _live.clear();
    _static.clear();
    _pending.clear();
    _queued.clear();
    _scanIdx = 0;
    _lastSec = 0;
    _frozenSec = null;
  }

  bool _visible(int type) {
    if (type == 4) return widget.showBottom;
    if (type == 5) return widget.showTop;
    return widget.showScroll;
  }

  double _measure(String text) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: widget.fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 8;
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
      _reset();
      _lastCount = widget.comments.length;
    }
    if (!widget.isPlaying && old.isPlaying) {
      _frozenSec = _sec();
      if (_ticker.isActive) _ticker.stop();
    } else if (widget.isPlaying && !old.isPlaying) {
      _frozenSec = null;
      _lastSec = _rawSec();
      if (!_ticker.isActive) _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comments.length != _lastCount) {
      _reset();
      _lastCount = widget.comments.length;
    }

    final now = _sec();
    final sw = _size.width;
    final px = _pxPerSec();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          if (w > 0 && h > 0) _size = Size(w, h);

          return RepaintBoundary(
            child: Stack(
              children: [
                for (final d in _static)
                  _buildItem(d.text, d.color, d.x, d.y, true, 0),
                for (final d in _live)
                  if (d.x(now, sw, px) + d.width > -4 &&
                      d.x(now, sw, px) < sw + 4)
                    _buildItem(d.text, d.color, d.x(now, sw, px), d.y, false,
                        d.x(now, sw, px)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildItem(String text, int colorValue, double x, double y,
      bool isStatic, double alphaFactor) {
    final c = Color(colorValue);
    final alpha = (c.alpha * widget.opacity).toInt().clamp(0, 255);
    final style = TextStyle(
        color: c.withAlpha(alpha),
        fontSize: widget.fontSize,
        fontWeight: FontWeight.bold);
    final outlineStyle = widget.showOutline
        ? TextStyle(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.black
                  .withAlpha((widget.opacity * 255).toInt().clamp(0, 255)),
          )
        : null;

    return Positioned(
      left: x,
      top: y,
      child: Stack(
        children: [
          if (outlineStyle != null)
            Text(text,
                style: outlineStyle, maxLines: 1, overflow: TextOverflow.clip),
          Text(text, style: style, maxLines: 1, overflow: TextOverflow.clip),
        ],
      ),
    );
  }
}

class _PendingDanmu {
  final int index;
  final DanmuComment comment;
  const _PendingDanmu({required this.index, required this.comment});
}

class _LiveDanmu {
  final String text;
  final int color;
  final int type;
  final double width;
  final int? row;
  final double y;
  final double videoTime;
  final double? releaseSec;
  double x;
  double ttl;

  _LiveDanmu({
    required this.text,
    required this.color,
    required this.type,
    required this.width,
    this.row,
    this.y = 0,
    this.videoTime = 0,
    this.releaseSec,
    this.ttl = 6.0,
    double? x,
  }) : x = x ?? 0;

  double get _start => releaseSec ?? videoTime;
}
