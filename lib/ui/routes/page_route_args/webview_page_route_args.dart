import 'package:flutter/material.dart';

@immutable
class WebViewRouteArgs {
  const WebViewRouteArgs({
    required this.initialUrl,
    this.openAddMode = false,
  });

  final Uri initialUrl;

  final bool openAddMode;
}
