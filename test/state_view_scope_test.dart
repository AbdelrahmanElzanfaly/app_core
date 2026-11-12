import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Bloc bloc;

  setUp(() => bloc = _Bloc());
  tearDown(() => bloc.close());

  const failure = AppFailure(FailureType.network);

  Widget page() =>
      Scaffold(body: StateView<_Bloc>(bloc: bloc, child: const SizedBox()));

  testWidgets('without a scope, a failure shows the plain snack bar', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: page()));

    bloc.handleError(failure);
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('No connection. Check the network and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a scope in MaterialApp.builder presents every failure instead', (
    tester,
  ) async {
    final presented = <AppFailure>[];
    BuildContext? presentedFrom;
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => StateViewScope(
              onError: (context, failure) {
                presentedFrom = context;
                presented.add(failure);
              },
              child: child!,
            ),
        home: page(),
      ),
    );

    bloc.handleError(failure);
    await tester.pump();

    expect(presented, [failure]);
    expect(find.byType(SnackBar), findsNothing);
    // The StateView's own context: below the theme, the localizations and
    // the scaffold messenger, so the presenter can show a snack bar.
    expect(presentedFrom!.widget, isA<StateView<_Bloc>>());
    expect(ScaffoldMessenger.maybeOf(presentedFrom!), isNotNull);
  });

  testWidgets('maybeOf is null without a scope', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    expect(StateViewScope.maybeOf(context), isNull);
  });

  testWidgets('a new presenter is used for the next failure', (tester) async {
    final calls = <String>[];
    Future<void> pumpWith(String name) => tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => StateViewScope(
              onError: (context, failure) => calls.add(name),
              child: child!,
            ),
        home: page(),
      ),
    );

    await pumpWith('first');
    await pumpWith('second');
    bloc.handleError(failure);
    await tester.pump();

    expect(calls, ['second']);
  });
}

class _Bloc extends BaseBloc<Object, int> {
  _Bloc() : super(0);
}
