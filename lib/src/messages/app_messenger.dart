import 'package:flutter/material.dart';

import 'app_message_theme.dart';
import 'app_message_type.dart';

/// The app's one way to show a short message: a snack bar whose colours
/// come from the theme's [AppMessageTheme].
///
/// ```dart
/// context.showSuccess(l10n.saved);
/// context.showWarning(l10n.roxOutOfStockToast(alert.name));
/// ```
///
/// Call it from a page, typically its `BlocConsumer` listener when a
/// `SingleEffect` arrives; a bloc never shows messages itself. Each message
/// replaces the one on screen. For a result the user must not miss (a
/// transfer, a payment), use a dialog or a result screen: a snack bar goes
/// away by itself.
extension AppMessenger on BuildContext {
  void showSuccess(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => showAppMessage(
    message,
    type: AppMessageType.success,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  void showError(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => showAppMessage(
    message,
    type: AppMessageType.error,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  void showWarning(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => showAppMessage(
    message,
    type: AppMessageType.warning,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  void showInfo(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => showAppMessage(message, actionLabel: actionLabel, onAction: onAction);

  /// Does nothing without a [ScaffoldMessenger] above this context.
  void showAppMessage(
    String message, {
    AppMessageType type = AppMessageType.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    assert(
      (actionLabel == null) == (onAction == null),
      'An action needs both a label and a callback.',
    );
    final messenger = ScaffoldMessenger.maybeOf(this);
    if (messenger == null) return;

    final style = AppMessageTheme.of(this).styleOf(type);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: style.background,
          duration: style.duration,
          content: AppMessageContent(message: message, type: type),
          action:
              actionLabel == null
                  ? null
                  : SnackBarAction(
                    label: actionLabel,
                    textColor: style.foreground,
                    onPressed: onAction!,
                  ),
        ),
      );
  }
}

/// A message's content: its type's icon beside the text, laid out for the
/// reading direction. The icon, the colour and the gap come from the theme's
/// [AppMessageTheme].
class AppMessageContent extends StatelessWidget {
  const AppMessageContent({
    super.key,
    required this.message,
    required this.type,
  });

  final String message;
  final AppMessageType type;

  @override
  Widget build(BuildContext context) {
    final theme = AppMessageTheme.of(context);
    final style = theme.styleOf(type);
    return Row(
      children: [
        Icon(style.icon, color: style.foreground),
        SizedBox(width: theme.iconSpacing),
        // Merges with the snack bar's own text style; only the colour
        // changes.
        Expanded(
          child: Text(message, style: TextStyle(color: style.foreground)),
        ),
      ],
    );
  }
}
