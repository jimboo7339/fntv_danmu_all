import 'package:flutter/foundation.dart';

/// A ring-buffer log collector that captures debugPrint output.
class LogBuffer {
  LogBuffer._();
  static final LogBuffer instance = LogBuffer._();

  final List<LogEntry> _entries = [];
  static const int maxEntries = 2000;
  bool _enabled = false;

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    if (!value) clear();
  }

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(String message) {
    _entries.add(LogEntry(DateTime.now(), message));
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  void clear() => _entries.clear();

  String dump() {
    final buf = StringBuffer();
    for (final e in _entries) {
      buf.writeln('[${e.time.toIso8601String().substring(11, 23)}] ${e.message}');
    }
    return buf.toString();
  }

  /// Install as debugPrint handler so all debugPrint calls are captured.
  void install() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (instance._enabled && message != null && message.isNotEmpty) {
        instance.add(message);
      }
    };
  }
}

class LogEntry {
  final DateTime time;
  final String message;
  LogEntry(this.time, this.message);
}
