import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/play_list_item.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import '../models/stream_response.dart';
import '../providers/app_state.dart';

class PlayerControls extends StatelessWidget {
  final String title;
  final bool isPlaying;
  final bool isLocked;
  final double speed;
  final Duration position;
  final Duration duration;
  final List<PlayListItem>? episodeList;
  final int currentEpIndex;
  final bool danmuOn;
  final int qualityCount;
  final List<String> qualityLabels;
  final int qualityIndex;
  final List<AudioStreamInfo>? audioStreams;
  final List<SubtitleStreamInfo>? subtitleStreams;
  final int selectedAudioIndex;
  final int selectedSubtitleIndex;
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;
  final void Function(double) onSpeed;
  final VoidCallback onLock;
  final VoidCallback onDanmu;
  final VoidCallback onBack;
  final void Function(int) onEpisode;
  final void Function(int) onQuality;
  final void Function(int) onAudioSelected;
  final void Function(int) onSubtitleSelected;
  final void Function(double) onSeekChanged;

  const PlayerControls({
    super.key,
    required this.title,
    required this.isPlaying,
    required this.isLocked,
    required this.speed,
    required this.position,
    required this.duration,
    this.episodeList,
    required this.currentEpIndex,
    required this.danmuOn,
    required this.qualityCount,
    required this.qualityLabels,
    required this.qualityIndex,
    this.audioStreams,
    this.subtitleStreams,
    this.selectedAudioIndex = 0,
    this.selectedSubtitleIndex = -1,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeed,
    required this.onLock,
    required this.onDanmu,
    required this.onBack,
    required this.onEpisode,
    required this.onQuality,
    required this.onAudioSelected,
    required this.onSubtitleSelected,
    required this.onSeekChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLocked) return const SizedBox.shrink();

    final posMs = position.inMilliseconds.toDouble();
    final durMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
          stops: [0, 0.2, 0.7, 1],
        ),
      ),
      child: Column(
        children: [
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  ),
                  GestureDetector(
                    onTap: () => _showDanmuPanel(context),
                    onLongPress: onDanmu, // 长按快速开关
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: danmuOn ? FnTheme.danmuGreen.withOpacity(0.3) : Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('弹', style: TextStyle(
                        color: danmuOn ? FnTheme.danmuGreen : Colors.grey,
                        fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Bottom controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: FnTheme.danmuGreen,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: FnTheme.danmuGreen,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: posMs.clamp(0.0, durMs),
                    min: 0.0,
                    max: durMs,
                    onChanged: onSeekChanged,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        '${formatDuration(position.inSeconds)} / ${formatDuration(duration.inSeconds)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      _ctrlBtn('10秒', () => onSeek(const Duration(seconds: -10))),
                      GestureDetector(
                        onTap: onPlayPause,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: FnTheme.danmuGreen.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white, size: 28,
                          ),
                        ),
                      ),
                      _ctrlBtn('10秒', () => onSeek(const Duration(seconds: 10))),
                      const SizedBox(width: 8),
                      _ctrlBtn('${speed}x', () => _showSpeedMenu(context)),
                      if (qualityCount > 0)
                        _ctrlBtn(qualityLabels.isNotEmpty ? qualityLabels[qualityIndex] : '画质', () => _showQualityMenu(context)),
                      if (episodeList != null && episodeList!.isNotEmpty)
                        _ctrlBtn('选集', () => _showEpisodePanel(context)),
                      if (audioStreams != null && audioStreams!.length > 1)
                        _ctrlBtn('音频', () => _showAudioMenu(context)),
                      if (subtitleStreams != null && subtitleStreams!.isNotEmpty)
                        _ctrlBtn('字幕', () => _showSubtitlePanel(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _ctrlBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }

  // ── 倍速：紧凑弹窗 ──────────────────────────────────────

  void _showSpeedMenu(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    _showCompactPopup(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('倍速', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: speeds.map((s) {
              final isCurrent = (s - speed).abs() < 0.01;
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onSpeed(s);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent ? FnTheme.danmuGreen : Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s == 1.0 ? '正常' : '${s}x',
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── 画质：紧凑弹窗 ──────────────────────────────────────

  void _showQualityMenu(BuildContext context) {
    _showCompactPopup(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(qualityCount, (i) {
          final isCurrent = i == qualityIndex;
          return GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onQuality(i);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isCurrent)
                    const Icon(Icons.check, color: FnTheme.danmuGreen, size: 14),
                  if (isCurrent) const SizedBox(width: 4),
                  Text(qualityLabels[i], style: TextStyle(
                    color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── 音频：右侧滑入面板 ──────────────────────────────────

  void _showAudioMenu(BuildContext context) {
    if (audioStreams == null || audioStreams!.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'audio',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: _AudioPanel(
              audioStreams: audioStreams!,
              selectedIndex: selectedAudioIndex,
              onSelect: (i) {
                Navigator.pop(ctx);
                onAudioSelected(i);
              },
            ),
          ),
        );
      },
    );
  }

  // ── 字幕：右侧滑入面板（选择+样式） ─────────────────────

  void _showSubtitlePanel(BuildContext context) {
    if (subtitleStreams == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'subtitle',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: _SubtitlePanel(
              subtitleStreams: subtitleStreams!,
              selectedIndex: selectedSubtitleIndex,
              onSelect: (idx) {
                Navigator.pop(ctx);
                onSubtitleSelected(idx);
              },
            ),
          ),
        );
      },
    );
  }

  // ── 弹幕设置：右侧滑入面板 ──────────────────────────────

  void _showDanmuPanel(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'danmu',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: const _DanmuPanel(),
          ),
        );
      },
    );
  }

  // ── 选集：右侧滑入面板 ──────────────────────────────────

  void _showEpisodePanel(BuildContext context) {
    if (episodeList == null || episodeList!.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'episodes',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: _EpisodePanel(
              episodeList: episodeList!,
              currentEpIndex: currentEpIndex,
              onSelect: (i) {
                Navigator.pop(ctx);
                onEpisode(i);
              },
            ),
          ),
        );
      },
    );
  }

  // ── 紧凑弹窗工具方法 ────────────────────────────────────

  void _showCompactPopup({required BuildContext context, required Widget child}) {
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 70, left: 12, right: 12),
          child: Material(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

}

// ── 音频右侧面板 ──────────────────────────────────────────

class _AudioPanel extends StatelessWidget {
  final List<AudioStreamInfo> audioStreams;
  final int selectedIndex;
  final void Function(int) onSelect;

  const _AudioPanel({
    required this.audioStreams,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW * 0.30;
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SizedBox(
        width: panelW.clamp(240.0, 350.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.volume_up, color: FnTheme.danmuGreen, size: 20),
                  const SizedBox(width: 8),
                  Text('音频 (${audioStreams.length})', style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: audioStreams.length,
                itemBuilder: (_, i) {
                  final a = audioStreams[i];
                  final isCurrent = i == selectedIndex;
                  final label = _audioLabelStatic(a, i);
                  return GestureDetector(
                    onTap: () => onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isCurrent
                            ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          if (isCurrent)
                            const Icon(Icons.check_circle, color: FnTheme.danmuGreen, size: 18),
                          if (!isCurrent)
                            const Icon(Icons.circle_outlined, color: Colors.white38, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(label, style: TextStyle(
                              color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            )),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _audioLabelStatic(AudioStreamInfo a, int index) {
    final parts = <String>[];
    if (a.title != null && a.title!.isNotEmpty) parts.add(a.title!);
    if (a.language != null && a.language!.isNotEmpty) parts.add(a.language!);
    if (a.codecName != null && a.codecName!.isNotEmpty) parts.add(a.codecName!.toUpperCase());
    if (a.channels > 0) parts.add('${a.channels}ch');
    if (parts.isEmpty) return '音频 ${index + 1}';
    return parts.join(' · ');
  }
}

// ── 字幕右侧面板（选择+样式） ──────────────────────────────

class _SubtitlePanel extends StatefulWidget {
  final List<SubtitleStreamInfo> subtitleStreams;
  final int selectedIndex;
  final void Function(int) onSelect;

  const _SubtitlePanel({
    required this.subtitleStreams,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<_SubtitlePanel> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW * 0.35;
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SizedBox(
        width: panelW.clamp(280.0, 400.0),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.subtitles, color: FnTheme.danmuGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text('字幕设置', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // 字幕轨道
                  const Text('字幕轨道', style: TextStyle(
                    color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...List.generate(widget.subtitleStreams.length + 1, (i) {
                    final isOff = i == 0;
                    final isCurrent = isOff
                        ? widget.selectedIndex < 0
                        : (i - 1) == widget.selectedIndex;
                    final label = isOff ? '关闭字幕' : _subtitleLabel(widget.subtitleStreams[i - 1], i - 1);
                    return GestureDetector(
                      onTap: () => widget.onSelect(isOff ? -1 : i - 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isCurrent
                              ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.3))
                              : null,
                        ),
                        child: Row(
                          children: [
                            if (isCurrent)
                              const Icon(Icons.check_circle, color: FnTheme.danmuGreen, size: 16),
                            if (!isCurrent)
                              const Icon(Icons.circle_outlined, color: Colors.white38, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(label, style: TextStyle(
                              color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ))),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(color: Colors.white12, height: 24),
                  // 字幕样式
                  const Text('字幕样式', style: TextStyle(
                    color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _styleSlider('字号', app.subtitleSize, 14, 40, (v) => setState(() => app.subtitleSize = v)),
                  _styleSlider('粗细', app.subtitleWeight, 100, 900, (v) => setState(() => app.subtitleWeight = v), _weightLabel(app.subtitleWeight)),
                  _styleSlider('描边', app.subtitleOutline, 0, 4, (v) => setState(() => app.subtitleOutline = v)),
                  _switchRow('背景', app.subtitleBackground, (v) => setState(() => app.subtitleBackground = v)),
                  _colorRow(app),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weightLabel(double w) {
    if (w <= 200) return '极细';
    if (w <= 300) return '细';
    if (w <= 400) return '常规';
    if (w <= 600) return '中粗';
    if (w <= 700) return '粗';
    return '极粗';
  }

  Widget _styleSlider(String label, double value, double min, double max,
      void Function(double) onChanged, [String? displayValue]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: FnTheme.danmuGreen,
                inactiveTrackColor: Colors.white24,
                thumbColor: FnTheme.danmuGreen,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(displayValue ?? value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, void Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Expanded(
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: value,
              activeColor: FnTheme.danmuGreen,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow(AppState app) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const SizedBox(width: 40, child: Text('颜色', style: TextStyle(color: Colors.white70, fontSize: 12))),
          ...([0xFFFFFFFF, 0xFFFFFF00, 0xFF00FF00, 0xFF00FFFF, 0xFFFF6600].map((c) =>
            GestureDetector(
              onTap: () => setState(() => app.subtitleColorValue = c),
              child: Container(
                width: 24, height: 24,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: app.subtitleColorValue == c
                      ? Border.all(color: FnTheme.danmuGreen, width: 2)
                      : null,
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  String _subtitleLabel(SubtitleStreamInfo s, int index) {
    final parts = <String>[];
    if (s.title != null && s.title!.isNotEmpty) parts.add(s.title!);
    if (s.language != null && s.language!.isNotEmpty) parts.add(s.language!);
    if (s.codecName != null && s.codecName!.isNotEmpty) parts.add(s.codecName!.toUpperCase());
    if (parts.isEmpty) return '字幕 ${index + 1}';
    return parts.join(' · ');
  }
}

// ── 弹幕设置右侧面板 ──────────────────────────────────────

class _DanmuPanel extends StatelessWidget {
  const _DanmuPanel();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW * 0.30;
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SizedBox(
        width: panelW.clamp(250.0, 350.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.comment, color: FnTheme.danmuGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text('弹幕设置', style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // 开关
                  SwitchListTile(
                    dense: true,
                    title: const Text('开启弹幕', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: app.danmuOn,
                    activeColor: FnTheme.danmuGreen,
                    onChanged: (v) => app.danmuOn = v,
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  // 字号
                  _slider('字号', app.danmuFontSize, 14, 36, (v) => app.danmuFontSize = v, '${app.danmuFontSize.toInt()}'),
                  // 速度
                  _slider('速度', app.danmuSpeed, 0.3, 3.0, (v) => app.danmuSpeed = v, '${app.danmuSpeed.toStringAsFixed(1)}x'),
                  // 透明度
                  _slider('透明度', app.danmuOpacity, 0.1, 1.0, (v) => app.danmuOpacity = v, '${(app.danmuOpacity * 100).toInt()}%'),
                  // 区域
                  _slider('区域', app.danmuArea.toDouble(), 10, 100, (v) => app.danmuArea = v.toInt(), '${app.danmuArea}%'),
                  // 密度
                  _slider('密度', app.danmuDensity.toDouble(), 10, 100, (v) => app.danmuDensity = v.toInt(), '${app.danmuDensity}%'),
                  const Divider(color: Colors.white12, height: 16),
                  // 描边
                  SwitchListTile(
                    dense: true,
                    title: const Text('文字描边', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: app.danmuOutline,
                    activeColor: FnTheme.danmuGreen,
                    onChanged: (v) => app.danmuOutline = v,
                  ),
                  // 防重叠
                  SwitchListTile(
                    dense: true,
                    title: const Text('防止重叠', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: app.danmuAntiOverlap,
                    activeColor: FnTheme.danmuGreen,
                    onChanged: (v) => app.danmuAntiOverlap = v,
                  ),
                  // 合并重复
                  SwitchListTile(
                    dense: true,
                    title: const Text('合并重复', style: TextStyle(color: Colors.white, fontSize: 14)),
                    value: app.danmuMergeDuplicates,
                    activeColor: FnTheme.danmuGreen,
                    onChanged: (v) => app.danmuMergeDuplicates = v,
                  ),
                  const Divider(color: Colors.white12, height: 16),
                  // 弹幕服务器
                  ListTile(
                    dense: true,
                    title: const Text('弹幕服务器', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(
                      app.danmuUrl.isEmpty ? '未设置' : app.danmuUrl,
                      style: TextStyle(color: app.danmuUrl.isEmpty ? Colors.orange : Colors.white54, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                    onTap: () => _showUrlEditor(context, app),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String display) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: FnTheme.danmuGreen,
                inactiveTrackColor: Colors.white24,
                thumbColor: FnTheme.danmuGreen,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                trackHeight: 2,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(display, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  void _showUrlEditor(BuildContext context, AppState app) {
    final ctrl = TextEditingController(text: app.danmuUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('弹幕服务器地址', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.100:9321',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () { app.danmuUrl = ctrl.text.trim(); Navigator.pop(ctx); },
            child: const Text('保存', style: TextStyle(color: FnTheme.danmuGreen)),
          ),
        ],
      ),
    );
  }
}

// ── 选集右侧面板 ──────────────────────────────────────────

class _EpisodePanel extends StatelessWidget {
  final List<PlayListItem> episodeList;
  final int currentEpIndex;
  final void Function(int) onSelect;

  const _EpisodePanel({
    required this.episodeList,
    required this.currentEpIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final panelW = screenW * 0.35; // 右侧 35% 宽度
    return Material(
      color: const Color(0xFF1A1A1A),
      child: SizedBox(
        width: panelW.clamp(280.0, 400.0),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.list, color: FnTheme.danmuGreen, size: 20),
                  const SizedBox(width: 8),
                  Text('选集 (${episodeList.length})', style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // 剧集列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: episodeList.length,
                itemBuilder: (_, i) {
                  final ep = episodeList[i];
                  final isCurrent = i == currentEpIndex;
                  return GestureDetector(
                    onTap: () => onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? FnTheme.danmuGreen.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isCurrent
                            ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          // 集号
                          Container(
                            width: 36, height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCurrent ? FnTheme.danmuGreen : Colors.white12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${ep.episodeNumber > 0 ? ep.episodeNumber : i + 1}',
                              style: TextStyle(
                                color: isCurrent ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 标题
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ep.title ?? '第${ep.episodeNumber > 0 ? ep.episodeNumber : i + 1}集',
                                  style: TextStyle(
                                    color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const Icon(Icons.play_circle_filled, color: FnTheme.danmuGreen, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
