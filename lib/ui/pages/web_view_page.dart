import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

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
  final FlutterTts _flutterTts = FlutterTts();
  final List<_CachedArticle> _cachedArticles = [];
  bool _isSpeaking = false;
  late final Future<void> _ttsInitFuture;

  @override
  void initState() {
    super.initState();
    _isAddMode = widget.openAddMode;
    _setName = widget.setName;
    _ttsInitFuture = _setupTts();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _setupTts() async {
    // await _flutterTts.setSharedInstance(true);

    print("TEST_D 11 ${await _flutterTts.getDefaultEngine}");
    print("TEST_D 12 ${await _flutterTts.getDefaultVoice}");

    await _flutterTts.setLanguage('ja-JP');
    await _flutterTts.setSpeechRate(1);
    await _flutterTts.awaitSpeakCompletion(true);
    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
    });
    _flutterTts.setErrorHandler((msg) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
    });
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

  Future<void> _captureArticle(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取得に失敗しました: $url')),
        );
        return;
      }

      final content = _stripHtml(response.body);
      if (!mounted) return;
      setState(() {
        _cachedArticles
            .add(_CachedArticle(url: uri.toString(), content: content));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記事を保存しました (${_cachedArticles.length}件)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記事取得エラー: $e')),
      );
    }
  }

  Future<void> _playCachedContent() async {
    try {
      await _ttsInitFuture;
      await _flutterTts.stop();
      await _flutterTts.setPitch(1);
      setState(() {
        _isSpeaking = true;
      });
      await _flutterTts.speak('はむこ、はむころ、ハムスター');
      await _flutterTts.stop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSpeaking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TTSエラー: $e')),
      );
    }
  }

  String _stripHtml(String html) {
    final withoutScripts = html.replaceAll(
        RegExp(r'<script[^>]*>.*?</script>',
            dotAll: true, caseSensitive: false),
        '');
    final withoutStyles = withoutScripts.replaceAll(
        RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false),
        '');
    return withoutStyles
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri != null && navigationAction.isForMainFrame) {
                  unawaited(_captureArticle(uri.toString()));
                }
                return NavigationActionPolicy.ALLOW;
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
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: Icon(
                    _isSpeaking ? Icons.volume_up : Icons.play_arrow,
                  ),
                  label: Text(_isSpeaking ? '再生中...' : 'TTS再生'),
                  onPressed: _playCachedContent,
                  // onPressed: _isSpeaking ? null : _playCachedContent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CachedArticle {
  _CachedArticle({required this.url, required this.content});

  final String url;
  final String content;
}
