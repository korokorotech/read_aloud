import 'package:flutter/material.dart';

class WebViewPage extends StatelessWidget {
  const WebViewPage({
    super.key,
    required this.setId,
    required this.initialUrl,
    this.openAddMode = false,
  });

  final String setId;
  final Uri initialUrl;
  final bool openAddMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web View'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('セットID: $setId'),
            const SizedBox(height: 12),
            Text('初期URL: ${initialUrl.toString()}'),
            const SizedBox(height: 12),
            Text('追加モード: ${openAddMode ? 'ON' : 'OFF'}'),
          ],
        ),
      ),
    );
  }
}
