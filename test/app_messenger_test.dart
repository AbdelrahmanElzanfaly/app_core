import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B5CAB));
  final messages = AppMessageTheme.fallback(scheme);
  late BuildContext page;

  Future<void> pumpPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ThemeData(colorScheme: scheme, extensions: [messages]),
      locale: locale,
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        CoreLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: Scaffold(
        body: Builder(
          builder: (context) {
            page = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );

  SnackBar shown(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar));

  group('AppMessenger', () {
    final shows = <AppMessageType, void Function(BuildContext, String)>{
      AppMessageType.success: (c, m) => c.showSuccess(m),
      AppMessageType.error: (c, m) => c.showError(m),
      AppMessageType.warning: (c, m) => c.showWarning(m),
      AppMessageType.info: (c, m) => c.showInfo(m),
    };

    for (final MapEntry(key: type, value: show) in shows.entries) {
      testWidgets('${type.name}: theme colours, icon and duration', (
        tester,
      ) async {
        await pumpPage(tester);

        show(page, 'Saved');
        await tester.pump();

        final style = messages.styleOf(type);
        expect(shown(tester).backgroundColor, style.background);
        expect(shown(tester).duration, style.duration);
        expect(shown(tester).action, isNull);
        expect(
          tester.widget<Text>(find.text('Saved')).style?.color,
          style.foreground,
        );
        expect(
          tester.widget<Icon>(find.byIcon(style.icon)).color,
          style.foreground,
        );
      });
    }

    test('by default every type has its own icon, and errors stay longest', () {
      final styles = AppMessageType.values.map(messages.styleOf);
      expect(
        styles.map((style) => style.icon).toSet(),
        hasLength(AppMessageType.values.length),
      );
      for (final style in styles) {
        expect(style.duration, lessThanOrEqualTo(messages.error.duration));
      }
    });

    testWidgets('the icon, the duration and the gap come from the theme', (
      tester,
    ) async {
      final custom = messages.copyWith(
        success: messages.success.copyWith(
          icon: Icons.thumb_up_rounded,
          duration: const Duration(seconds: 9),
        ),
        iconSpacing: 20,
      );
      await pumpPage(
        tester,
        theme: ThemeData(colorScheme: scheme, extensions: [custom]),
      );

      page.showSuccess('Saved');
      await tester.pump();

      expect(find.byIcon(Icons.thumb_up_rounded), findsOneWidget);
      expect(find.byIcon(messages.success.icon), findsNothing);
      expect(shown(tester).duration, const Duration(seconds: 9));
      // The gap is the only box with a width and no height; the icon has
      // its own sized box.
      final gap = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(AppMessageContent),
              matching: find.byType(SizedBox),
            ),
          )
          .singleWhere((box) => box.height == null);
      expect(gap.width, 20);
    });

    testWidgets('an action shows in the message colour and runs', (
      tester,
    ) async {
      var retried = 0;
      await pumpPage(tester);

      page.showError('Failed', actionLabel: 'Retry', onAction: () => retried++);
      // Settled: a snack bar ignores taps while it slides in.
      await tester.pumpAndSettle();

      expect(shown(tester).action?.textColor, messages.error.foreground);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('a new message replaces the one on screen', (tester) async {
      await pumpPage(tester);

      page.showSuccess('First');
      await tester.pump();
      page.showWarning('Second');
      await tester.pumpAndSettle();

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('the icon sits at the start in a right-to-left layout', (
      tester,
    ) async {
      await pumpPage(tester, locale: const Locale('ar'));

      page.showWarning('Warning');
      await tester.pump();

      expect(
        tester.getCenter(find.byIcon(messages.warning.icon)).dx,
        greaterThan(tester.getCenter(find.text('Warning')).dx),
      );
    });

    testWidgets('a theme without the extension uses the fallback', (
      tester,
    ) async {
      await pumpPage(tester, theme: ThemeData(colorScheme: scheme));

      page.showSuccess('Saved');
      await tester.pump();

      expect(shown(tester).backgroundColor, messages.success.background);
    });

    testWidgets('does nothing without a ScaffoldMessenger', (tester) async {
      late BuildContext bare;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              bare = context;
              return const SizedBox();
            },
          ),
        ),
      );

      bare.showError('Nowhere to show');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('StateView', () {
    late _Bloc bloc;

    setUp(() => bloc = _Bloc());
    tearDown(() => bloc.close());

    for (final (locale, copy) in [
      (const Locale('en'), 'No connection. Check the network and try again.'),
      (const Locale('ar'), 'لا يوجد اتصال. تحقّق من الشبكة وحاول مرة أخرى.'),
    ]) {
      testWidgets(
        'shows a failure as an error message (${locale.languageCode})',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: scheme, extensions: [messages]),
              locale: locale,
              localizationsDelegates: const [
                ...GlobalMaterialLocalizations.delegates,
                CoreLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en'), Locale('ar')],
              home: Scaffold(
                body: StateView<_Bloc>(bloc: bloc, child: const SizedBox()),
              ),
            ),
          );

          bloc.handleError(const AppFailure(FailureType.network));
          await tester.pump();

          expect(find.text(copy), findsOneWidget);
          expect(find.byIcon(messages.error.icon), findsOneWidget);
          expect(shown(tester).backgroundColor, messages.error.background);
          expect(shown(tester).duration, messages.error.duration);
        },
      );
    }
  });
}

class _Bloc extends BaseBloc<Object, int> {
  _Bloc() : super(0);
}
