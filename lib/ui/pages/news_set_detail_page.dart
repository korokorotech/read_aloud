import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/entities/news_set_add_option.dart';
import 'package:read_aloud/entities/preferred_news_source.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/repositories/news_item_repository.dart';
import 'package:read_aloud/services/app_settings.dart';
import 'package:read_aloud/services/player_service.dart';
import 'package:read_aloud/ui/modals/news_set_create_modal.dart';
import 'package:read_aloud/ui/pages/article_web_view_page.dart';
import 'package:read_aloud/ui/routes/app_router.dart';
import 'package:read_aloud/ui/widgets/snack_bar_helper.dart';

class NewsSetDetailPage extends StatefulWidget {
  const NewsSetDetailPage({
    super.key,
    required this.setId,
  });

  final String setId;

  @override
  State<NewsSetDetailPage> createState() => _NewsSetDetailPageState();
}

class _NewsSetDetailPageState extends State<NewsSetDetailPage> {
  final NewsSetRepository _repository = NewsSetRepository();
  final NewsItemRepository _newsItemRepository = NewsItemRepository();
  final PlayerService _player = PlayerService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  NewsSetDetail? _detail;
  String? _editingName;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.name ?? 'ニュースセット詳細';
    return AnimatedBuilder(
      animation: _player,
      builder: (context, _) {
        final isActiveSet = _player.currentSetId == widget.setId;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    _editingName ?? title,
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
            actions: [
              if (kDebugMode && _detail != null)
                IconButton(
                  tooltip: 'デバッグ:本文一覧を表示',
                  icon: const Icon(Icons.bug_report_outlined),
                  onPressed: _showDebugNewsItems,
                ),
            ],
          ),
          body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(isActiveSet),
          ),
          floatingActionButton: _detail == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add_link),
                  label: const Text('記事を追加'),
                  onPressed: _handleAddItemToSet,
                ),
        );
      },
    );
  }

  Future<void> _showDebugNewsItems() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NewsItemsDebugSheet(items: detail.items),
    );
  }

  Widget _buildBody(bool isActiveSet) {
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

    final listChildren = <Widget>[];
    if (detail.items.isEmpty) {
      listChildren.add(const _EmptyItemsState());
    } else {
      for (var i = 0; i < detail.items.length; i++) {
        final item = detail.items[i];
        final isCurrent = isActiveSet &&
            _player.currentItems.isNotEmpty &&
            _player.currentIndex == i;
        listChildren.add(
          _NewsItemCard(
            item: item,
            domain: _extractDomain(item.url),
            addedLabel: _formatDateTime(
              DateTime.fromMillisecondsSinceEpoch(item.addedAt),
            ),
            isCurrent: isCurrent,
            onTap: () =>
                unawaited(_player.startWithDetail(detail, startIndex: i)),
            onOpenUrl: () => _openNewsItemUrl(item),
            onDelete: () => _handleDeleteItem(item),
          ),
        );
        listChildren.add(const SizedBox(height: 12));
      }
    }
    listChildren.add(const SizedBox(height: 140));

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: _PlaybackSection(
            detail: detail,
            player: _player,
            isActiveSet: isActiveSet,
            onStartSet: () => unawaited(_player.startWithDetail(detail)),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadDetail(showSpinner: false),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: listChildren,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAddItemToSet() async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    await _openWebViewForSet(detail);
  }

  Future<void> _openWebViewForSet(NewsSetDetail detail) async {
    final settings = AppSettings.instance;
    final defaultOption = await settings.getDefaultAddOption();
    final preferredSource = await settings.getPreferredNewsSource();
    final result = await showModalBottomSheet<NewsSetCreateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => NewsSetCreateModal(
        initialName: detail.name,
        title: 'ニュースセットに追加',
        initialOption: defaultOption,
        preferredNewsSource: preferredSource,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final initialUrl = resolveInitialUrlForNewsSet(
      result,
      newsSource: preferredSource,
    );
    if (initialUrl == null) {
      showAutoHideSnackBar(
        context,
        message: '遷移先URLを決定できませんでした。',
      );
      return;
    }

    await context.pushWebView(
      setId: detail.id,
      setName: result.setName,
      initialUrl: initialUrl,
      openAddMode: result.option == NewsSetAddOption.customUrl,
    );
    if (!mounted) return;
    await _loadDetail(showSpinner: false);
  }

  Future<void> _openNewsItemUrl(NewsItemRecord item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '記事のURLが不正です。',
      );
      return;
    }

    final title = item.previewText.trim().isEmpty
        ? _extractDomain(item.url)
        : item.previewText;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleWebViewPage(
          initialUrl: uri,
          title: title,
        ),
      ),
    );
  }

  Future<void> _handleDeleteItem(NewsItemRecord item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('この記事を削除しますか？'),
          content: Text(
            '「${item.previewText.isEmpty ? item.url : item.previewText}」をセットから削除します。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _newsItemRepository.deleteArticle(item.id);
      if (!mounted) return;
      showAutoHideSnackBar(context, message: '記事を削除しました。');
      await _loadDetail(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      showAutoHideSnackBar(
        context,
        message: '削除に失敗しました: $e',
      );
    }
  }

  Future<void> _handleRename() async {
    final currentDetail = _detail;
    if (currentDetail == null) {
      return;
    }

    final controller = TextEditingController(text: currentDetail.name);
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

    if (!mounted || newName == null || newName.isEmpty) {
      return;
    }
    setState(() {
      _editingName = newName;
      _detail = currentDetail.copyWith(name: newName);
    });
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
      setState(() {
        _detail = detail;
        _editingName = detail?.name;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'セット情報の取得に失敗しました: $e';
        _isLoading = false;
      });
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

  String _extractDomain(String url) => Uri.tryParse(url)?.host ?? 'unknown';
}

class _NewsItemsDebugSheet extends StatelessWidget {
  const _NewsItemsDebugSheet({required this.items});

  final List<NewsItemRecord> items;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'デバッグ: 本文一覧',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '閉じる',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('ニュースアイテムがありません'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final title = item.previewText.isEmpty
                            ? item.url
                            : item.previewText;
                        final rawArticle = item.articleText ?? '';
                        final hasArticle = rawArticle.trim().isNotEmpty;
                        final article = hasArticle ? rawArticle : '(本文なし)';
                        return Card(
                          child: ExpansionTile(
                            title: Text(
                              '${index + 1}. $title',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: SelectableText(
                                  article,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
    required this.detail,
    required this.player,
    required this.isActiveSet,
    required this.onStartSet,
  });

  final NewsSetDetail detail;
  final PlayerService player;
  final bool isActiveSet;
  final VoidCallback onStartSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hasItems = detail.items.isNotEmpty;
    final isCurrentSet = isActiveSet && player.currentItems.isNotEmpty;
    final index = isCurrentSet ? player.currentIndex : 0;
    final currentItem = isCurrentSet
        ? player.currentItems[index]
        : (hasItems ? detail.items.first : null);
    final domain = currentItem != null
        ? (Uri.tryParse(currentItem.url)?.host ?? currentItem.url)
        : '-';

    final statusText = isCurrentSet
        ? '再生中 ${index + 1} / ${player.currentItems.length}'
        : 'まだ再生していません';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          statusText,
          style: theme.labelSmall?.copyWith(color: Colors.black54),
        ),
        if (currentItem != null) ...[
          const SizedBox(height: 6),
          Text(
            currentItem.previewText,
            style: theme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              icon: const Icon(Icons.skip_previous),
              tooltip: '前の記事',
              onPressed: isCurrentSet && player.canPlayPrevious
                  ? player.playPrevious
                  : null,
              iconSize: 24,
            ),
            const SizedBox(width: 16),
            IconButton.filled(
              icon: Icon(
                isCurrentSet && player.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              tooltip: isCurrentSet && player.isPlaying ? '一時停止' : '再生',
              onPressed: hasItems
                  ? (isCurrentSet ? player.togglePlayPause : onStartSet)
                  : null,
              iconSize: 24,
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              icon: const Icon(Icons.skip_next),
              tooltip: '次の記事',
              onPressed:
                  isCurrentSet && player.canPlayNext ? player.playNext : null,
              iconSize: 24,
            ),
          ],
        ),
      ],
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
    this.onOpenUrl,
    this.onDelete,
  });

  final NewsItemRecord item;
  final String domain;
  final String addedLabel;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback? onOpenUrl;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final color = isCurrent
        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
        : null;
    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.previewText,
                      style:
                          theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'この記事を削除',
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 18,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$domain ・ $addedLabel',
                style: theme.bodySmall?.copyWith(color: Colors.black54),
              ),
              if (onOpenUrl != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('記事を開く'),
                    onPressed: onOpenUrl,
                  ),
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
