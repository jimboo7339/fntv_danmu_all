class DanmuComment {
  final String text;
  final double time;
  final int color;
  final int type; // 1=scroll, 4=bottom, 5=top
  final double fontSize;

  DanmuComment({
    required this.text,
    required this.time,
    this.color = 0xFFFFFFFF,
    this.type = 1,
    this.fontSize = 0,
  });

  factory DanmuComment.fromJson(Map<String, dynamic> json) {
    int c = 0xFFFFFFFF;
    if (json['color'] != null) {
      if (json['color'] is int) {
        c = json['color'];
      } else if (json['color'] is String) {
        final s = json['color'].toString().replaceAll('#', '');
        if (s.length == 6) c = int.parse('FF$s', radix: 16);
        else if (s.length == 8) c = int.parse(s, radix: 16);
      }
    }
    return DanmuComment(
      text: json['text']?.toString() ?? json['content']?.toString() ?? '',
      time: (json['time'] ?? json['time_point'] ?? 0).toDouble(),
      color: c,
      type: json['type'] ?? 1,
      fontSize: (json['font_size'] ?? 0).toDouble(),
    );
  }
}
