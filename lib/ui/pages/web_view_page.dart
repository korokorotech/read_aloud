import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:read_aloud/data/news_item_repository.dart';

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
  late final NewsItemRepository _newsItemRepository;
  InAppWebViewController? _webViewController;
  final FlutterTts _flutterTts = FlutterTts();
  final List<_CachedArticle> _cachedArticles = [];
  bool _isSpeaking = false;
  late final Future<void> _ttsInitFuture;
  late final Future<UserScript> _readabilityUserScriptFuture;

  @override
  void initState() {
    super.initState();
    _isAddMode = widget.openAddMode;
    _setName = widget.setName;
    _newsItemRepository = NewsItemRepository();
    _ttsInitFuture = _setupTts();
    _readabilityUserScriptFuture = _loadReadabilityUserScript();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _setupTts() async {
    await _flutterTts.setSharedInstance(true);
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

  Future<UserScript> _loadReadabilityUserScript() async {
    final source = await rootBundle.loadString('assets/js/Readability.js');
    return UserScript(
      source: source,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    );
  }

  Future<void> _handleBack() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.pop();
    }
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
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('本文を解析中です: $url')),
      );

    try {
      final article = await _extractArticleFromUrl(url);
      if (!mounted) return;

      if (article == null || article.content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本文を取得できませんでした: $url')),
        );
        return;
      }

      final preview = _buildPreviewText(article);
      final saved = await _newsItemRepository.insertArticle(
        setId: widget.setId,
        setName: _setName,
        url: url,
        previewText: preview,
        articleText: article.content,
      );

      if (!mounted) return;
      setState(() {
        _cachedArticles.add(
          _CachedArticle(
            id: saved.id,
            url: url,
            title: article.title?.trim().isNotEmpty == true
                ? article.title!.trim()
                : preview,
            content: article.content,
          ),
        );
      });
      _showAddedSnackBar(saved);
    } on DuplicateArticleException {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('このURLは既にセットに追加されています。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記事取得エラー: $e')),
      );
    }
  }

  void _showAddedSnackBar(NewsItemRecord item) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('キューに追加しました'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'もとに戻す',
            onPressed: () {
              unawaited(_undoInsert(item));
            },
          ),
        ),
      );
  }

  Future<void> _undoInsert(NewsItemRecord item) async {
    try {
      await _newsItemRepository.deleteArticle(item.id);
      if (!mounted) return;
      setState(() {
        _cachedArticles.removeWhere((article) => article.id == item.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('直前の追加を取り消しました。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取り消しに失敗しました: $e')),
      );
    }
  }

  String _buildPreviewText(_ExtractedArticle article) {
    final title = article.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    final body = article.content.trim();
    if (body.isEmpty) {
      return '無題の記事';
    }

    const maxLength = 80;
    return body.length <= maxLength
        ? body
        : '${body.substring(0, maxLength)}…';
  }

  Future<void> _playCachedContent() async {
    if (_cachedArticles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存された本文がありません。')),
      );
      return;
    }

    try {
      await _ttsInitFuture;
      await _flutterTts.stop();
      final buffer = StringBuffer();
      for (final article in _cachedArticles) {
        buffer.writeln(article.content);
      }
      setState(() {
        _isSpeaking = true;
      });
      await _flutterTts.speak(buffer.toString());
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

  Future<_ExtractedArticle?> _extractArticleFromUrl(String url) async {
    final userScript = await _readabilityUserScriptFuture;
    final completer = Completer<_ExtractedArticle?>();

    late HeadlessInAppWebView headless;
    headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        clearCache: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([userScript]),
      onWebViewCreated: (_) {},
      onLoadStop: (controller, _) async {
        try {
          final article = await _extractReadableArticle(controller);
          if (!completer.isCompleted) {
            completer.complete(article);
          }
        } catch (_) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      },
      onReceivedError: (controller, request, error) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    try {
      await headless.run();
      await headless.webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      return await completer.future
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
    } finally {
      await headless.dispose();
    }
  }

  Future<_ExtractedArticle?> _extractReadableArticle(
      InAppWebViewController controller) async {
    final raw = await controller.evaluateJavascript(
      source: _readabilityExtractorJs,
    );
    final jsonStr = raw is String ? raw : raw?.toString();
    if (jsonStr == null || jsonStr.isEmpty) {
      return null;
    }

    final Map<String, dynamic> result = jsonDecode(jsonStr);
    if (result['ok'] == true) {
      final text = result['text'] as String?;
      final title = result['title'] as String?;
      if (text == null) {
        return null;
      }
      final normalized = normalize(text);
      if (normalized.isEmpty) {
        return null;
      }
      return _ExtractedArticle(title: title, content: normalized);
    } else {
      debugPrint('Readability failed: ${result['error']}');
    }

    return null;
  }

  String normalize(String s) {
    return s
        // NBSP を普通のスペースに
        .replaceAll('\u00A0', ' ')
        // 全角スペース
        .replaceAll('\u3000', ' ')
        // ゼロ幅文字
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        // 連続する改行を1つに
        .replaceAll(RegExp(r'\n\s*\n+'), '')
        .replaceAll(RegExp(r'\t'), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserScript>(
      future: _readabilityUserScriptFuture,
      builder: (context, snapshot) {
        final body = (() {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return _buildWebView(snapshot.data!);
          }
          return const Center(
            child: Text('Readability の読み込みに失敗しました'),
          );
        })();

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
          body: body,
        );
      },
    );
  }

  Widget _buildWebView(UserScript readabilityScript) {
    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(widget.initialUrl.toString()),
            ),
            initialSettings: InAppWebViewSettings(
              useHybridComposition: true,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptEnabled: true,
            ),
            initialUserScripts:
                UnmodifiableListView<UserScript>([readabilityScript]),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (_isAddMode &&
                  uri != null &&
                  navigationAction.isForMainFrame) {
                unawaited(_captureArticle(uri.toString()));
                return NavigationActionPolicy.CANCEL;
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
                onPressed: _isSpeaking ? null : _playCachedContent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtractedArticle {
  const _ExtractedArticle({this.title, required this.content});

  final String? title;
  final String content;
}

class _CachedArticle {
  _CachedArticle({
    required this.id,
    required this.url,
    required this.title,
    required this.content,
  });

  final String id;
  final String url;
  final String title;
  final String content;
}

const _readabilityExtractorJs = r'''
(() => {
  try {
    if (typeof Readability === 'undefined') {
      return JSON.stringify({ ok: false, error: 'Readability not found' });
    }
    const doc = document.cloneNode(true);
    const article = new Readability(doc).parse();
    if (!article || !article.textContent) {
      return JSON.stringify({ ok: false, error: 'No article' });
    }
    return JSON.stringify({
      ok: true,
      title: article.title || '',
      text: article.textContent || ''
    });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
''';
