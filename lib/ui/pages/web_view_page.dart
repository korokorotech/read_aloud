import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/repositories/news_item_repository.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/services/player_service.dart';
import 'package:read_aloud/ui/routes/app_router.dart';
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
  static const _logFileName = 'web_view_debug.log';
  static const int _maxLogFileBytes = 512 * 1024;

  late bool _isAddMode;
  late String _setName;
  late final NewsItemRepository _newsItemRepository;
  late final NewsSetRepository _newsSetRepository;
  final PlayerService _player = PlayerService.instance;
  InAppWebViewController? _webViewController;
  bool _showActionMenu = false;
  late final Future<UserScript> _readabilityUserScriptFuture;
  bool _hasExistingSet = false;
  bool _isCheckingSetExists = true;
  static const int _contextMenuBatchSize = 10;
  _PreparedLink? _pendingLongPressLink;

  @override
  void initState() {
    super.initState();
    _isAddMode = widget.openAddMode;
    _setName = widget.setName;
    _newsItemRepository = NewsItemRepository();
    _newsSetRepository = NewsSetRepository();
    _readabilityUserScriptFuture = _loadReadabilityUserScript();
    unawaited(_checkSetExists());
    if (Platform.isAndroid) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
  }

  Future<UserScript> _loadReadabilityUserScript() async {
    final source = await rootBundle.loadString('assets/js/Readability.js');
    return UserScript(
      source: source,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    );
  }

  Future<void> _checkSetExists() async {
    try {
      final exists = await _newsSetRepository.exists(widget.setId);
      if (!mounted) return;
      setState(() {
        _hasExistingSet = exists;
        _isCheckingSetExists = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasExistingSet = false;
        _isCheckingSetExists = false;
      });
    }
  }

  void _markSetAsAvailable() {
    if (!mounted) return;
    if (_hasExistingSet && !_isCheckingSetExists) {
      return;
    }
    setState(() {
      _hasExistingSet = true;
      _isCheckingSetExists = false;
    });
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

  Future<void> _handleOpenSetDetail() async {
    if (_isCheckingSetExists || !_hasExistingSet) {
      return;
    }
    await context.pushSetDetail(widget.setId);
  }

  Future<void> _handleReadVisiblePage() async {
    final controller = _webViewController;
    if (controller == null) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'ページを読み込んでいる最中です。少し待ってから再試行してください。',
      );
      return;
    }

    try {
      final currentUri = await controller.getUrl();
      final currentUrl = currentUri?.toString() ?? widget.initialUrl.toString();

      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '現在のページを解析しています…',
      );

      final article = await _extractReadableArticle(controller);
      if (!mounted) return;
      if (article == null || article.content.trim().isEmpty) {
        showAutoHideSnackBar(
          context,
          message: '本文を取得できませんでした。',
        );
        return;
      }

      final preview = _buildPreviewText(article);
      await _player.playStandaloneArticle(
        url: currentUrl,
        previewText: preview,
        articleText: article.content,
      );
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '読み上げに失敗しました: $e',
      );
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
      _markSetAsAvailable();
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

  Future<void> _handleAddLinkFromContextMenu() async {
    final link = _pendingLongPressLink;
    _pendingLongPressLink = null;
    if (link == null) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'リンクのURLを特定できませんでした。',
      );
      return;
    }
    await _captureArticle(link.normalizedUrl);
  }

  Future<void> _handleAddBatchFromContextMenu() async {
    final link = _pendingLongPressLink;
    _pendingLongPressLink = null;
    final controller = _webViewController;
    if (controller == null) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'WebView の準備ができていません。',
      );
      return;
    }
    if (link == null) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'リンクのURLを特定できませんでした。',
      );
      return;
    }
    final links = await _collectForwardLinks(
      controller,
      link.anchorUrl,
      _contextMenuBatchSize,
    );
    if (links.isEmpty) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: 'このリンク以降の項目を取得できませんでした。',
      );
      return;
    }
    await _captureMultipleArticles(links);
  }

  Future<_PreparedLink?> _prepareLongPressLink(
    InAppWebViewController controller,
    String rawUrl,
  ) async {
    if (rawUrl.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null) {
      return null;
    }
    Uri? absolute = parsed;
    if (parsed.scheme.isEmpty) {
      final current = await controller.getUrl();
      final base = current == null ? null : Uri.tryParse(current.toString());
      if (base == null) {
        return null;
      }
      absolute = base.resolveUri(parsed);
    }
    final scheme = absolute.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final absoluteUrl = absolute.toString();
    final normalized = _normalizeUrl(absoluteUrl) ?? absoluteUrl;
    return _PreparedLink(anchorUrl: absoluteUrl, normalizedUrl: normalized);
  }

  Future<_LinkAction?> _showLinkActionSheet({
    required String url,
    String? title,
  }) async {
    if (!mounted) return null;
    final theme = Theme.of(context);
    final trimmedTitle = title?.trim();
    final label =
        trimmedTitle != null && trimmedTitle.isNotEmpty ? trimmedTitle : url;
    return showModalBottomSheet<_LinkAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  url,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.library_add),
                title: const Text('リンク先を読み上げに追加'),
                onTap: () => Navigator.of(context).pop(_LinkAction.addSingle),
              ),
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('選択以降の10件を読み上げに追加'),
                onTap: () => Navigator.of(context).pop(_LinkAction.addBatch),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<String>> _collectForwardLinks(
    InAppWebViewController controller,
    String targetUrl,
    int limit,
  ) async {
    final encodedTarget = jsonEncode(targetUrl);
    final script = '''
(() => {
  try {
    const target = $encodedTarget;
    const limit = $limit;
    const AD_KEYWORDS = ['広告'];
    const LIST_ITEM_SELECTOR = 'li,[role="listitem"],article';

    const norm = (s) => (s || '').replace(/\\s+/g, '').trim();
    const hasAdLabel = (el) => {
      if (!el) return false;
      const text = norm(el.textContent || '');
      if (!text || text.length > 20) {
        return false;
      }
      return AD_KEYWORDS.some((k) => text.includes(norm(k)));
    };

    const listItemCache = new WeakMap();
    const adListItems = new WeakSet();
    const cleanListItems = new WeakSet();

    const getListItem = (anchor) => {
      if (!anchor) return null;
      if (listItemCache.has(anchor)) {
        return listItemCache.get(anchor);
      }
      const container = anchor.closest ? anchor.closest(LIST_ITEM_SELECTOR) : null;
      listItemCache.set(anchor, container);
      return container;
    };

    const markListItem = (listItem, isAd) => {
      if (!listItem) return;
      if (isAd) {
        adListItems.add(listItem);
        cleanListItems.delete(listItem);
      } else {
        cleanListItems.add(listItem);
        adListItems.delete(listItem);
      }
    };

    const listItemHasAdLabel = (listItem) => {
      if (!listItem) return false;
      if (adListItems.has(listItem)) return true;
      if (cleanListItems.has(listItem)) return false;
      if (hasAdLabel(listItem)) {
        markListItem(listItem, true);
        return true;
      }
      const descendants = listItem.querySelectorAll('*');
      for (const node of descendants) {
        if (hasAdLabel(node)) {
          markListItem(listItem, true);
          return true;
        }
      }
      markListItem(listItem, false);
      return false;
    };

    const isInAdContainer = (anchor) => {
      const listItem = getListItem(anchor);
      if (!listItem) {
        return false;
      }
      return listItemHasAdLabel(listItem);
    };

    const anchors = Array.from(document.querySelectorAll('a[href]')).filter((a) => {
      const href = a.href || '';
      if (!href) return false;
      if (!/^https?:\\/\\//i.test(href)) {
        return false;
      }
      if (hasAdLabel(a)) {
        return false;
      }
      if (isInAdContainer(a)) {
        return false;
      }
      return true;
    });

    let startAnchor = document.activeElement;
    if (startAnchor && startAnchor.tagName !== 'A') {
      startAnchor = startAnchor.closest ? startAnchor.closest('a[href]') : null;
    }
    if (!startAnchor && target) {
      startAnchor = anchors.find((a) => (a.href || '') === target) || null;
    }
    if (!startAnchor) {
      return JSON.stringify({ ok: false, reason: 'no active anchor' });
    }
    let startIndex = anchors.findIndex((a) => a === startAnchor);
    if (startIndex < 0 && target) {
      startIndex = anchors.findIndex((a) => (a.href || '') === target);
    }
    if (startIndex < 0) {
      return JSON.stringify({ ok: false, reason: 'start filtered out' });
    }

    const collected = [];
    for (let i = startIndex; i < anchors.length && collected.length < limit; i++) {
      collected.push(anchors[i].href);
    }

    return JSON.stringify({ ok: true, links: collected });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
''';

    final raw = await controller.evaluateJavascript(source: script);
    final jsonStr = raw is String ? raw : raw?.toString();
    if (jsonStr == null || jsonStr.isEmpty) {
      return [];
    }
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
      final rawLinks = (decoded['links'] as List?) ?? <dynamic>[];
      return rawLinks.whereType<String>().toList();
    }
    return [];
  }

  Future<void> _captureMultipleArticles(List<String> urls) async {
    if (urls.isEmpty) {
      return;
    }
    if (!mounted) return;
    showAutoHideSnackBar(
      context,
      message: '${urls.length}件のリンクを解析しています…',
    );
    final inserted = <NewsItemRecord>[];
    var duplicateCount = 0;
    var failureCount = 0;
    for (final url in urls) {
      final normalized = _normalizeUrl(url) ?? url;
      try {
        final article = await _extractArticleFromUrl(normalized);
        if (article == null || article.content.isEmpty) {
          failureCount++;
          continue;
        }
        final saved = await _saveExtractedArticle(normalized, article);
        inserted.add(saved);
        _markSetAsAvailable();
      } on DuplicateArticleException {
        duplicateCount++;
      } catch (_) {
        failureCount++;
      }
    }
    if (!mounted) return;
    if (inserted.isEmpty) {
      final detail = (duplicateCount > 0 || failureCount > 0)
          ? '（重複$duplicateCount件/失敗$failureCount件）'
          : '';
      showAutoHideSnackBar(
        context,
        message: 'リンクを追加できませんでした$detail',
      );
      return;
    }
    showAutoHideSnackBar(
      context,
      message:
          '${inserted.length}件のリンクをキューに追加しました（重複$duplicateCount件/失敗$failureCount件）',
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'もとに戻す',
        onPressed: () {
          unawaited(_undoBatchInsert(inserted));
        },
      ),
    );
  }

  Future<void> _undoBatchInsert(List<NewsItemRecord> items) async {
    try {
      for (final item in items) {
        await _newsItemRepository.deleteArticle(item.id);
      }
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '追加を取り消しました。',
      );
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '取り消しに失敗しました: $e',
      );
    }
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
      _markSetAsAvailable();
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
    int loadCount = 0;
    bool triedReadMoreClick = false;
    _ExtractedArticle? firstArticle;
    final processedUrls = <String>{};

    headless = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        clearCache: true,
        isInspectable: kDebugMode ? true : false,
        safeBrowsingEnabled: kDebugMode ? false : true,
        supportMultipleWindows: true,
        javaScriptCanOpenWindowsAutomatically: true,
        disableLongPressContextMenuOnLinks: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([userScript]),
      onCreateWindow: (controller, createWindowRequest) async {
        final targetUrl = createWindowRequest.request.url;
        if (targetUrl != null) {
          await controller.loadUrl(urlRequest: URLRequest(url: targetUrl));
          return true;
        }
        return false;
      },
      onConsoleMessage: kDebugMode
          ? (controller, msg) => _logWithSave("WV console: ${msg.message}")
          : null,
      onLoadStop: (controller, loadedUrl) async {
        final loaded = loadedUrl?.toString();
        if (loaded != null && processedUrls.contains(loaded)) {
          _logWithSave("TEST_D 67 skip already processed $loaded");
          return;
        }
        if (loaded != null) {
          processedUrls.add(loaded);
        }
        _logWithSave("TEST_D 68 $loadCount $loadedUrl");
        loadCount++;
        try {
          if (loadedUrl?.host == "news.google.com") {
            return;
          }
          _logWithSave("TEST_D 69");

          final article = await _extractReadableArticle(controller);
          _logWithSave("TEST_D 70 ${article?.content}");
          if (loadCount == 1) {
            firstArticle = article;
          }

          if (!triedReadMoreClick && _looksTruncated(article)) {
            triedReadMoreClick = true;
            _logWithSave("TEST_D 71 _tryClickReadMore from now");
            final clicked = await _tryClickReadMore(controller);
            if (clicked) {
              _logWithSave("TEST_D 74 clicked");
              return;
            }
          }

          _logWithSave("TEST_D 73 ${completer.isCompleted}");
          if (!completer.isCompleted) {
            _logWithSave("TEST_D 75 completed");
            completer.complete(article ?? firstArticle);
          }
        } catch (_) {
          if (!completer.isCompleted) {
            completer.complete(firstArticle);
          }
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) {
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(firstArticle);
        }
      },
    );

    try {
      await headless.run();
      await headless.webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
      return await completer.future
          .timeout(const Duration(seconds: 20), onTimeout: () => firstArticle);
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
    _logWithSave("TEST_D 91 _extractReadableArticle $result");

    if (result['ok'] == true) {
      final title = (result['title'] as String?)?.trim();
      final html = result['html'] as String?;
      final textFallback = (result['text'] as String?) ?? '';
      if (html == null || html.trim().isEmpty) {
        final normalized = normalize(textFallback);
        if (normalized.isEmpty) {
          return null;
        }
        return _ExtractedArticle(title: title, content: normalized);
      }
      final extracted = _extractMainTextFromReadabilityHtml(html);
      final normalized =
          normalize(extracted.isNotEmpty ? extracted : textFallback);
      if (normalized.isEmpty) {
        return null;
      }
      return _ExtractedArticle(
        title: title,
        content: normalized,
        html: html,
      );
    } else {
      _logWithSave('Readability failed: ${result['error']}');
    }

    return null;
  }

  Future<bool> _tryClickReadMore(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: _clickReadMoreJs,
      );
      final jsonStr = raw is String ? raw : raw?.toString();
      if (jsonStr == null || jsonStr.isEmpty) {
        return false;
      }

      final Map<String, dynamic> result = jsonDecode(jsonStr);
      _logWithSave("TEST_D 72 _tryClickReadMore $result");
      if (result['ok'] == true && result['clicked'] == true) {
        return true;
      }
    } catch (e) {
      _logWithSave('Read more click failed: $e');
    }
    return false;
  }

  void _logWithSave(String message) {
    final line = '[${DateTime.now().toIso8601String()}] ${message.trimRight()}';
    debugPrint(line);
    unawaited(_appendLogLine(line));
  }

  Future<void> _appendLogLine(String line) async {
    try {
      final file = await _ensureLogFile();
      await _rotateLogFileIfNeeded(file);
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Log write failed: $e');
      }
    }
  }

  Future<File> _ensureLogFile() async {
    final file = File('${Directory.systemTemp.path}/$_logFileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<void> _rotateLogFileIfNeeded(File file) async {
    try {
      final length = await file.length();
      if (length < _maxLogFileBytes) {
        return;
      }
      final rotated = File('${file.path}.1');
      if (await rotated.exists()) {
        await rotated.delete();
      }
      await file.rename(rotated.path);
      await file.create();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Log rotation failed: $e');
      }
    }
  }

  bool _looksTruncated(_ExtractedArticle? article) {
    if (article == null) {
      return true;
    }
    final text = article.content.trim();
    if (text.length < 200) {
      return true;
    }
    final ret = _readMoreKeywords.any(text.contains);
    debugPrint("TEST_D 90 _looksTruncated $ret");
    return ret;
  }

  String _extractMainTextFromReadabilityHtml(String html) {
    final doc = html_parser.parse(html);
    dom.Element? root = doc.querySelector('[data-ual-view-type="detail"]') ??
        doc.querySelector('article') ??
        doc.body;
    if (root == null) {
      return '';
    }

    root
        .querySelectorAll('header, nav, aside, footer')
        .forEach((e) => e.remove());
    root.querySelectorAll('figcaption').forEach((e) => e.remove());
    root.querySelectorAll('#emotion-list').forEach((e) => e.remove());

    for (final sec in root.querySelectorAll('section')) {
      final heading = sec.querySelector('h1,h2,h3,h4,h5,h6')?.text ?? '';
      if (_containsAny(heading, const ['関連記事', '関連', 'あわせて読みたい'])) {
        sec.remove();
      }
    }

    final kept = <String>[];
    for (final p in root.querySelectorAll('p')) {
      final text = _normalizeSpaces(p.text);
      if (text.isEmpty) {
        continue;
      }
      if (_containsAny(text, const ['記事に関する報告', '問題を報告'])) {
        continue;
      }
      if (_containsAny(text, const [
        'コメント',
        '配信',
        '関連記事',
        'おすすめ',
        'シェア',
        'PR',
        '広告',
        '【写真あり】',
        '【図解】',
        'もっと読む',
        '続きを読む',
      ])) {
        if (text.length < 120) {
          continue;
        }
      }
      if (text.length < 35) {
        continue;
      }

      final linkTextLen = p.querySelectorAll('a').fold<int>(
            0,
            (sum, a) => sum + _normalizeSpaces(a.text).length,
          );
      final totalLen = text.length;
      final linkDensity = totalLen == 0 ? 0.0 : linkTextLen / totalLen;
      if (linkDensity > 0.60) {
        continue;
      }
      kept.add(text);
    }

    if (kept.isEmpty) {
      return '';
    }
    return kept.join('\n\n');
  }

  bool _containsAny(String s, List<String> needles) {
    for (final n in needles) {
      if (s.contains(n)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeSpaces(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String normalize(String s) {
    return s
        // NBSP を普通のスペースに
        .replaceAll('\u00A0', ' ')
        // 全角スペース
        .replaceAll('\u3000', ' ')
        // ゼロ幅文字
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '\n')
        // 連続する改行を1つに
        .replaceAll(RegExp(r'\n\s*\n+'), '\n')
        .replaceAll(RegExp(r'\t+'), ' ')
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
    final canControlSet = !_isCheckingSetExists && _hasExistingSet;
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
            onLongPressHitTestResult: (controller, hitTestResult) async {
              final type = hitTestResult.type;
              final isLink = type ==
                      InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE ||
                  type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE;
              if (!isLink) {
                return;
              }
              final focus = await controller.requestFocusNodeHref();
              final rawUrl = focus?.url.toString();
              if (rawUrl == null || rawUrl.isEmpty) {
                return;
              }
              final prepared = await _prepareLongPressLink(controller, rawUrl);
              if (prepared == null) {
                return;
              }
              _pendingLongPressLink = prepared;
              final action = await _showLinkActionSheet(
                url: prepared.anchorUrl,
                title: focus?.title,
              );
              if (action == _LinkAction.addSingle) {
                await _handleAddLinkFromContextMenu();
              } else if (action == _LinkAction.addBatch) {
                await _handleAddBatchFromContextMenu();
              } else {
                _pendingLongPressLink = null;
              }
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
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'このページを読み上げ',
                  onTap: () {
                    unawaited(_handleReadVisiblePage());
                  },
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: 'ニュースセット詳細に移動',
                  onTap: canControlSet ? _handleOpenSetDetail : null,
                  enabled: canControlSet,
                ),
                const SizedBox(height: 10),
                _ActionButton(
                  icon: Icons.settings,
                  tooltip: 'その他の操作',
                  onTap: _toggleActionMenu,
                ),
                const SizedBox(height: 10),
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
  const _ExtractedArticle({
    this.title,
    required this.content,
    this.html,
  });

  final String? title;
  final String content;
  final String? html;
}

enum _LinkAction {
  addSingle,
  addBatch,
}

class _PreparedLink {
  const _PreparedLink({
    required this.anchorUrl,
    required this.normalizedUrl,
  });

  final String anchorUrl;
  final String normalizedUrl;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = enabled
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final iconColor =
        enabled ? theme.colorScheme.onPrimaryContainer : theme.disabledColor;
    final radius = BorderRadius.circular(12);
    return Material(
      elevation: enabled ? 1.2 : 0,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: radius),
      color: backgroundColor,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Tooltip(
              message: tooltip,
              child: Icon(
                icon,
                size: 18,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> _readMoreKeywords = [
  '記事全文',
  '記事を読む',
  '記事全文を読む',
  '全文を読む',
  '続きを読む',
  'もっと読む',
  '続きはこちら',
  '記事の続き',
  'Read more',
];

const _readabilityExtractorJs = r'''
(() => {
  try {
    if (typeof Readability === 'undefined') {
      return JSON.stringify({ ok: false, error: 'Readability not found' });
    }
    const doc = document.cloneNode(true);
    const article = new Readability(doc).parse();

    if (!article) {
      return JSON.stringify({ ok: false, error: 'No article' });
    }

    const text = article.textContent || '';
    const html = article.content || '';
    const title = article.title || '';

    return JSON.stringify({
      ok: true,
      title,
      text,
      html
    });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
''';

final _clickReadMoreJs = _buildClickReadMoreJs();

String _buildClickReadMoreJs() {
  final keywordsJson = jsonEncode(_readMoreKeywords);
  return '''
(() => {
  try {
    console.log("TEST_D 101 _clickReadMoreJs start");
    const KEYWORDS = $keywordsJson;

    const norm = (s) => (s || '').replace(/\\s+/g, '').trim();

    const nodes = Array.from(document.querySelectorAll(
      'a,button,[role="button"],input[type="button"],input[type="submit"]'
    ));

    const getLabel = (el) => {
      const text = el.innerText || el.textContent || '';
      const aria = el.getAttribute('aria-label') || '';
      const title = el.getAttribute('title') || '';
      const value = (el.tagName === 'INPUT') ? (el.getAttribute('value') || '') : '';
      return norm(text) || norm(aria) || norm(title) || norm(value);
    };

    const isVisible = (el) => {
      const r = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      return r.width > 0 && r.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
    };

    const hit = nodes.find(el => {
      if (!el) return false;
      const label = getLabel(el);
      if (!label) return false;
      if (!isVisible(el)) return false;
      return KEYWORDS.some(k => label.includes(norm(k)));
    });
    console.log("TEST_D 100", hit);

    if (!hit) {
      return JSON.stringify({ ok: true, clicked: false });
    }

    const href = (hit.tagName === 'A') ? (hit.getAttribute('href') || '') : '';
    hit.click();

    return JSON.stringify({ ok: true, clicked: true, href });
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})()
''';
}
