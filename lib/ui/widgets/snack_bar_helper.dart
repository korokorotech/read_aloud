import 'package:flutter/material.dart';

const Duration _defaultSnackBarDuration = Duration(seconds: 4);

void showAutoHideSnackBar(
  BuildContext context, {
  required String message,
  Duration? duration,
  SnackBarAction? action,
  bool hideCurrent = true,
}) {
  final messenger = ScaffoldMessenger.of(context);
  if (hideCurrent) {
    messenger.hideCurrentSnackBar();
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? _defaultSnackBarDuration,
      action: action,
      persist: false,
    ),
  );
}
