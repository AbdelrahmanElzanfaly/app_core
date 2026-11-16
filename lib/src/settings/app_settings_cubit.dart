import 'package:app_network/app_network.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'app_settings_state.dart';

/// Theme and language, persisted across launches.
///
/// Also the [LocaleProvider] the HTTP client reads, so `accept-language`
/// matches the language on screen: see [currentLanguageTag].
class AppSettingsCubit extends Cubit<AppSettingsState>
    implements LocaleProvider {
  AppSettingsCubit() : super(const AppSettingsState());

  String get _themeKey => '${AppConfig.instance.storageKey}.themeMode';
  String get _localeKey => '${AppConfig.instance.storageKey}.locale';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString(_themeKey);
    final locale = prefs.getString(_localeKey);
    emit(
      AppSettingsState(
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == theme,
          orElse: () => ThemeMode.system,
        ),
        locale: locale == null ? null : Locale(locale),
      ),
    );
  }

  Future<void> changeTheme(ThemeMode themeMode) async {
    emit(AppSettingsState(themeMode: themeMode, locale: state.locale));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeMode.name);
  }

  /// Null goes back to the device language.
  Future<void> changeLanguage(Locale? locale) async {
    emit(AppSettingsState(themeMode: state.themeMode, locale: locale));
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }

  /// The language on screen: the chosen one, or the device's while none is
  /// chosen, resolved against [AppConfig.supportedLocales] the way the
  /// framework resolves the app's own locale.
  ///
  /// An app that declares no supported locales sends only a chosen language,
  /// and none while it follows the device.
  @override
  String? currentLanguageTag() {
    final chosen = state.locale;
    final supported = AppConfig.instance.supportedLocales;
    if (supported.isEmpty) return chosen?.toLanguageTag();

    return basicLocaleListResolution(
      chosen == null
          ? WidgetsBinding.instance.platformDispatcher.locales
          : [chosen],
      supported,
    ).toLanguageTag();
  }
}
