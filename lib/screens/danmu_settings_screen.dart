import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';

class DanmuSettingsScreen extends StatelessWidget {
  const DanmuSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('弹幕设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 显示设置
          _sectionTitle('显示设置'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('开启弹幕'),
                  value: app.danmuOn,
                  onChanged: (v) => app.danmuOn = v,
                  activeColor: FnTheme.danmuGreen,
                ),
                _sliderTile('弹幕不透明度', app.danmuOpacity, 0.1, 1.0,
                    (v) => app.danmuOpacity = v, (v) => '${(v * 100).toInt()}%'),
                _sliderTile('弹幕字号', app.danmuFontSize, 14, 36,
                    (v) => app.danmuFontSize = v, (v) => '${v.toInt()}'),
                _sliderTile('显示区域', app.danmuArea.toDouble(), 10, 100,
                    (v) => app.danmuArea = v.toInt(), (v) => '${v.toInt()}%'),
                _sliderTile('弹幕速度', app.danmuSpeed, 0.5, 2.0,
                    (v) => app.danmuSpeed = v, (v) => '${v.toStringAsFixed(1)}x'),
                _sliderTile('弹幕密度', app.danmuDensity.toDouble(), 10, 100,
                    (v) => app.danmuDensity = v.toInt(), (v) => '${v.toInt()}%'),
                SwitchListTile(
                  title: const Text('文字描边'),
                  value: app.danmuOutline,
                  onChanged: (v) => app.danmuOutline = v,
                  activeColor: FnTheme.danmuGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 弹幕类型
          _sectionTitle('弹幕类型'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('滚动弹幕'),
                  value: app.danmuScroll,
                  onChanged: (v) => app.danmuScroll = v,
                  activeColor: FnTheme.danmuGreen,
                ),
                SwitchListTile(
                  title: const Text('顶部弹幕'),
                  value: app.danmuTop,
                  onChanged: (v) => app.danmuTop = v,
                  activeColor: FnTheme.danmuGreen,
                ),
                SwitchListTile(
                  title: const Text('底部弹幕'),
                  value: app.danmuBottom,
                  onChanged: (v) => app.danmuBottom = v,
                  activeColor: FnTheme.danmuGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title,
          style: const TextStyle(
              color: FnTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _sliderTile(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String Function(double) format) {
    return ListTile(
      title: Text(label),
      subtitle: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: FnTheme.danmuGreen,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
              width: 48,
              child: Text(format(value), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
