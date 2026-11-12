import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    group('fallback, ${brightness.name}', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF0B5CAB),
        brightness: brightness,
      );
      final theme = AppMessageTheme.fallback(scheme);

      test('text on every type meets WCAG AA contrast (4.5:1)', () {
        for (final type in AppMessageType.values) {
          final style = theme.styleOf(type);
          expect(
            _contrast(style.background, style.foreground),
            greaterThan(4.5),
            reason: type.name,
          );
        }
      });

      test('success reads green and warning amber', () {
        expect(
          HSLColor.fromColor(theme.success.background).hue,
          inInclusiveRange(90, 170),
        );
        expect(
          HSLColor.fromColor(theme.warning.background).hue,
          inInclusiveRange(25, 65),
        );
      });

      test('error and info come from the scheme', () {
        expect(theme.error.background, scheme.errorContainer);
        expect(theme.error.foreground, scheme.onErrorContainer);
        expect(theme.info.background, scheme.inverseSurface);
        expect(theme.info.foreground, scheme.onInverseSurface);
      });
    });
  }

  test('seeded uses the given seeds', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final seeded = AppMessageTheme.seeded(
      scheme,
      success: Colors.teal,
      warning: Colors.deepOrange,
    );
    final fallback = AppMessageTheme.fallback(scheme);

    expect(seeded.success, isNot(fallback.success));
    expect(seeded.warning, isNot(fallback.warning));
    expect(seeded.error, fallback.error);
  });

  test('styleOf maps each type to its own style', () {
    final theme = AppMessageTheme.fallback(
      ColorScheme.fromSeed(seedColor: Colors.blue),
    );

    expect(theme.styleOf(AppMessageType.success), same(theme.success));
    expect(theme.styleOf(AppMessageType.error), same(theme.error));
    expect(theme.styleOf(AppMessageType.warning), same(theme.warning));
    expect(theme.styleOf(AppMessageType.info), same(theme.info));
  });

  test('copyWith and lerp', () {
    final light = AppMessageTheme.fallback(
      ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    final dark = AppMessageTheme.fallback(
      ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
    );

    expect(light.copyWith(info: dark.info).info, dark.info);
    expect(light.copyWith(info: dark.info).error, light.error);
    expect(light.lerp(dark, 0).warning, light.warning);
    expect(light.lerp(dark, 1).warning, dark.warning);
    expect(light.lerp(null, 0.5), same(light));
  });

  test('icons, durations and the gap: defaults, copyWith and lerp', () {
    final theme = AppMessageTheme.fallback(
      ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    expect(theme.success.icon, Icons.check_circle_rounded);
    expect(theme.warning.icon, Icons.warning_amber_rounded);
    expect(theme.error.icon, Icons.error_rounded);
    expect(theme.info.icon, Icons.info_rounded);
    expect(theme.success.duration, const Duration(seconds: 3));
    expect(theme.warning.duration, const Duration(seconds: 5));
    expect(theme.error.duration, const Duration(seconds: 6));
    expect(theme.info.duration, const Duration(seconds: 4));
    expect(theme.iconSpacing, AppMessageTheme.defaultIconSpacing);

    final other = theme.copyWith(
      iconSpacing: 20,
      info: theme.info.copyWith(icon: Icons.campaign_rounded),
    );
    expect(other.info.icon, Icons.campaign_rounded);
    expect(other.info.background, theme.info.background);
    expect(theme.lerp(other, 0.5).iconSpacing, 16);
    expect(theme.lerp(other, 0.4).info.icon, theme.info.icon);
    expect(theme.lerp(other, 0.6).info.icon, Icons.campaign_rounded);
    expect(
      AppMessageTheme.seeded(
        ColorScheme.fromSeed(seedColor: Colors.blue),
        success: Colors.green,
        warning: Colors.amber,
        iconSpacing: 8,
      ).iconSpacing,
      8,
    );
  });

  testWidgets('of reads the theme extension, or falls back without one', (
    tester,
  ) async {
    final base = AppMessageTheme.fallback(
      ColorScheme.fromSeed(seedColor: Colors.blue),
    );
    final custom = base.copyWith(
      success: base.success.copyWith(
        background: Colors.black,
        foreground: Colors.white,
      ),
    );
    late AppMessageTheme withExtension;
    late AppMessageTheme without;

    await tester.pumpWidget(
      Column(
        children: [
          Theme(
            data: ThemeData(extensions: [custom]),
            child: Builder(
              builder: (context) {
                withExtension = AppMessageTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
          Theme(
            data: ThemeData(),
            child: Builder(
              builder: (context) {
                without = AppMessageTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );

    expect(withExtension.success.background, Colors.black);
    expect(without.success.background, isNot(Colors.black));
  });
}

/// The WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
