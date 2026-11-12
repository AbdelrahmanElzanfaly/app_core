import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_message_type.dart';

/// How one kind of message looks: its colours, its icon and how long it
/// stays.
@immutable
class AppMessageStyle {
  const AppMessageStyle({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.duration,
  });

  final Color background;

  /// The text, the icon and the action on [background].
  final Color foreground;

  /// Shown beside the text, so the kind never depends on colour alone.
  final IconData icon;

  /// How long the message stays on screen.
  final Duration duration;

  AppMessageStyle copyWith({
    Color? background,
    Color? foreground,
    IconData? icon,
    Duration? duration,
  }) => AppMessageStyle(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    icon: icon ?? this.icon,
    duration: duration ?? this.duration,
  );

  /// Blends the colours; the icon and the duration switch halfway, as they
  /// cannot be blended.
  static AppMessageStyle lerp(AppMessageStyle a, AppMessageStyle b, double t) =>
      AppMessageStyle(
        background: Color.lerp(a.background, b.background, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
        icon: t < 0.5 ? a.icon : b.icon,
        duration: t < 0.5 ? a.duration : b.duration,
      );

  @override
  bool operator ==(Object other) =>
      other is AppMessageStyle &&
      other.background == background &&
      other.foreground == foreground &&
      other.icon == icon &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(background, foreground, icon, duration);
}

/// How each [AppMessageType] looks, set once in the app's `ThemeData`:
///
/// ```dart
/// extensions: [AppMessageTheme.seeded(scheme, success: ..., warning: ...)]
/// ```
///
/// Material's [ColorScheme] has error colours only, so success and warning
/// are derived from their own seeds for the scheme's brightness, the same
/// way a scheme is, which keeps the text readable in light and dark. Each
/// type's icon and duration live here too, so the whole look comes from the
/// theme. A theme without this extension gets [AppMessageTheme.fallback].
@immutable
class AppMessageTheme extends ThemeExtension<AppMessageTheme> {
  const AppMessageTheme({
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    this.iconSpacing = defaultIconSpacing,
  });

  /// Success and warning colours from their seeds; error and info colours
  /// from [scheme] (its error container, and Material's own snack bar
  /// colours). Icons and durations are the defaults below; change one with
  /// `copyWith` on its style.
  factory AppMessageTheme.seeded(
    ColorScheme scheme, {
    required Color success,
    required Color warning,
    double iconSpacing = defaultIconSpacing,
  }) {
    AppMessageStyle tones(Color seed, IconData icon, Duration duration) {
      final tones = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: scheme.brightness,
        // Keeps the seed's hue recognisable: green reads as success, amber
        // as warning.
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      return AppMessageStyle(
        background: tones.primaryContainer,
        foreground: tones.onPrimaryContainer,
        icon: icon,
        duration: duration,
      );
    }

    return AppMessageTheme(
      success: tones(
        success,
        Icons.check_circle_rounded,
        const Duration(seconds: 3),
      ),
      error: AppMessageStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        icon: Icons.error_rounded,
        // Longest: what the user may need to read twice or act on.
        duration: const Duration(seconds: 6),
      ),
      warning: tones(
        warning,
        Icons.warning_amber_rounded,
        const Duration(seconds: 5),
      ),
      info: AppMessageStyle(
        background: scheme.inverseSurface,
        foreground: scheme.onInverseSurface,
        icon: Icons.info_rounded,
        duration: const Duration(seconds: 4),
      ),
      iconSpacing: iconSpacing,
    );
  }

  /// For a theme that sets no [AppMessageTheme]: a test, a preview, an app
  /// that has not chosen its own seeds.
  factory AppMessageTheme.fallback(ColorScheme scheme) =>
      AppMessageTheme.seeded(
        scheme,
        success: defaultSuccessSeed,
        warning: defaultWarningSeed,
      );

  static const Color defaultSuccessSeed = Color(0xFF1E8E3E);
  static const Color defaultWarningSeed = Color(0xFFF9A825);

  /// The gap between the icon and the text when the app sets none.
  static const double defaultIconSpacing = 12;

  final AppMessageStyle success;
  final AppMessageStyle error;
  final AppMessageStyle warning;
  final AppMessageStyle info;

  /// The gap between a message's icon and its text.
  final double iconSpacing;

  AppMessageStyle styleOf(AppMessageType type) => switch (type) {
    AppMessageType.success => success,
    AppMessageType.error => error,
    AppMessageType.warning => warning,
    AppMessageType.info => info,
  };

  /// The theme's own extension, or [AppMessageTheme.fallback] for its
  /// scheme.
  static AppMessageTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppMessageTheme>() ??
        AppMessageTheme.fallback(theme.colorScheme);
  }

  @override
  AppMessageTheme copyWith({
    AppMessageStyle? success,
    AppMessageStyle? error,
    AppMessageStyle? warning,
    AppMessageStyle? info,
    double? iconSpacing,
  }) => AppMessageTheme(
    success: success ?? this.success,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    iconSpacing: iconSpacing ?? this.iconSpacing,
  );

  @override
  AppMessageTheme lerp(AppMessageTheme? other, double t) {
    if (other == null) return this;
    return AppMessageTheme(
      success: AppMessageStyle.lerp(success, other.success, t),
      error: AppMessageStyle.lerp(error, other.error, t),
      warning: AppMessageStyle.lerp(warning, other.warning, t),
      info: AppMessageStyle.lerp(info, other.info, t),
      iconSpacing: lerpDouble(iconSpacing, other.iconSpacing, t)!,
    );
  }
}
