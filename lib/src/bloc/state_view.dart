import 'dart:async';

import 'package:flutter/material.dart';

import '../error/app_failure.dart';
import '../l10n/core_localizations.dart';
import '../messages/app_messenger.dart';
import 'base_bloc.dart';

/// Renders a [BaseBloc]'s loading flag as an overlay and its errors as
/// error messages (`AppMessenger.showError`), around [child].
class StateView<B extends BaseBloc<dynamic, dynamic>> extends StatefulWidget {
  const StateView({super.key, required this.bloc, required this.child});

  final B bloc;
  final Widget child;

  @override
  State<StateView<B>> createState() => _StateViewState<B>();
}

class _StateViewState<B extends BaseBloc<dynamic, dynamic>>
    extends State<StateView<B>> {
  StreamSubscription<AppFailure>? _errors;

  @override
  void initState() {
    super.initState();
    _errors = widget.bloc.errors.listen(_showError);
  }

  @override
  void didUpdateWidget(StateView<B> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bloc != widget.bloc) {
      _errors?.cancel();
      _errors = widget.bloc.errors.listen(_showError);
    }
  }

  void _showError(AppFailure failure) {
    if (!mounted) return;
    context.showError(CoreLocalizations.of(context).describe(failure));
  }

  @override
  void dispose() {
    _errors?.cancel();
    super.dispose();
  }

  @override
  // `StackFit.expand`: the stack takes the incoming size and gives it to both
  // layers. With the default loose fit, a stack whose only non-positioned
  // child is an empty box sizes itself to zero — and the page with it.
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      ValueListenableBuilder<bool>(
        valueListenable: widget.bloc.loading,
        builder: (context, isLoading, _) => isLoading
            ? const ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}
