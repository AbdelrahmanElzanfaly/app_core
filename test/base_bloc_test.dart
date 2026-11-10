import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BaseBloc.refresh', () {
    test('same-type refresh calls wait for one request to finish', () async {
      final bloc = _createBloc();
      var finishedFirst = false;
      var finishedSecond = false;
      final first = bloc.refresh(const _ReloadA()).then((_) {
        finishedFirst = true;
      });
      final second = bloc.refresh(const _ReloadA()).then((_) {
        finishedSecond = true;
      });
      await bloc.startedA.future;
      await Future<void>.delayed(Duration.zero);

      expect(bloc.requestsA, 1);
      expect(finishedFirst, isFalse);
      expect(finishedSecond, isFalse);

      bloc.responseA.complete();
      await Future.wait([first, second]);

      expect(finishedFirst, isTrue);
      expect(finishedSecond, isTrue);
      expect(bloc.requestsA, 1);
    });

    test(
      'a handled failure releases refresh and permits a successful retry',
      () async {
        final bloc = _createBloc();
        final published = bloc.errors.first;

        await bloc.refresh(const _FallibleReload());

        expect(await published, same(_RefreshProbe.failure));
        expect(bloc.requestsFallible, 1);
        expect(bloc.loading.value, isFalse);
        expect(bloc.state, 0);

        await bloc.refresh(const _FallibleReload());

        expect(bloc.requestsFallible, 2);
        expect(bloc.loading.value, isFalse);
        expect(bloc.state, 1);
      },
    );

    test('joins a normal droppable request already in progress', () async {
      final bloc = _createBloc();
      bloc.add(const _ReloadA());
      await bloc.startedA.future;
      var refreshed = false;

      final refresh = bloc.refresh(const _ReloadA()).then((_) {
        refreshed = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(bloc.requestsA, 1);
      expect(refreshed, isFalse);
      bloc.responseA.complete();
      await refresh;

      expect(refreshed, isTrue);
      expect(bloc.requestsA, 1);
    });

    test(
      'unrelated events and other refresh types do not release a waiter',
      () async {
        final bloc = _createBloc();
        var finishedA = false;
        var finishedB = false;
        final refreshA = bloc.refresh(const _ReloadA()).then((_) {
          finishedA = true;
        });
        await bloc.startedA.future;
        bloc.add(const _Unrelated());
        await bloc.unrelatedHandled.future;
        await Future<void>.delayed(Duration.zero);
        expect(finishedA, isFalse);

        final refreshB = bloc.refresh(const _ReloadB()).then((_) {
          finishedB = true;
        });
        await bloc.startedB.future;
        expect(bloc.requestsA, 1);
        expect(bloc.requestsB, 1);
        expect(finishedA, isFalse);
        expect(finishedB, isFalse);

        bloc.responseA.complete();
        await refreshA;
        expect(finishedA, isTrue);
        expect(finishedB, isFalse);

        bloc.responseB.complete();
        await refreshB;
        expect(finishedB, isTrue);
      },
    );

    test('refresh during or after close starts no new work', () async {
      final bloc = _createBloc();
      final pending = bloc.refresh(const _ReloadA());
      await bloc.startedA.future;

      final closing = bloc.close();
      await bloc.refresh(const _ReloadB());
      await pending;
      expect(bloc.responseA.isCompleted, isFalse);
      expect(bloc.requestsB, 0);

      bloc.responseA.complete();
      await closing;
      await bloc.refresh(const _ReloadB());

      expect(bloc.isClosed, isTrue);
      expect(bloc.requestsB, 0);
    });

    test(
      'a rejected add fails its future without poisoning the next refresh',
      () async {
        final bloc = _createBloc()..rejectNextAdd = true;

        await expectLater(
          bloc.refresh(const _ReloadA()),
          throwsA(isA<StateError>()),
        );
        expect(bloc.requestsA, 0);

        final retried = bloc.refresh(const _ReloadA());
        await bloc.startedA.future;
        bloc.responseA.complete();
        await retried;

        expect(bloc.requestsA, 1);
      },
    );
  });
}

_RefreshProbe _createBloc() {
  final bloc = _RefreshProbe();
  addTearDown(() async {
    if (!bloc.responseA.isCompleted) bloc.responseA.complete();
    if (!bloc.responseB.isCompleted) bloc.responseB.complete();
    if (!bloc.isClosed) await bloc.close();
  });
  return bloc;
}

sealed class _Event {
  const _Event();
}

class _ReloadA extends _Event {
  const _ReloadA();
}

class _ReloadB extends _Event {
  const _ReloadB();
}

class _Unrelated extends _Event {
  const _Unrelated();
}

class _FallibleReload extends _Event {
  const _FallibleReload();
}

class _RefreshProbe extends BaseBloc<_Event, int> {
  _RefreshProbe() : super(0) {
    on<_ReloadA>((event, emit) async {
      requestsA++;
      if (!startedA.isCompleted) startedA.complete();
      await responseA.future;
    }, transformer: droppable());
    on<_ReloadB>((event, emit) async {
      requestsB++;
      if (!startedB.isCompleted) startedB.complete();
      await responseB.future;
    }, transformer: droppable());
    on<_Unrelated>(
      (event, emit) => unrelatedHandled.complete(),
      transformer: sequential(),
    );
    on<_FallibleReload>((event, emit) async {
      await launchBlock(
        block: () async {
          requestsFallible++;
          if (requestsFallible == 1) throw failure;
          emit(state + 1);
        },
      );
    }, transformer: droppable());
  }

  static const failure = AppFailure(
    FailureType.timeout,
    code: 'request_timeout',
  );

  final startedA = Completer<void>();
  final startedB = Completer<void>();
  final responseA = Completer<void>();
  final responseB = Completer<void>();
  final unrelatedHandled = Completer<void>();
  int requestsA = 0;
  int requestsB = 0;
  int requestsFallible = 0;
  bool rejectNextAdd = false;

  @override
  void add(_Event event) {
    if (rejectNextAdd) {
      rejectNextAdd = false;
      throw StateError('The event was rejected.');
    }
    super.add(event);
  }
}
