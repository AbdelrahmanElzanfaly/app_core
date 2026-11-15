import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

/// App-wide preferences: theme and language.
class AppSettingsState extends Equatable {
  const AppSettingsState({this.themeMode = ThemeMode.system, this.locale});

  final ThemeMode themeMode;

  /// Null follows the device language.
  final Locale? locale;

  @override
  List<Object?> get props => [themeMode, locale];
}
