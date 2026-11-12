import 'package:flutter/widgets.dart';

import '../error/app_failure.dart';

/// Shows a failure a `StateView` received, in the app's own style.
typedef FailurePresenter =
    void Function(BuildContext context, AppFailure failure);

/// How every `StateView` below presents its failures.
///
/// Set once, in `MaterialApp.builder`, so each feature's errors look the same
/// without per-page code. Without a scope, `StateView` shows a plain snack
/// bar with `CoreLocalizations`' copy, as before.
class StateViewScope extends InheritedWidget {
  const StateViewScope({
    super.key,
    required this.onError,
    required super.child,
  });

  final FailurePresenter onError;

  /// No rebuild dependency: `StateView` reads it only when a failure
  /// arrives.
  static StateViewScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StateViewScope>();

  @override
  bool updateShouldNotify(StateViewScope oldWidget) =>
      onError != oldWidget.onError;
}
