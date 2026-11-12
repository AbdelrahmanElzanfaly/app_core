import 'package:flutter/material.dart';

import 'app_message_type.dart';

/// The colours of one kind of message.
@immutable
class AppMessageStyle {
  const AppMessageStyle({required this.background, required this.foreground});

  final Color background;

  /// The text, the icon and the action on [background].
  final Color foreground;

  static AppMessageStyle lerp(AppMessageStyle a, AppMessageStyle b, double t) =>
      AppMessageStyle(
        background: Color.lerp(a.background, b.background, t)!,
        foreground: Color.lerp(a.foreground, b.foreground, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is AppMessageStyle &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}

/// How each [AppMessageType] looks, set once in the app's `ThemeData`:
///
/// ```dart
/// extensions: [AppMessageTheme.seeded(scheme, success: ..., warning: ...)]
/// ```
///
/// Material's [ColorScheme] has error colours only, so success and warning
/// are derived from their own seeds for the scheme's brightness, the same
/// way a scheme is, which keeps the text readable in light and dark. A theme
/// without this extension gets [AppMessageTheme.fallback].
@immutable
class AppMessageTheme extends ThemeExtension<AppMessageTheme> {
  const AppMessageTheme({
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
  });

  /// Success and warning from their seeds; error and info from [scheme]
  /// (its error container, and Material's own snack bar colours).
  factory AppMessageTheme.seeded(
    ColorScheme scheme, {
    required Color success,
    required Color warning,
  }) {
    AppMessageStyle tones(Color seed) {
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
      );
    }

    return AppMessageTheme(
      success: tones(success),
      error: AppMessageStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ),
      warning: tones(warning),
      info: AppMessageStyle(
        background: scheme.inverseSurface,
        foreground: scheme.onInverseSurface,
      ),
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

  final AppMessageStyle success;
  final AppMessageStyle error;
  final AppMessageStyle warning;
  final AppMessageStyle info;

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
  }) => AppMessageTheme(
    success: success ?? this.success,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    info: info ?? this.info,
  );

  @override
  AppMessageTheme lerp(AppMessageTheme? other, double t) {
    if (other == null) return this;
    return AppMessageTheme(
      success: AppMessageStyle.lerp(success, other.success, t),
      error: AppMessageStyle.lerp(error, other.error, t),
      warning: AppMessageStyle.lerp(warning, other.warning, t),
      info: AppMessageStyle.lerp(info, other.info, t),
    );
  }
}
