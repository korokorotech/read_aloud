import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ArticleWebViewPage extends StatefulWidget {
  const ArticleWebViewPage({
    super.key,
    required this.initialUrl,
    this.title,
  });

  final Uri initialUrl;
  final String? title;

  @override
  State<ArticleWebViewPage> createState() => _ArticleWebViewPageState();
}

class _ArticleWebViewPageState extends State<ArticleWebViewPage> {
  InAppWebViewController? _controller;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final titleText = widget.title ?? widget.initialUrl.host;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleText ?? '記事を表示',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress >= 1
              ? const SizedBox.shrink()
              : LinearProgressIndicator(value: _progress),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(widget.initialUrl.toString()),
        ),
        initialSettings: InAppWebViewSettings(
          useHybridComposition: true,
          javaScriptEnabled: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
        },
        onProgressChanged: (_, progress) {
          setState(() {
            _progress = progress.clamp(0, 100) / 100;
          });
        },
      ),
    );
  }
}
