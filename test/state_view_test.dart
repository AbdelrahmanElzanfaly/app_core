import 'package:app_core/app_core.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late _Bloc bloc;

  setUp(() => bloc = _Bloc());
  tearDown(() => bloc.close());

  /// A page that paints, under [StateView], inside a [LayoutBuilder] with a
  /// bar beside it: as an app's tab shell lays out a tab, since
  /// `Scaffold(extendBody: true)` wraps its body in a [LayoutBuilder] and
  /// keeps its bottom bar next to it.
  Future<void> pumpInShell(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder:
                    (context, constraints) => StateView<_Bloc>(
                      bloc: bloc,
                      child: const CustomPaint(
                        painter: _Page(),
                        child: SizedBox.expand(),
                      ),
                    ),
              ),
            ),
            const SizedBox(
              width: double.infinity,
              height: 80,
              child: CustomPaint(painter: _Bar()),
            ),
          ],
        ),
      ),
    );
  }

  RenderObject painting<T extends CustomPainter>(WidgetTester tester) =>
      tester.renderObject(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is T,
        ),
      );

  /// How many times each of [targets] paints while [act] runs. None may be a
  /// repaint boundary: the hook also fires for a boundary reused as it was.
  Future<List<int>> paintsOf(
    List<RenderObject> targets,
    Future<void> Function() act,
  ) async {
    final paints = List.filled(targets.length, 0);
    final previous = debugOnProfilePaint;
    debugOnProfilePaint = (painted) {
      previous?.call(painted);
      final index = targets.indexWhere((target) => identical(target, painted));
      if (index >= 0) paints[index]++;
    };
    try {
      await act();
    } finally {
      debugOnProfilePaint = previous;
    }
    return paints;
  }

  testWidgets('shows a spinner over the page while loading, centred on a '
      'dimmed overlay, and takes it away once done', (tester) async {
    await pumpInShell(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    bloc.loading.value = true;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getCenter(find.byType(CircularProgressIndicator)),
      tester.getCenter(find.byType(StateView<_Bloc>)),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0x33000000),
      ),
      findsOneWidget,
    );

    bloc.loading.value = false;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the turning spinner leaves the page under it and the bar '
      'beside it as painted', (tester) async {
    await pumpInShell(tester);
    bloc.loading.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final paints = await paintsOf(
      [painting<_Page>(tester), painting<_Bar>(tester)],
      () async {
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      },
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(paints, [0, 0]);

    bloc.loading.value = false;
    await tester.pump();
  });
}

class _Bloc extends BaseBloc<Object, int> {
  _Bloc() : super(0);
}

/// The page under the overlay.
class _Page extends CustomPainter {
  const _Page();

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.teal);

  @override
  bool shouldRepaint(_Page oldDelegate) => false;
}

/// What sits beside the page, such as a tab bar.
class _Bar extends CustomPainter {
  const _Bar();

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.indigo);

  @override
  bool shouldRepaint(_Bar oldDelegate) => false;
}
