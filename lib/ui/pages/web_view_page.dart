import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.setId,
    required this.setName,
    required this.initialUrl,
    this.openAddMode = false,
  });

  final String setId;
  final String setName;
  final Uri initialUrl;
  final bool openAddMode;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late bool _isAddMode;
  late String _setName;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _isAddMode = widget.openAddMode;
    _setName = widget.setName;
  }

  void _handleBack() {
    context.pop();
  }

  Future<void> _handleRename() async {
    final controller = TextEditingController(text: _setName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('セット名を編集'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'ニュースセット名',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      setState(() {
        _setName = newName;
      });
    }
  }

  void _handleBulkAdd() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一括設定（モック）'),
        content: const Text(
          'ここではWebView内で検出したリンクのプレビューを表示し、まとめて追加する想定です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('リンクを一括追加しました（モック）。')),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleAddMode() {
    setState(() {
      _isAddMode = !_isAddMode;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _isAddMode ? 'ニュース追加モードをオンにしました。' : 'ニュース追加モードをオフにしました。',
          ),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'OK',
            onPressed: ScaffoldMessenger.of(context).hideCurrentSnackBar,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(
              child: Text(
                _setName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'ニュースセット名を変更',
              onPressed: _handleRename,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.initialUrl.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                useHybridComposition: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
            ),
          ),
          Positioned(
            left: 16,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('一括設定'),
                  onPressed: _handleBulkAdd,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: Icon(
                    _isAddMode ? Icons.check_circle : Icons.add_circle,
                  ),
                  label: Text(_isAddMode ? '追加モード ON' : 'ニュース追加モード'),
                  onPressed: _toggleAddMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
