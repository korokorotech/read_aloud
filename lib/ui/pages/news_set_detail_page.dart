import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/ui/routes/app_router.dart';

class NewsSetDetailPage extends StatefulWidget {
  const NewsSetDetailPage({
    super.key,
    required this.setId,
    this.autoStartPlayback = false,
  });

  final String setId;
  final bool autoStartPlayback;

  @override
  State<NewsSetDetailPage> createState() => _NewsSetDetailPageState();
}

class _NewsSetDetailPageState extends State<NewsSetDetailPage> {
  final NewsSetRepository _repository = NewsSetRepository();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isLoading = true;
  String? _errorMessage;
  NewsSetDetail? _detail;
  bool _isPlaying = false;
  int _currentIndex = 0;
  late Future<void> _ttsInitFuture;
  bool _shouldAutoStart = false;

  @override
  void initState() {
    super.initState();
    _shouldAutoStart = widget.autoStartPlayback;
    _ttsInitFuture = _setupTts();
    _loadDetail();
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
    _flutterTts.setCompletionHandler(_handlePlaybackComplete);
    _flutterTts.setErrorHandler((msg) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('TTSエラー: $msg')));
    });
  }

  void _handlePlaybackComplete() {
    if (!mounted) return;
    final detail = _detail;
    if (detail == null) {
      setState(() {
        _isPlaying = false;
      });
      return;
    }
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= detail.items.length) {
      setState(() {
        _isPlaying = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('再生が完了しました。')));
    } else {
      setState(() {
        _currentIndex = nextIndex;
      });
      unawaited(_playCurrent());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.name ?? 'ニュースセット詳細';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () => _loadDetail(),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
      floatingActionButton: _detail == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add_link),
              label: const Text('記事を追加'),
              onPressed: () => _openWebViewForSet(_detail!),
            ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _DetailErrorView(
        message: _errorMessage!,
        onRetry: () => _loadDetail(),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return RefreshIndicator(
        onRefresh: () => _loadDetail(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('ニュースセットが見つかりませんでした。')),
          ],
        ),
      );
    }

    final children = <Widget>[
      _SetHeaderSection(
        detail: detail,
        updatedLabel: _formatDateTime(detail.updatedAt),
      ),
      const SizedBox(height: 16),
    ];

    if (detail.items.isEmpty) {
      children.add(const _EmptyItemsState());
    } else {
      children.add(
        _PlaybackSection(
          currentItem: detail.items[_currentIndex],
          currentIndex: _currentIndex,
          totalCount: detail.items.length,
          isPlaying: _isPlaying,
          onPlayPause: _handlePlayOrPause,
          onNext: _currentIndex < detail.items.length - 1
              ? () => _skipTo(1)
              : null,
          onPrev: _currentIndex > 0 ? () => _skipTo(-1) : null,
        ),
      );
      children.add(const SizedBox(height: 16));

      for (var i = 0; i < detail.items.length; i++) {
        final item = detail.items[i];
        children.add(
          _NewsItemCard(
            item: item,
            domain: _extractDomain(item.url),
            addedLabel:
                _formatDateTime(DateTime.fromMillisecondsSinceEpoch(item.addedAt)),
            isCurrent: i == _currentIndex,
            onTap: () => _handleSelectItem(i),
          ),
        );
        children.add(const SizedBox(height: 12));
      }
    }

    return RefreshIndicator(
      onRefresh: () => _loadDetail(showSpinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

  Future<void> _openWebViewForSet(NewsSetDetail detail) async {
    final uri =
        Uri.parse('https://news.google.com/home?hl=ja&gl=JP&ceid=JP:ja');
    await context.pushWebView(
      setId: detail.id,
      setName: detail.name,
      initialUrl: uri,
      openAddMode: false,
    );
    if (!mounted) return;
    await _loadDetail(showSpinner: false);
  }

  Future<void> _loadDetail({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final detail = await _repository.fetchDetail(widget.setId);
      if (!mounted) return;
      var nextIndex = _currentIndex;
      if (detail == null || detail.items.isEmpty) {
        nextIndex = 0;
      } else {
        nextIndex = nextIndex.clamp(0, detail.items.length - 1);
      }
      setState(() {
        _detail = detail;
        _isLoading = false;
        _errorMessage = null;
        _currentIndex = nextIndex;
      });
      if (_shouldAutoStart && detail != null && detail.items.isNotEmpty) {
        _shouldAutoStart = false;
        unawaited(_playCurrent());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'セット情報の取得に失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _playCurrent() async {
    final detail = _detail;
    if (detail == null || detail.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('再生する記事がありません。')));
      return;
    }
    await _ttsInitFuture;
    final item = detail.items[_currentIndex];
    final text = item.articleText?.trim().isNotEmpty == true
        ? item.articleText!
        : item.previewText;
    setState(() {
      _isPlaying = true;
    });
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> _handlePlayOrPause() async {
    if (_isPlaying) {
      await _flutterTts.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
      });
    } else {
      await _playCurrent();
    }
  }

  Future<void> _skipTo(int offset) async {
    final detail = _detail;
    if (detail == null || detail.items.isEmpty) {
      return;
    }
    final newIndex = (_currentIndex + offset).clamp(0, detail.items.length - 1);
    if (newIndex == _currentIndex) {
      return;
    }
    setState(() {
      _currentIndex = newIndex;
    });
    if (_isPlaying) {
      await _playCurrent();
    }
  }

  void _handleSelectItem(int index) {
    final detail = _detail;
    if (detail == null || index == _currentIndex) {
      return;
    }
    setState(() {
      _currentIndex = index;
    });
    if (_isPlaying) {
      unawaited(_playCurrent());
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference < const Duration(hours: 24) && now.day == dateTime.day) {
      final hh = dateTime.hour.toString().padLeft(2, '0');
      final mm = dateTime.minute.toString().padLeft(2, '0');
      return '今日 $hh:$mm';
    }
    final yyyy = dateTime.year.toString();
    final mm = dateTime.month.toString().padLeft(2, '0');
    final dd = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final min = dateTime.minute.toString().padLeft(2, '0');
    return '$yyyy/$mm/$dd $hh:$min';
  }

  String _extractDomain(String url) =>
      Uri.tryParse(url)?.host ?? 'unknown';
}

class _SetHeaderSection extends StatelessWidget {
  const _SetHeaderSection({
    required this.detail,
    required this.updatedLabel,
  });

  final NewsSetDetail detail;
  final String updatedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.name,
          style: theme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '記事 ${detail.items.length} 件',
          style: theme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '最終更新 $updatedLabel',
          style: theme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class _EmptyItemsState extends StatelessWidget {
  const _EmptyItemsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'この記事セットにはまだアイテムがありません',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '右下の「記事を追加」からWebViewを開き、気になる記事を追加してください。',
              style: theme.bodyMedium?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackSection extends StatelessWidget {
  const _PlaybackSection({
    required this.currentItem,
    required this.currentIndex,
    required this.totalCount,
    required this.isPlaying,
    required this.onPlayPause,
    this.onNext,
    this.onPrev,
  });

  final NewsItemRecord currentItem;
  final int currentIndex;
  final int totalCount;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final domain = Uri.tryParse(currentItem.url)?.host ?? currentItem.url;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '再生中 ${currentIndex + 1} / $totalCount',
              style: theme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              currentItem.previewText,
              style: theme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              domain,
              style: theme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: onPrev,
                  iconSize: 28,
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: onPlayPause,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(isPlaying ? '一時停止' : '再生'),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_next),
                  onPressed: onNext,
                  iconSize: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsItemCard extends StatelessWidget {
  const _NewsItemCard({
    required this.item,
    required this.domain,
    required this.addedLabel,
    this.isCurrent = false,
    this.onTap,
  });

  final NewsItemRecord item;
  final String domain;
  final String addedLabel;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final cardColor =
        isCurrent ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : null;
    return Card(
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.previewText,
                style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '$domain ・ $addedLabel',
                style: theme.bodySmall?.copyWith(color: Colors.black54),
              ),
              if (isCurrent) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up,
                        size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '再生中',
                      style: theme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }
}
