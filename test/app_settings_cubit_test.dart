import 'dart:ui' show Locale;

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void configure({
    List<Locale> supported = const [Locale('ar'), Locale('en')],
  }) {
    AppConfig.initialize(
      (environment) => AppConfig(
        environment: environment,
        appName: 'test',
        baseUrl: 'https://api.test',
        applicationId: 'test',
        storageKey: 'test',
        supportedLocales: supported,
      ),
    );
  }

  /// The device's languages, in the user's order of preference.
  void deviceSpeaks(List<Locale> locales) {
    binding.platformDispatcher.localesTestValue = locales;
    addTearDown(binding.platformDispatcher.clearLocalesTestValue);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configure();
  });

  group('the request language', () {
    test('is the chosen language, whatever the device speaks', () async {
      deviceSpeaks(const [Locale('en', 'US')]);
      final settings = AppSettingsCubit();

      await settings.changeLanguage(const Locale('ar'));
      expect(settings.currentLanguageTag(), 'ar');

      await settings.changeLanguage(const Locale('en'));
      expect(settings.currentLanguageTag(), 'en');
    });

    test('is a choice restored from the last launch', () async {
      SharedPreferences.setMockInitialValues({'test.locale': 'en'});
      deviceSpeaks(const [Locale('ar', 'EG')]);
      final settings = AppSettingsCubit();

      await settings.initialize();

      expect(settings.currentLanguageTag(), 'en');
    });

    test('follows an Arabic device of any country', () {
      deviceSpeaks(const [Locale('ar', 'LY')]);

      expect(AppSettingsCubit().currentLanguageTag(), 'ar');
    });

    test('follows an English device', () {
      deviceSpeaks(const [Locale('en', 'GB')]);

      expect(AppSettingsCubit().currentLanguageTag(), 'en');
    });

    test("takes the device's next language when the first has no "
        'translation', () {
      deviceSpeaks(const [Locale('fr', 'FR'), Locale('en', 'US')]);

      expect(AppSettingsCubit().currentLanguageTag(), 'en');
    });

    test('is the first supported language when the device speaks none of '
        'them', () {
      deviceSpeaks(const [Locale('fr', 'FR')]);

      expect(AppSettingsCubit().currentLanguageTag(), 'ar');
    });

    test('follows the device again once the choice is cleared', () async {
      deviceSpeaks(const [Locale('ar', 'EG')]);
      final settings = AppSettingsCubit();
      await settings.changeLanguage(const Locale('en'));

      await settings.changeLanguage(null);

      expect(settings.currentLanguageTag(), 'ar');
    });
  });

  group('with no supported locales declared', () {
    setUp(() => configure(supported: const []));

    test('nothing is sent while the app follows the device', () {
      deviceSpeaks(const [Locale('ar', 'EG')]);

      expect(AppSettingsCubit().currentLanguageTag(), isNull);
    });

    test('a chosen language is sent as it is', () async {
      final settings = AppSettingsCubit();

      await settings.changeLanguage(const Locale('ar'));

      expect(settings.currentLanguageTag(), 'ar');
    });
  });
}
