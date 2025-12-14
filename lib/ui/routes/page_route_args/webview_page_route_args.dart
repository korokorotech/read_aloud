import 'package:flutter/material.dart';

@immutable
class WebViewRouteArgs {
  const WebViewRouteArgs({
    required this.setName,
    required this.initialUrl,
    this.openAddMode = false,
  });

  final String setName;
  final Uri initialUrl;

  final bool openAddMode;
}
