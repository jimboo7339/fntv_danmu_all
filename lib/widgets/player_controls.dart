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
                    onTap: onDanmu,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isCurrent)
                    const Icon(Icons.check, color: FnTheme.danmuGreen, size: 16),
                  if (isCurrent) const SizedBox(width: 6),
                  Text(qualityLabels[i], style: TextStyle(
                    color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                    fontSize: 13,
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

  // ── 音频：紧凑弹窗 ──────────────────────────────────────

  void _showAudioMenu(BuildContext context) {
    if (audioStreams == null || audioStreams!.isEmpty) return;
    _showCompactPopup(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(audioStreams!.length, (i) {
          final a = audioStreams![i];
          final isCurrent = i == selectedAudioIndex;
          final label = _audioLabel(a, i);
          return GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onAudioSelected(i);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isCurrent)
                    const Icon(Icons.check, color: FnTheme.danmuGreen, size: 16),
                  if (isCurrent) const SizedBox(width: 6),
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
      ),
    );
  }

  // ── 字幕：选择 + 样式调节面板 ────────────────────────────

  void _showSubtitlePanel(BuildContext context) {
    if (subtitleStreams == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _SubtitlePanel(
        subtitleStreams: subtitleStreams!,
        selectedIndex: selectedSubtitleIndex,
        onSelect: (idx) {
          Navigator.pop(sheetCtx);
          onSubtitleSelected(idx);
        },
      ),
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
          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          child: Material(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  String _audioLabel(AudioStreamInfo a, int index) {
    final parts = <String>[];
    if (a.title != null && a.title!.isNotEmpty) parts.add(a.title!);
    if (a.language != null && a.language!.isNotEmpty) parts.add(a.language!);
    if (a.codecName != null && a.codecName!.isNotEmpty) parts.add(a.codecName!.toUpperCase());
    if (a.channels > 0) parts.add('${a.channels}ch');
    if (parts.isEmpty) return '音频 ${index + 1}';
    return parts.join(' · ');
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

// ── 字幕选择 + 样式调节面板 ────────────────────────────────

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
    final app = context.read<AppState>();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 字幕轨道选择
          const Text('字幕轨道', style: TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...List.generate(widget.subtitleStreams.length + 1, (i) {
            final isOff = i == 0;
            final isCurrent = isOff
                ? widget.selectedIndex < 0
                : (i - 1) == widget.selectedIndex;
            final label = isOff ? '关闭字幕' : _subtitleLabel(widget.subtitleStreams[i - 1], i - 1);
            return GestureDetector(
              onTap: () => widget.onSelect(isOff ? -1 : i - 1),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (isCurrent)
                      const Icon(Icons.check, color: FnTheme.danmuGreen, size: 16),
                    if (isCurrent) const SizedBox(width: 6),
                    Text(label, style: TextStyle(
                      color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
            );
          }),
          const Divider(color: Colors.white12, height: 32),
          // 字幕样式调节
          const Text('字幕样式', style: TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // 字号
          _styleSlider(
            label: '字号',
            value: app.subtitleSize,
            min: 14, max: 40,
            onChanged: (v) => setState(() => app.subtitleSize = v),
          ),
          // 描边
          _styleSlider(
            label: '描边',
            value: app.subtitleOutline,
            min: 0, max: 4,
            onChanged: (v) => setState(() => app.subtitleOutline = v),
          ),
          // 背景
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 50,
                  child: Text('背景', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: app.subtitleBackground,
                    activeColor: FnTheme.danmuGreen,
                    onChanged: (v) => setState(() => app.subtitleBackground = v),
                  ),
                ),
              ],
            ),
          ),
          // 颜色
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 50,
                  child: Text('颜色', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                ...([0xFFFFFFFF, 0xFFFFFF00, 0xFF00FF00, 0xFF00FFFF, 0xFFFF6600].map((c) =>
                  GestureDetector(
                    onTap: () => setState(() => app.subtitleColorValue = c),
                    child: Container(
                      width: 28, height: 28,
                      margin: const EdgeInsets.only(right: 8),
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
          ),
        ],
      ),
    );
  }

  Widget _styleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required void Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: FnTheme.danmuGreen,
                inactiveTrackColor: Colors.white24,
                thumbColor: FnTheme.danmuGreen,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
            child: Text(
              value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ),
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
