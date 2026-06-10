import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User info card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  child: Icon(Icons.person, size: 30, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.api.baseUrl, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('已连接', style: TextStyle(color: Colors.green[400], fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 弹幕设置
        _sectionTitle('弹幕设置'),
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
        const SizedBox(height: 16),

        // 播放设置
        _sectionTitle('播放设置'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('解码模式'),
                subtitle: Text(app.decoderMode == 'hardware' ? '硬解' : '软解'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDecoderPicker(context, app),
              ),
              ListTile(
                title: const Text('快进步长'),
                subtitle: Text('${app.seekStep} 秒'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSeekStepPicker(context, app),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 弹幕服务器
        _sectionTitle('弹幕服务器'),
        Card(
          child: ListTile(
            title: const Text('弹幕 API 地址'),
            subtitle: Text(app.danmuUrl),
            trailing: const Icon(Icons.edit),
            onTap: () => _editDanmuUrl(context, app),
          ),
        ),
        const SizedBox(height: 16),

        // 关于
        _sectionTitle('关于'),
        Card(
          child: Column(
            children: [
              const ListTile(
                title: Text('版本'),
                subtitle: Text('FnOS TV v1.0.0 (Flutter)'),
              ),
              ListTile(
                title: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  app.logout();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(title, style: const TextStyle(
        color: FnTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
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
              min: min, max: max,
              activeColor: FnTheme.danmuGreen,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 48, child: Text(format(value), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  void _showDecoderPicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('解码模式'),
      children: [
        RadioListTile(value: 'hardware', groupValue: app.decoderMode,
          title: const Text('硬解'), onChanged: (v) { app.decoderMode = v!; Navigator.pop(ctx); }),
        RadioListTile(value: 'software', groupValue: app.decoderMode,
          title: const Text('软解'), onChanged: (v) { app.decoderMode = v!; Navigator.pop(ctx); }),
      ],
    ));
  }

  void _showSeekStepPicker(BuildContext ctx, AppState app) {
    showDialog(context: ctx, builder: (_) => SimpleDialog(
      title: const Text('快进步长'),
      children: [5, 10, 15, 30].map((s) => RadioListTile(
        value: s, groupValue: app.seekStep,
        title: Text('$s 秒'),
        onChanged: (v) { app.seekStep = v!; Navigator.pop(ctx); },
      )).toList(),
    ));
  }

  void _editDanmuUrl(BuildContext ctx, AppState app) {
    final ctrl = TextEditingController(text: app.danmuUrl);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('弹幕 API 地址'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'http://host:9321')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ElevatedButton(onPressed: () { app.danmuUrl = ctrl.text.trim(); Navigator.pop(ctx); }, child: const Text('保存')),
      ],
    ));
  }
}
