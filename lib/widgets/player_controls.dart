import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/play_list_item.dart';
import '../models/danmu_comment.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import '../models/stream_response.dart';
import '../providers/app_state.dart';
import '../services/api_client.dart';
import 'danmu_heatmap.dart';
class PlayerControls extends StatelessWidget {
  final String title;
  final String logoUrl;
  final String headerTitle;
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
  final void Function(bool) onDanmuToggle;
  final VoidCallback onBack;
  final void Function(int) onEpisode;
  final void Function(int) onQuality;
  final void Function(int) onAudioSelected;
  final void Function(int) onSubtitleSelected;
  final void Function(double) onSeekChanged;
  final String showName;
  final Map<String, dynamic>? currentDanmuSource;
  final void Function(Map<String, dynamic>) onDanmuSourceSelected;
  final VoidCallback? onLoadExternalSubtitle;
  final bool useMpv;
  final bool isStrmFile;
  final VoidCallback? onSwitchToMpv;
  final int seekStep;
  final String engineLabel;
  final void Function(String engine) onEngineSelect;
  final String aspectMode;
  final void Function(String) onAspectMode;
  final VoidCallback? onPrevEpisode;
  final VoidCallback? onNextEpisode;
  final bool hasPrevEpisode;
  final bool hasNextEpisode;
  final VoidCallback onRotate;
  final List<DanmuComment> danmuComments;

  const PlayerControls({
    super.key,
    required this.title,
    this.logoUrl = '',
    this.headerTitle = '',
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
    required this.onDanmuToggle,
    required this.onBack,
    required this.onEpisode,
    required this.onQuality,
    required this.onAudioSelected,
    required this.onSubtitleSelected,
    required this.onSeekChanged,
    this.showName = '',
    this.currentDanmuSource,
    required this.onDanmuSourceSelected,
    this.onLoadExternalSubtitle,
    this.useMpv = true,
    this.isStrmFile = false,
    this.onSwitchToMpv,
    this.seekStep = 10,
    this.engineLabel = '',
    required this.onEngineSelect,
    this.aspectMode = 'fit',
    required this.onAspectMode,
    this.onPrevEpisode,
    this.onNextEpisode,
    this.hasPrevEpisode = false,
    this.hasNextEpisode = false,
    required this.onRotate,
    this.danmuComments = const [],
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
          // Top bar — 仅返回 + 弹幕菜单
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: _buildHeaderBrand(context),
                  ),
                  GestureDetector(
                    onTap: () => _showDanmuPanel(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: danmuOn ? FnTheme.danmuGreen.withOpacity(0.28) : Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: danmuOn ? FnTheme.danmuGreen.withOpacity(0.5) : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            danmuOn ? Icons.comment_rounded : Icons.comment_outlined,
                            color: danmuOn ? FnTheme.danmuGreen : Colors.white54,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text('弹幕', style: TextStyle(
                            color: danmuOn ? FnTheme.danmuGreen : Colors.white54,
                            fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                // 进度条上方：内核信息 + 标题
                Row(
                  children: [
                    if (engineLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(engineLabel,
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (danmuComments.isNotEmpty)
                  DanmuHeatmap(
                    comments: danmuComments,
                    duration: duration,
                    position: position,
                    onSeekTap: (ratio) {
                      final ms = (duration.inMilliseconds * ratio).round();
                      onSeekChanged(ms.toDouble());
                    },
                  ),
                if (danmuComments.isNotEmpty) const SizedBox(height: 4),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            children: [
                              if (hasPrevEpisode && onPrevEpisode != null)
                                _iconBtn(Icons.skip_previous_rounded, onPrevEpisode!),
                              GestureDetector(
                                onTap: onPlayPause,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: FnTheme.danmuGreen.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white, size: 26,
                                  ),
                                ),
                              ),
                              if (hasNextEpisode && onNextEpisode != null)
                                _iconBtn(Icons.skip_next_rounded, onNextEpisode!),
                              const SizedBox(width: 4),
                              _ctrlBtn('${seekStep}s', () => onSeek(Duration(seconds: -seekStep))),
                              _ctrlBtn('${seekStep}s', () => onSeek(Duration(seconds: seekStep))),
                              _ctrlBtn('${speed}x', () => _showSpeedMenu(context)),
                              _ctrlBtn(_aspectLabel(aspectMode), () => _showAspectMenu(context)),
                              _ctrlBtn(useMpv ? 'MPV' : 'Exo', () => _showEngineMenu(context)),
                              _ctrlBtn('旋转', onRotate),
                              if (qualityCount > 0)
                                _ctrlBtn(qualityLabels.isNotEmpty ? qualityLabels[qualityIndex] : '画质', () => _showQualityMenu(context)),
                              if (episodeList != null && episodeList!.isNotEmpty)
                                _ctrlBtn('选集', () => _showEpisodePanel(context)),
                              if (audioStreams != null && audioStreams!.length > 1)
                                _ctrlBtn('音频', () => _showAudioMenu(context)),
                              if (subtitleStreams != null && subtitleStreams!.isNotEmpty)
                                _ctrlBtn('字幕', () => _showSubtitlePanel(context))
                              else if (!useMpv && onLoadExternalSubtitle != null)
                                _ctrlBtn('字幕', () => _showSubtitlePanel(context)),
                            ],
                          ),
                        ),
                      ),
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

  Widget _buildHeaderBrand(BuildContext context) {
    final name = headerTitle.isNotEmpty ? headerTitle : title;
    if (logoUrl.isNotEmpty) {
      final headers = context.read<AppState>().api.imageHeaders;
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 28,
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            httpHeaders: headers,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  String _aspectLabel(String mode) {
    switch (mode) {
      case 'fill': return '填充';
      case '16:9': return '16:9';
      case '4:3': return '4:3';
      default: return '适应';
    }
  }

  void _showAspectMenu(BuildContext context) {
    const modes = ['fit', 'fill', '16:9', '4:3'];
    const labels = ['适应屏幕', '填充屏幕', '16:9', '4:3'];
    _showCompactPopup(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(modes.length, (i) {
          final isCurrent = aspectMode == modes[i];
          return GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onAspectMode(modes[i]);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(labels[i], style: TextStyle(
                color: isCurrent ? FnTheme.danmuGreen : Colors.white70,
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              )),
            ),
          );
        }),
      ),
    );
  }

  void _showEngineMenu(BuildContext context) {
    _showCompactPopup(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('播放内核', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          _engineOption(context, 'MPV', useMpv, () {
            Navigator.pop(context);
            if (!useMpv) onEngineSelect('mpv');
          }),
          const SizedBox(height: 6),
          _engineOption(context, 'Exo', !useMpv, () {
            Navigator.pop(context);
            if (useMpv) onEngineSelect('exo');
          }),
          if (isStrmFile)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'strm 直链建议 MPV',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _engineOption(BuildContext context, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        if (!active) onTap();
        else Navigator.pop(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (active) const Icon(Icons.check, color: FnTheme.danmuGreen, size: 14),
            if (active) const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: active ? FnTheme.danmuGreen : Colors.white70,
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
          ],
        ),
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

  void _showBottomPopup(
    BuildContext context, {
    required String title,
    required Widget child,
    double maxHeight = 320,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).padding.bottom;
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 68 + bottom),
            child: Material(
              color: const Color(0xF0181818),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 400, maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 2, 0),
                      child: Row(
                        children: [
                          Text(title, style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 音频 ──────────────────────────────────

  void _showAudioMenu(BuildContext context) {
    if (audioStreams == null || audioStreams!.isEmpty) return;
    _showBottomPopup(
      context,
      title: '音频轨道',
      maxHeight: 260,
      child: _AudioPanel(
        audioStreams: audioStreams!,
        selectedIndex: selectedAudioIndex,
        onSelect: (i) {
          Navigator.pop(context);
          onAudioSelected(i);
        },
      ),
    );
  }

  // ── 字幕 ──────────────────────────────────

  void _showSubtitlePanel(BuildContext context) {
    _showBottomPopup(
      context,
      title: '字幕',
      maxHeight: 360,
      child: _SubtitlePanel(
        subtitleStreams: subtitleStreams ?? [],
        selectedIndex: selectedSubtitleIndex,
        onSelect: (idx) {
          Navigator.pop(context);
          onSubtitleSelected(idx);
        },
        onLoadExternal: onLoadExternalSubtitle != null ? () {
          Navigator.pop(context);
          onLoadExternalSubtitle!();
        } : null,
        useMpv: useMpv,
        isStrmFile: isStrmFile,
        onSwitchToMpv: onSwitchToMpv != null ? () {
          Navigator.pop(context);
          onSwitchToMpv!();
        } : null,
      ),
    );
  }

  // ── 弹幕设置 ──────────────────────────────

  void _showDanmuPanel(BuildContext context) {
    _showBottomPopup(
      context,
      title: '弹幕设置',
      maxHeight: 400,
      child: _DanmuPanel(
        showName: showName,
        currentDanmuSource: currentDanmuSource,
        danmuOn: danmuOn,
        onDanmuToggle: (v) {
          onDanmuToggle(v);
        },
        onSourceSelected: (data) {
          Navigator.pop(context);
          onDanmuSourceSelected(data);
        },
      ),
    );
  }

  // ── 选集 ──────────────────────────────────

  void _showEpisodePanel(BuildContext context) {
    if (episodeList == null || episodeList!.isEmpty) return;
    _showBottomPopup(
      context,
      title: '选集 (${episodeList!.length})',
      maxHeight: 300,
      child: _EpisodePanel(
        episodeList: episodeList!,
        currentEpIndex: currentEpIndex,
        onSelect: (i) {
          Navigator.pop(context);
          onEpisode(i);
        },
      ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(audioStreams.length, (i) {
        final a = audioStreams[i];
        final isCurrent = i == selectedIndex;
        final label = _audioLabelStatic(a, i);
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isCurrent ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.3)) : null,
            ),
            child: Row(
              children: [
                Icon(isCurrent ? Icons.check_circle : Icons.circle_outlined,
                  color: isCurrent ? FnTheme.danmuGreen : Colors.white38, size: 16),
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
  final VoidCallback? onLoadExternal;
  final bool useMpv;
  final bool isStrmFile;
  final VoidCallback? onSwitchToMpv;

  const _SubtitlePanel({
    required this.subtitleStreams,
    required this.selectedIndex,
    required this.onSelect,
    this.onLoadExternal,
    this.useMpv = true,
    this.isStrmFile = false,
    this.onSwitchToMpv,
  });

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<_SubtitlePanel> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.useMpv && widget.isStrmFile && widget.subtitleStreams.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '网盘串流 (strm) 无法用 Exo 加载内嵌字幕',
                        style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '请切换 MPV 内核，由播放器本地解析 mov_text 字幕。',
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                ),
                if (widget.onSwitchToMpv != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onSwitchToMpv,
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('切换 MPV 并加载字幕', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FnTheme.danmuGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const Text('字幕轨道', style: TextStyle(
          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ...List.generate(widget.subtitleStreams.length + 1, (i) {
          final isOff = i == 0;
          final isCurrent = isOff
              ? widget.selectedIndex < 0
              : (i - 1) == widget.selectedIndex;
          final label = isOff ? '关闭字幕' : _subtitleLabel(widget.subtitleStreams[i - 1], i - 1);
          return GestureDetector(
            onTap: () => widget.onSelect(isOff ? -1 : i - 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  Icon(isCurrent ? Icons.check_circle : Icons.circle_outlined,
                    color: isCurrent ? FnTheme.danmuGreen : Colors.white38, size: 16),
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
        if (widget.onLoadExternal != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: widget.onLoadExternal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.file_open_rounded, color: FnTheme.danmuGreen, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.subtitleStreams.isEmpty
                          ? '加载外部字幕 (SRT/VTT)'
                          : '加载外部字幕',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
        ],
        const Divider(color: Colors.white12, height: 20),
        const Text('字幕样式', style: TextStyle(
          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _styleSlider('字号', app.subtitleSize, 14, 40, (v) => setState(() => app.subtitleSize = v)),
        _styleSlider('粗细', app.subtitleWeight, 100, 900, (v) => setState(() => app.subtitleWeight = v), _weightLabel(app.subtitleWeight)),
        _styleSlider('描边', app.subtitleOutline, 0, 4, (v) => setState(() => app.subtitleOutline = v)),
        _switchRow('背景', app.subtitleBackground, (v) => setState(() => app.subtitleBackground = v)),
        _styleSlider('底部边距', app.subtitleBottomMargin, -100, 200, (v) => setState(() => app.subtitleBottomMargin = v), '${app.subtitleBottomMargin.toInt()}px'),
        _colorRow(app),
      ],
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
  final String showName;
  final Map<String, dynamic>? currentDanmuSource;
  final bool danmuOn;
  final ValueChanged<bool> onDanmuToggle;
  final void Function(Map<String, dynamic>) onSourceSelected;

  const _DanmuPanel({
    required this.showName,
    this.currentDanmuSource,
    required this.danmuOn,
    required this.onDanmuToggle,
    required this.onSourceSelected,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('开启弹幕', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: danmuOn,
          activeColor: FnTheme.danmuGreen,
          onChanged: onDanmuToggle,
        ),
        const Divider(color: Colors.white12, height: 12),
        _buildSourceCard(context, app),
        const Divider(color: Colors.white12, height: 12),
        _slider('字号', app.danmuFontSize, 14, 36, (v) => app.danmuFontSize = v, '${app.danmuFontSize.toInt()}'),
        _slider('速度', app.danmuSpeed, 0.1, 2.0, (v) => app.danmuSpeed = v, '${app.danmuSpeed.toStringAsFixed(1)}x'),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            '1.0 ≈ 14 秒横穿 · 越小越慢',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10),
          ),
        ),
        _slider('透明度', app.danmuOpacity, 0.1, 1.0, (v) => app.danmuOpacity = v, '${(app.danmuOpacity * 100).toInt()}%'),
        _slider('区域', app.danmuArea.toDouble(), 10, 100, (v) => app.danmuArea = v.toInt(), '${app.danmuArea}%'),
        _slider('顶部边距', app.danmuTopMargin, -100, 200, (v) => app.danmuTopMargin = v, '${app.danmuTopMargin.toInt()}px'),
        _slider('密度', app.danmuDensity.toDouble(), 10, 100, (v) => app.danmuDensity = v.toInt(), '${app.danmuDensity}%'),
        const Divider(color: Colors.white12, height: 12),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('文字描边', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: app.danmuOutline,
          activeColor: FnTheme.danmuGreen,
          onChanged: (v) => app.danmuOutline = v,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('防止重叠', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: app.danmuAntiOverlap,
          activeColor: FnTheme.danmuGreen,
          onChanged: (v) => app.danmuAntiOverlap = v,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('合并重复', style: TextStyle(color: Colors.white, fontSize: 13)),
          value: app.danmuMergeDuplicates,
          activeColor: FnTheme.danmuGreen,
          onChanged: (v) => app.danmuMergeDuplicates = v,
        ),
      ],
    );
  }

  Widget _buildSourceCard(BuildContext context, AppState app) {
    final hasSource = currentDanmuSource != null;
    final animeName = currentDanmuSource?['animeName']?.toString() ?? '';
    final commentCount = currentDanmuSource?['commentCount'] ?? 0;
    final epNum = currentDanmuSource?['episodeNumber'] ?? 0;
    return GestureDetector(
      onTap: () => _showDanmuSearch(context, app),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasSource ? FnTheme.danmuGreen.withOpacity(0.08) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasSource ? FnTheme.danmuGreen.withOpacity(0.3) : Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              hasSource ? Icons.check_circle : Icons.search,
              color: hasSource ? FnTheme.danmuGreen : Colors.white38,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: hasSource
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(animeName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('第${epNum}集 · $commentCount 条弹幕',
                        style: TextStyle(color: FnTheme.danmuGreen.withOpacity(0.8), fontSize: 11)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(showName.isNotEmpty ? '未匹配到弹幕' : '未知剧集',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 2),
                      const Text('点击手动搜索弹幕源', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  void _showDanmuSearch(BuildContext context, AppState app) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'danmu-search',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return FadeTransition(
          opacity: anim,
          child: _DanmuSearchDialog(
            showName: showName,
            danmuUrl: app.danmuUrl,
            api: app.api,
            onSelect: (data) => onSourceSelected(data),
          ),
        );
      },
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
}

// ── 弹幕搜索对话框 ──────────────────────────────────────────

class _DanmuSearchDialog extends StatefulWidget {
  final String showName;
  final String danmuUrl;
  final ApiClient api;
  final void Function(Map<String, dynamic>) onSelect;

  const _DanmuSearchDialog({
    required this.showName,
    required this.danmuUrl,
    required this.api,
    required this.onSelect,
  });

  @override
  State<_DanmuSearchDialog> createState() => _DanmuSearchDialogState();
}

class _DanmuSearchDialogState extends State<_DanmuSearchDialog> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String _error = '';
  List<Map<String, dynamic>> _animeResults = [];
  
  // 当前选中的动画
  Map<String, dynamic>? _selectedAnime;
  List<Map<String, dynamic>> _episodeResults = [];
  bool _loadingEpisodes = false;

  @override
  void initState() {
    super.initState();
    if (widget.showName.isNotEmpty) {
      _searchCtrl.text = widget.showName;
      _doSearch();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty || widget.danmuUrl.isEmpty) return;
    setState(() { _searching = true; _error = ''; _animeResults = []; _selectedAnime = null; _episodeResults = []; });
    try {
      final resp = await widget.api.dio.get(
        '${widget.danmuUrl}/api/v2/search/anime',
        queryParameters: {'keyword': kw},
      );
      if (resp.statusCode != 200 || resp.data == null) {
        setState(() { _error = '搜索失败'; _searching = false; });
        return;
      }
      final raw = resp.data;
      List<dynamic> results = [];
      if (raw is List) results = raw;
      else if (raw is Map && raw['animes'] is List) results = raw['animes'] as List;
      else if (raw is Map && raw['data'] is List) results = raw['data'] as List;
      setState(() {
        _animeResults = results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _searching = false;
        if (_animeResults.isEmpty) _error = '未找到结果';
      });
    } catch (e) {
      setState(() { _error = '搜索出错: \$e'; _searching = false; });
    }
  }

  Future<void> _loadEpisodes(Map<String, dynamic> anime) async {
    final animeId = anime['animeId'] ?? anime['id'] ?? anime['bangumiId'] ?? 0;
    if (animeId == 0) return;
    setState(() { _selectedAnime = anime; _loadingEpisodes = true; _episodeResults = []; });
    try {
      final resp = await widget.api.dio.get('${widget.danmuUrl}/api/v2/bangumi/$animeId');
      if (resp.statusCode != 200 || resp.data == null) {
        setState(() { _loadingEpisodes = false; });
        return;
      }
      final bData = resp.data;
      List<dynamic> episodes = [];
      if (bData is Map) {
        if (bData['bangumi'] is Map && bData['bangumi']['episodes'] is List)
          episodes = bData['bangumi']['episodes'] as List;
        else if (bData['episodes'] is List)
          episodes = bData['episodes'] as List;
      }
      setState(() {
        _episodeResults = episodes.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loadingEpisodes = false;
      });
    } catch (e) {
      setState(() { _loadingEpisodes = false; });
    }
  }

  void _selectEpisode(Map<String, dynamic> ep) {
    final animeName = _selectedAnime?['animeName'] ?? _selectedAnime?['name'] ?? _searchCtrl.text;
    final episodeId = ep['episodeId'] ?? ep['id'] ?? 0;
    final episodeNumber = ep['episodeNumber'] ?? ep['episodeIndex'] ?? 0;
    final commentCount = ep['commentCount'] ?? 0;
    final animeId = _selectedAnime?['animeId'] ?? _selectedAnime?['id'] ?? 0;
    widget.onSelect({
      'animeId': animeId,
      'animeName': animeName,
      'episodeId': episodeId,
      'episodeNumber': episodeNumber is String ? int.tryParse(episodeNumber) ?? 0 : episodeNumber,
      'commentCount': commentCount,
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final dialogW = screenW * 0.5;
    return Center(
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: dialogW.clamp(320.0, 500.0),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    if (_selectedAnime != null)
                      GestureDetector(
                        onTap: () => setState(() { _selectedAnime = null; _episodeResults = []; }),
                        child: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                      ),
                    if (_selectedAnime != null) const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedAnime != null
                          ? '${_selectedAnime!['animeName'] ?? _selectedAnime!['name'] ?? ''}'
                          : '搜索弹幕源',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // 搜索框（只在动画列表模式显示）
              if (_selectedAnime == null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '输入剧名搜索...',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _doSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _doSearch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: FnTheme.danmuGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _searching
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('搜索', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              // 内容区
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedAnime == null) {
      // 动画搜索结果列表
      if (_error.isNotEmpty) return Center(child: Text(_error, style: const TextStyle(color: Colors.white54)));
      if (_animeResults.isEmpty && !_searching) {
        return const Center(child: Text('输入关键词搜索弹幕源', style: TextStyle(color: Colors.white38)));
      }
      return ListView.builder(
        itemCount: _animeResults.length,
        itemBuilder: (_, i) {
          final anime = _animeResults[i];
          final name = anime['animeName'] ?? anime['name'] ?? '未知';
          final epCount = anime['episodeCount'] ?? anime['epsCount'] ?? '?';
          final imageUrl = anime['imageUrl'] ?? anime['image'] ?? '';
          return GestureDetector(
            onTap: () => _loadEpisodes(anime),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                            const Icon(Icons.movie, color: Colors.white38, size: 20)),
                        )
                      : const Icon(Icons.movie, color: Colors.white38, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('$epCount 集', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // 剧集列表
      if (_loadingEpisodes) return const Center(child: CircularProgressIndicator(color: FnTheme.danmuGreen));
      if (_episodeResults.isEmpty) return const Center(child: Text('没有找到剧集', style: TextStyle(color: Colors.white54)));
      return ListView.builder(
        itemCount: _episodeResults.length,
        itemBuilder: (_, i) {
          final ep = _episodeResults[i];
          final epNum = ep['episodeNumber'] ?? ep['episodeIndex'] ?? (i + 1);
          final epTitle = ep['episodeTitle'] ?? ep['title'] ?? '第\$epNum集';
          final commentCount = ep['commentCount'] ?? 0;
          return GestureDetector(
            onTap: () => _selectEpisode(ep),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FnTheme.danmuGreen.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('$epNum', style: TextStyle(color: FnTheme.danmuGreen, fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(epTitle, style: const TextStyle(color: Colors.white, fontSize: 13),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('$commentCount 条弹幕', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.download, color: Colors.white38, size: 18),
                ],
              ),
            ),
          );
        },
      );
    }
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(episodeList.length, (i) {
        final ep = episodeList[i];
        final isCurrent = i == currentEpIndex;
        return GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isCurrent ? FnTheme.danmuGreen.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isCurrent
                  ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.3))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrent ? FnTheme.danmuGreen : Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${ep.episodeNumber > 0 ? ep.episodeNumber : i + 1}',
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ep.title ?? '第${ep.episodeNumber > 0 ? ep.episodeNumber : i + 1}集',
                    style: TextStyle(
                      color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrent)
                  const Icon(Icons.play_circle_filled, color: FnTheme.danmuGreen, size: 18),
              ],
            ),
          ),
        );
      }),
    );
  }
}
