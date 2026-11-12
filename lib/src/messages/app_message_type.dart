import 'package:flutter/material.dart';

/// What a message reports. Picks its icon and how long it stays; its
/// colours come from `AppMessageTheme`.
enum AppMessageType {
  success(Icons.check_circle_rounded, Duration(seconds: 3)),
  error(Icons.error_rounded, Duration(seconds: 6)),
  warning(Icons.warning_amber_rounded, Duration(seconds: 5)),
  info(Icons.info_rounded, Duration(seconds: 4));

  const AppMessageType(this.icon, this.duration);

  /// Shown beside the text, so the kind never depends on colour alone.
  final IconData icon;

  /// Longer for what the user may need to read twice or act on.
  final Duration duration;
}
