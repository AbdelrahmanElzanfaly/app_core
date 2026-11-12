import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

import '../error/app_failure.dart';

/// A bloc with a loading flag and an error channel, both rendered by
/// `StateView`, so a feature's state carries only its own data.
abstract class BaseBloc<E, S> extends Bloc<E, S> {
  BaseBloc(super.initialState);

  final ValueNotifier<bool> loading = ValueNotifier(false);
  final StreamController<AppFailure> _errors = StreamController.broadcast();
  final Map<Type, Completer<void>> _refreshWaiters = {};
  bool _isClosing = false;

  /// Failures to show to the user, one event each.
  Stream<AppFailure> get errors => _errors.stream;

  /// Adds a reload [event] and waits for its handler to finish.
  ///
  /// Use with a dedicated event registered with `droppable()`. Calls for the
  /// same concrete event type share one future. If a normal load of that type
  /// is already running, its completion also finishes the refresh.
  ///
  /// Completion means the handler has finished, including after a failure;
  /// errors still use [handleError] and the feature's state. Closing the bloc
  /// releases pending callbacks. This does not cancel the underlying request.
  Future<void> refresh(E event) {
    if (_isClosing || isClosed) return Future.value();

    final eventType = event.runtimeType;
    final active = _refreshWaiters[eventType];
    if (active != null) return active.future;

    final completed = Completer<void>();
    _refreshWaiters[eventType] = completed;
    try {
      add(event);
    } catch (error, stackTrace) {
      _refreshWaiters.remove(eventType);
      completed.completeError(error, stackTrace);
    }
    return completed.future;
  }

  @override
  void onDone(E event, [Object? error, StackTrace? stackTrace]) {
    super.onDone(event, error, stackTrace);
    _refreshWaiters.remove(event.runtimeType)?.complete();
  }

  /// Runs [block] with [loading] raised; anything it throws reaches
  /// [handleError] instead of the zone.
  Future<void> launchBlock({
    required Future<void> Function() block,
    bool showLoading = true,
  }) async {
    if (showLoading) loading.value = true;
    try {
      await block();
    } catch (error) {
      handleError(error);
    } finally {
      if (showLoading && !isClosed) loading.value = false;
    }
  }

  /// Publishes [error] on [errors], which `StateView` shows to the user.
  ///
  /// Pass [showMessage] false for a failure the page already presents itself
  /// (inline, or in a dialog): nothing is published. The feature's own state
  /// handling is unaffected either way.
  void handleError(Object error, {bool showMessage = true}) {
    if (!showMessage || _errors.isClosed) return;
    _errors.add(AppFailure.from(error));
  }

  @override
  Future<void> close() async {
    _isClosing = true;
    for (final completed in _refreshWaiters.values) {
      completed.complete();
    }
    _refreshWaiters.clear();

    // `loading` is not disposed: a `StateView` still mounted below this bloc's
    // provider may remove its listener after this runs.
    await _errors.close();
    return super.close();
  }
}
