import 'package:flutter/material.dart';
import '../models/play_list_item.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

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
  final VoidCallback onPlayPause;
  final void Function(Duration) onSeek;
  final VoidCallback onSpeed;
  final VoidCallback onLock;
  final VoidCallback onDanmu;
  final VoidCallback onBack;
  final void Function(int) onEpisode;
  final void Function(int) onQuality;
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
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeed,
    required this.onLock,
    required this.onDanmu,
    required this.onBack,
    required this.onEpisode,
    required this.onQuality,
    required this.onSeekChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLocked) {
      return const SizedBox.shrink();
    }

    final posMs = position.inMilliseconds.toDouble();
    final durMs = duration.inMilliseconds.toDouble().clamp(1, double.infinity);

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
                    value: posMs.clamp(0, durMs),
                    min: 0,
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
                      _ctrlBtn('${speed}x', onSpeed),
                      // Quality
                      if (qualityCount > 0)
                        _ctrlBtn(qualityLabels.isNotEmpty ? qualityLabels[qualityIndex] : '画质', () {
                          _showQualityMenu(context);
                        }),
                      // Episodes
                      if (episodeList != null && episodeList!.isNotEmpty)
                        _ctrlBtn('选集', () => _showEpisodePicker(context)),
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
      builder: (_) => SizedBox(
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
                      Navigator.pop(context);
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
      builder: (_) => SizedBox(
        height: 250,
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(items[i], style: TextStyle(
              color: i == qualityIndex ? FnTheme.danmuGreen : Colors.white)),
            onTap: () {
              Navigator.pop(context);
              onQuality(i);
            },
          ),
        ),
      ),
    );
  }
}
