import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/repositories/news_item_repository.dart';
import 'package:read_aloud/ui/widgets/snack_bar_helper.dart';

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
  bool _showActionMenu = false;
  late final Future<UserScript> _readabilityUserScriptFuture;

  @override
  void initState() {
    super.initState();
    _isAddMode = widget.openAddMode;
    _setName = widget.setName;
    _newsItemRepository = NewsItemRepository();
    _readabilityUserScriptFuture = _loadReadabilityUserScript();
  }

  Future<UserScript> _loadReadabilityUserScript() async {
    final source = await rootBundle.loadString('assets/js/Readability.js');
    return UserScript(
      source: source,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    );
  }

  Future<bool> _goBackInWebViewIfPossible() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return true;
    }
    return false;
  }

  Future<void> _handleBack() async {
    if (await _goBackInWebViewIfPossible()) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.pop();
    }
  }

  Future<bool> _handleSystemBack() async {
    final handled = await _goBackInWebViewIfPossible();
    return !handled;
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
              showAutoHideSnackBar(
                context,
                message: 'リンクを一括追加しました（モック）。',
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAddCurrentPage() async {
    final controller = _webViewController;
    if (controller == null) {
      showAutoHideSnackBar(
        context,
        message: 'WebView の準備ができていません。',
      );
      return;
    }
    final currentUrl = await controller.getUrl();
    final urlStr = currentUrl?.toString();
    if (urlStr == null || urlStr.isEmpty) {
      showAutoHideSnackBar(
        context,
        message: '現在のページのURLを取得できませんでした。',
      );
      return;
    }
    final normalizedUrl = _normalizeUrl(urlStr) ?? urlStr;

    if (_showActionMenu) {
      setState(() {
        _showActionMenu = false;
      });
    }

    if (!mounted) return;
    showAutoHideSnackBar(
      context,
      message: '現在のページを解析中です: $normalizedUrl',
    );

    try {
      final article = await _extractReadableArticle(controller);
      if (!mounted) return;
      if (article == null || article.content.isEmpty) {
        showAutoHideSnackBar(
          context,
          message: '本文を取得できませんでした: $normalizedUrl',
        );
        return;
      }

      final saved = await _saveExtractedArticle(normalizedUrl, article);
      if (!mounted) return;
      _showAddedSnackBar(saved);
    } on DuplicateArticleException {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'このURLは既にセットに追加されています。',
      );
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '記事取得エラー: $e',
      );
    }
  }

  void _toggleActionMenu() {
    setState(() {
      _showActionMenu = !_showActionMenu;
    });
  }

  void _handleBulkAddFromMenu() {
    setState(() {
      _showActionMenu = false;
    });
    _handleBulkAdd();
  }

  void _handleToggleAddModeFromMenu() {
    setState(() {
      _showActionMenu = false;
    });
    _toggleAddMode();
  }

  void _toggleAddMode() {
    setState(() {
      _isAddMode = !_isAddMode;
    });

    showAutoHideSnackBar(
      context,
      message: _isAddMode ? 'ニュース追加モードをオンにしました。' : 'ニュース追加モードをオフにしました。',
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'OK',
        onPressed: ScaffoldMessenger.of(context).hideCurrentSnackBar,
      ),
    );
  }

  Future<void> _captureArticle(String url) async {
    if (!mounted) return;
    showAutoHideSnackBar(
      context,
      message: '本文を解析中です: $url',
    );

    try {
      final article = await _extractArticleFromUrl(url);
      if (!mounted) return;

      if (article == null || article.content.isEmpty) {
        showAutoHideSnackBar(
          context,
          message: '本文を取得できませんでした: $url',
        );
        return;
      }

      final saved = await _saveExtractedArticle(url, article);

      if (!mounted) return;
      _showAddedSnackBar(saved);
    } on DuplicateArticleException {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'このURLは既にセットに追加されています。',
      );
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '記事取得エラー: $e',
      );
    }
  }

  void _showAddedSnackBar(NewsItemRecord item) {
    if (!mounted) return;
    showAutoHideSnackBar(
      context,
      message: 'キューに追加しました',
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'もとに戻す',
        onPressed: () {
          unawaited(_undoInsert(item));
        },
      ),
    );
  }

  Future<void> _undoInsert(NewsItemRecord item) async {
    try {
      await _newsItemRepository.deleteArticle(item.id);
      showAutoHideSnackBar(
        context,
        message: '直前の追加を取り消しました。',
      );
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '取り消しに失敗しました: $e',
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
    return body.length <= maxLength ? body : '${body.substring(0, maxLength)}…';
  }

  Future<NewsItemRecord> _saveExtractedArticle(
    String url,
    _ExtractedArticle article,
  ) {
    final preview = _buildPreviewText(article);
    return _newsItemRepository.insertArticle(
      setId: widget.setId,
      setName: _setName,
      url: url,
      previewText: preview,
      articleText: article.content,
    );
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
      onLoadStop: (controller, loadedUrl) async {
        try {
          if (loadedUrl?.host == "news.google.com") {
            return;
          }
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

  String? _normalizeUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return null;
    }

    Uri current = parsed;
    final redirected = _resolveGoogleRedirect(parsed);
    if (redirected != null) {
      current = redirected;
    }

    if (current.queryParameters.isEmpty) {
      return current.toString();
    }

    final filtered = <String, String>{};
    var changed = false;
    current.queryParameters.forEach((key, value) {
      if (_shouldDropQueryParam(key)) {
        changed = true;
      } else {
        filtered[key] = value;
      }
    });

    if (changed) {
      current = current.replace(
        queryParameters: filtered.isEmpty ? null : filtered,
      );
    }
    return current.toString();
  }

  Uri? _resolveGoogleRedirect(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!(host.contains('google.') || host.endsWith('google'))) {
      return null;
    }
    if (uri.path != '/url') {
      return null;
    }
    final q = uri.queryParameters['q'];
    if (q == null || q.isEmpty) {
      return null;
    }
    final redirected = Uri.tryParse(q);
    if (redirected == null || redirected.scheme.isEmpty) {
      return null;
    }
    return redirected;
  }

  bool _shouldDropQueryParam(String key) {
    final lower = key.toLowerCase();
    if (lower.startsWith('utm_')) return true;
    const dropList = {
      'ref',
      'ref_src',
      'fbclid',
      'gclid',
      'yclid',
      'mc_cid',
      'mc_eid',
      'igshid',
      'mkt_tok',
      'acd',
      'ved',
      'sa',
      'usg',
    };
    return dropList.contains(lower);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: FutureBuilder<UserScript>(
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
      ),
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
                final normalized = _normalizeUrl(uri.toString());
                unawaited(_captureArticle(normalized ?? uri.toString()));
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            minimum: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_showActionMenu) _buildActionMenu(),
                if (_showActionMenu) const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.settings,
                  tooltip: 'その他の操作',
                  onTap: _toggleActionMenu,
                ),
                const SizedBox(height: 12),
                _ActionButton(
                  icon: Icons.add,
                  tooltip: '現在のページを追加',
                  onTap: () {
                    unawaited(_handleAddCurrentPage());
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionMenu() {
    final toggleLabel = _isAddMode ? 'リンクタップで追加オフ' : 'リンクタップで追加オン';
    final toggleIcon = _isAddMode ? Icons.link_off : Icons.link;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      shadowColor: Colors.black12,
      child: SizedBox(
        width: 220,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: _handleBulkAddFromMenu,
                icon: const Icon(Icons.tune),
                label: const Text('一括追加'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
              ),
              TextButton.icon(
                onPressed: _handleToggleAddModeFromMenu,
                icon: Icon(toggleIcon),
                label: Text(toggleLabel),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtractedArticle {
  const _ExtractedArticle({this.title, required this.content});

  final String? title;
  final String content;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1.2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Tooltip(
              message: tooltip,
              child: Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
