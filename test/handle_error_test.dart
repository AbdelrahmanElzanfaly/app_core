import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const failure = AppFailure(FailureType.network);

  group('BaseBloc.handleError', () {
    late _Bloc bloc;
    late List<AppFailure> published;
    late StreamSubscription<AppFailure> subscription;

    setUp(() {
      bloc = _Bloc();
      published = [];
      subscription = bloc.errors.listen(published.add);
    });

    tearDown(() async {
      await subscription.cancel();
      if (!bloc.isClosed) await bloc.close();
    });

    test('publishes the failure by default', () async {
      bloc.handleError(failure);
      await pumpEventQueue();

      expect(published, [failure]);
    });

    test('showMessage false publishes nothing', () async {
      bloc.handleError(failure, showMessage: false);
      await pumpEventQueue();

      expect(published, isEmpty);
    });

    test('showMessage true is the same as the default', () async {
      bloc.handleError(failure, showMessage: true);
      await pumpEventQueue();

      expect(published, [failure]);
    });

    test('a quiet failure does not swallow the next one', () async {
      bloc
        ..handleError(failure, showMessage: false)
        ..handleError(const AppFailure(FailureType.server));
      await pumpEventQueue();

      expect(published, [const AppFailure(FailureType.server)]);
    });

    test('after close, either form is a no-op', () async {
      await bloc.close();

      bloc
        ..handleError(failure)
        ..handleError(failure, showMessage: false);
      await pumpEventQueue();

      expect(published, isEmpty);
    });
  });

  group('with StateView', () {
    late _Bloc bloc;

    setUp(() => bloc = _Bloc());
    tearDown(() => bloc.close());

    Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateView<_Bloc>(bloc: bloc, child: const SizedBox()),
        ),
      ),
    );

    testWidgets('the default shows the snack bar', (tester) async {
      await pumpPage(tester);

      bloc.handleError(failure);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('showMessage false shows nothing', (tester) async {
      await pumpPage(tester);

      bloc.handleError(failure, showMessage: false);
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

class _Bloc extends BaseBloc<Object, int> {
  _Bloc() : super(0);
}
