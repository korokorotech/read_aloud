import 'package:flutter/material.dart';

class NewsSetDetailPage extends StatelessWidget {
  const NewsSetDetailPage({
    super.key,
    required this.setId,
  });

  final String setId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ニュースセット詳細'),
      ),
      body: Center(
        child: Text('セットID: $setId'),
      ),
    );
  }
}
