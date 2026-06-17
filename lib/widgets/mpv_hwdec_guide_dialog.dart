import 'package:flutter/material.dart';
import '../models/mpv_player_settings.dart';
import '../utils/theme.dart';

/// 硬件解码器说明与选择弹窗
Future<void> showMpvHwdecGuideDialog(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onSelect,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => _MpvHwdecGuideDialog(
      current: current,
      onSelect: (v) {
        onSelect(v);
        Navigator.pop(ctx);
      },
    ),
  );
}

class _MpvHwdecGuideDialog extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;

  const _MpvHwdecGuideDialog({
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  _buildConceptCard(),
                  const SizedBox(height: 12),
                  ...MpvPlayerSettings.hwdecDetails.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HwdecOptionCard(
                        detail: d,
                        selected: d.value == current,
                        onSelect: () => onSelect(d.value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '修改后需重新进入播放页生效',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: FnTheme.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Icon(Icons.memory_rounded, color: FnTheme.danmuGreen.withOpacity(0.9), size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('硬件解码器说明', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text(
                  '了解区别后可直接点选应用',
                  style: TextStyle(fontSize: 12, color: FnTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildConceptCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FnTheme.danmuGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FnTheme.danmuGreen.withOpacity(0.2)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('什么是「拷贝」？', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          SizedBox(height: 8),
          Text(
            '硬解后画面可以直出屏幕（快），也可以先回拷到内存再由 MPV 处理（稳）。\n'
            '名称带「拷贝 / copy」的选项会回拷内存，音画同步和内嵌字幕通常更可靠。',
            style: TextStyle(fontSize: 12, color: FnTheme.textSecondary, height: 1.5),
          ),
          SizedBox(height: 10),
          _FlowRow(
            steps: ['芯片硬解', '回拷内存', 'MPV 合成', '屏幕'],
            highlight: [1, 2],
          ),
          SizedBox(height: 8),
          _FlowRow(
            steps: ['芯片硬解', '直出屏幕'],
            highlight: [],
            muted: true,
          ),
          SizedBox(height: 6),
          Text(
            '上行：拷贝模式（推荐云直链）　下行：直出模式（快但易漂移）',
            style: TextStyle(fontSize: 10, color: FnTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final List<String> steps;
  final List<int> highlight;
  final bool muted;

  const _FlowRow({
    required this.steps,
    required this.highlight,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Icon(Icons.arrow_forward_rounded, size: 12,
                color: muted ? FnTheme.textMuted : FnTheme.textSecondary),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: highlight.contains(i)
                  ? FnTheme.danmuGreen.withOpacity(0.15)
                  : (muted ? const Color(0xFF252525) : const Color(0xFF2A2A2A)),
              borderRadius: BorderRadius.circular(6),
              border: highlight.contains(i)
                  ? Border.all(color: FnTheme.danmuGreen.withOpacity(0.35))
                  : null,
            ),
            child: Text(
              steps[i],
              style: TextStyle(
                fontSize: 11,
                color: muted ? FnTheme.textMuted : FnTheme.textPrimary,
                fontWeight: highlight.contains(i) ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HwdecOptionCard extends StatelessWidget {
  final HwdecOptionDetail detail;
  final bool selected;
  final VoidCallback onSelect;

  const _HwdecOptionCard({
    required this.detail,
    required this.selected,
    required this.onSelect,
  });

  Color get _badgeColor => switch (detail.badge) {
        HwdecBadge.recommended => FnTheme.danmuGreen,
        HwdecBadge.neutral => const Color(0xFF64B5F6),
        HwdecBadge.caution => const Color(0xFFFFB74D),
        HwdecBadge.fallback => FnTheme.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FnTheme.danmuGreen.withOpacity(0.1) : const Color(0xFF222222),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? FnTheme.danmuGreen.withOpacity(0.55) : const Color(0xFF333333),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? FnTheme.danmuGreen : FnTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detail.shortDesc,
                          style: const TextStyle(fontSize: 12, color: FnTheme.textSecondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BadgeChip(text: detail.badgeText, color: _badgeColor),
                ],
              ),
              const SizedBox(height: 10),
              _BulletSection(icon: Icons.check_circle_outline, color: FnTheme.danmuGreen, title: '优点', items: detail.pros),
              const SizedBox(height: 6),
              _BulletSection(icon: Icons.info_outline, color: const Color(0xFFFFB74D), title: '注意', items: detail.cons),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 14, color: FnTheme.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '适合：${detail.scenario}',
                        style: const TextStyle(fontSize: 11, color: FnTheme.textMuted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: FnTheme.danmuGreen),
                    const SizedBox(width: 6),
                    Text('当前使用中', style: TextStyle(fontSize: 12, color: FnTheme.danmuGreen.withOpacity(0.95))),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '点击选用',
                    style: TextStyle(fontSize: 12, color: FnTheme.danmuGreen.withOpacity(0.85)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String text;
  final Color color;

  const _BadgeChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _BulletSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;

  const _BulletSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map((t) => Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('· ', style: TextStyle(fontSize: 12, color: FnTheme.textMuted)),
                  Expanded(child: Text(t, style: const TextStyle(fontSize: 11, color: FnTheme.textSecondary, height: 1.35))),
                ],
              ),
            )),
      ],
    );
  }
}
