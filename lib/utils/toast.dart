import 'package:flutter/material.dart';
import 'theme.dart';

enum FnToastType { info, success, warning, error }

/// 统一浮动提示，替代默认 SnackBar 样式。
class FnToast {
  static void show(
    BuildContext context,
    String message, {
    FnToastType type = FnToastType.info,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: const Color(0xEE1E1E1E),
        elevation: 8,
        duration: duration,
        content: Row(
          children: [
            Icon(_icon(type), color: _color(type), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
              ),
            ),
          ],
        ),
        action: actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: FnTheme.danmuGreen,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );
  }

  static IconData _icon(FnToastType type) {
    switch (type) {
      case FnToastType.success:
        return Icons.check_circle_rounded;
      case FnToastType.warning:
        return Icons.warning_amber_rounded;
      case FnToastType.error:
        return Icons.error_outline_rounded;
      case FnToastType.info:
        return Icons.info_outline_rounded;
    }
  }

  static Color _color(FnToastType type) {
    switch (type) {
      case FnToastType.success:
        return FnTheme.danmuGreen;
      case FnToastType.warning:
        return Colors.orangeAccent;
      case FnToastType.error:
        return Colors.redAccent;
      case FnToastType.info:
        return Colors.white70;
    }
  }
}
