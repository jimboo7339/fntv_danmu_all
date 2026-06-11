import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/play_list_item.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import '../models/stream_response.dart';

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
  final int selectedSubtitleIndex; // -1 = off
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
    if (isLocked) {
      return const SizedBox.shrink();
    }

    final posMs = position.inMilliseconds.toDouble();
    final durMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();

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
                  // Danmu toggle
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
                // Seek bar
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
                    value: posMs.clamp(0.0, durMs).toDouble(),
                    min: 0.0,
                    max: durMs,
                    onChanged: onSeekChanged,
                  ),
                ),
                // Time + controls
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      // Time
                      Text(
                        '${formatDuration(position.inSeconds)} / ${formatDuration(duration.inSeconds)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      // Rewind
                      _ctrlBtn('10秒', () => onSeek(const Duration(seconds: -10))),
                      // Play/Pause
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
                      // Forward
                      _ctrlBtn('10秒', () => onSeek(const Duration(seconds: 10))),
                      const SizedBox(width: 8),
                      // Speed
                      _ctrlBtn('${speed}x', () => _showSpeedPicker(context)),
                      // Quality
                      if (qualityCount > 0)
                        _ctrlBtn(qualityLabels.isNotEmpty ? qualityLabels[qualityIndex] : '画质', () {
                          _showQualityMenu(context);
                        }),
                      // Episodes
                      if (episodeList != null && episodeList!.isNotEmpty)
                        _ctrlBtn('选集', () => _showEpisodePicker(context)),
                      // Audio track
                      if (audioStreams != null && audioStreams!.length > 1)
                        _ctrlBtn('音频', () => _showAudioPicker(context)),
                      // Subtitle track
                      if (subtitleStreams != null && subtitleStreams!.isNotEmpty)
                        _ctrlBtn('字幕', () => _showSubtitlePicker(context)),
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

  void _showEpisodePicker(BuildContext context) {
    if (episodeList == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SizedBox(
        height: 300,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择剧集', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: episodeList!.length,
                itemBuilder: (_, i) {
                  final ep = episodeList![i];
                  final isCurrent = i == currentEpIndex;
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: FnTheme.danmuGreen.withOpacity(0.15),
                    title: Text(
                      'EP${ep.episodeNumber > 0 ? ep.episodeNumber : i + 1}  ${ep.title ?? ''}',
                      style: TextStyle(
                        color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onEpisode(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQualityMenu(BuildContext context) {
    final items = <String>[];
    for (int i = 0; i < qualityCount; i++) {
      items.add((i == qualityIndex ? '✓ ' : '  ') + qualityLabels[i]);
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SizedBox(
        height: 250,
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(items[i], style: TextStyle(
              color: i == qualityIndex ? FnTheme.danmuGreen : Colors.white)),
            onTap: () {
              Navigator.pop(sheetContext);
              onQuality(i);
            },
          ),
        ),
      ),
    );
  }

  void _showSpeedPicker(BuildContext context) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SizedBox(
        height: 300,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('播放倍速', style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: speeds.length,
                itemBuilder: (_, i) {
                  final s = speeds[i];
                  final isCurrent = (s - speed).abs() < 0.01;
                  return ListTile(
                    autofocus: isCurrent,
                    title: Text(
                      s == 1.0 ? '1.0x  正常' : '${s}x',
                      style: TextStyle(
                        color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check, color: FnTheme.danmuGreen)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onSpeed(s);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioPicker(BuildContext context) {
    if (audioStreams == null || audioStreams!.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SizedBox(
        height: 300,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('音频轨道', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: audioStreams!.length,
                itemBuilder: (_, i) {
                  final a = audioStreams![i];
                  final isCurrent = i == selectedAudioIndex;
                  final label = _audioLabel(a, i);
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: FnTheme.danmuGreen.withOpacity(0.15),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check, color: FnTheme.danmuGreen)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onAudioSelected(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubtitlePicker(BuildContext context) {
    if (subtitleStreams == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SizedBox(
        height: 300,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('字幕轨道', style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: subtitleStreams!.length + 1,
                itemBuilder: (_, i) {
                  final isOff = i == 0;
                  final isCurrent = isOff
                      ? selectedSubtitleIndex < 0
                      : (i - 1) == selectedSubtitleIndex;
                  String label;
                  if (isOff) {
                    label = '关闭字幕';
                  } else {
                    label = _subtitleLabel(subtitleStreams![i - 1], i - 1);
                  }
                  return ListTile(
                    selected: isCurrent,
                    selectedTileColor: FnTheme.danmuGreen.withOpacity(0.15),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isCurrent ? FnTheme.danmuGreen : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check, color: FnTheme.danmuGreen)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onSubtitleSelected(isOff ? -1 : i - 1);
                    },
                  );
                },
              ),
            ),
          ],
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
