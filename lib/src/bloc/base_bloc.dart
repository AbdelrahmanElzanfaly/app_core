import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../error/app_failure.dart';

/// A bloc with a loading flag and an error channel, both rendered by
/// `StateView`, so a feature's state carries only its own data.
abstract class BaseBloc<E, S> extends Bloc<E, S> {
  BaseBloc(super.initialState);

  final ValueNotifier<bool> loading = ValueNotifier(false);
  final StreamController<AppFailure> _errors = StreamController.broadcast();

  /// Failures to show to the user, one event each.
  Stream<AppFailure> get errors => _errors.stream;

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

  void handleError(Object error) {
    if (!_errors.isClosed) _errors.add(AppFailure.from(error));
  }

  @override
  Future<void> close() async {
    // `loading` is not disposed: a `StateView` still mounted below this bloc's
    // provider may remove its listener after this runs.
    await _errors.close();
    return super.close();
  }
}
