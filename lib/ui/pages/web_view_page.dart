import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isAddMode
            ? 'ニュース追加モードをオンにしました。リンクをタップすると「リンク先をニュースセットに追加しました」想定。'
            : 'ニュース追加モードをオフにしました。'),
        action: _isAddMode
            ? SnackBarAction(
                label: '取消',
                onPressed: () {
                  if (!mounted) return;
                  setState(() {
                    _isAddMode = false;
                  });
                },
              )
            : null,
        duration: const Duration(seconds: 3),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '閲覧中URL：${widget.initialUrl}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  _WebViewPlaceholder(isAddMode: _isAddMode),
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.tune),
                      label: const Text('一括設定'),
                      onPressed: _handleBulkAdd,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 32,
                    child: FilledButton.icon(
                      icon: Icon(
                        _isAddMode ? Icons.check_circle : Icons.add_circle,
                      ),
                      label: Text(
                          _isAddMode ? '追加モード ON' : 'ニュース追加モード'),
                      onPressed: _toggleAddMode,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('戻る'),
                onPressed: _handleBack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebViewPlaceholder extends StatelessWidget {
  const _WebViewPlaceholder({required this.isAddMode});

  final bool isAddMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.web,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'WebView 表示エリア（モック）',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isAddMode
                  ? 'ニュース追加モード: ON\nリンクをタップするとキューに追加される想定です。'
                  : 'リンクをタップすると通常遷移します。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
