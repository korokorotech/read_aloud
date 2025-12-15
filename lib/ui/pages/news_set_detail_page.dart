import 'dart:async';

import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/services/player_service.dart';
import 'package:read_aloud/ui/modals/news_set_create_modal.dart';
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
  final PlayerService _player = PlayerService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  NewsSetDetail? _detail;

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
                : _buildBody(isActiveSet),
          ),
          floatingActionButton: _detail == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add_link),
                  label: const Text('記事を追加'),
                  onPressed: () => _openWebViewForSet(_detail!),
                ),
        );
      },
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
          detail: detail,
          player: _player,
          isActiveSet: isActiveSet,
          onStartSet: () => unawaited(_player.startWithDetail(detail)),
        ),
      );
      children.add(const SizedBox(height: 16));

      for (var i = 0; i < detail.items.length; i++) {
        final item = detail.items[i];
        final isCurrent = isActiveSet &&
            _player.currentItems.isNotEmpty &&
            _player.currentIndex == i;
        children.add(
          _NewsItemCard(
            item: item,
            domain: _extractDomain(item.url),
            addedLabel:
                _formatDateTime(DateTime.fromMillisecondsSinceEpoch(item.addedAt)),
            isCurrent: isCurrent,
            onTap: () =>
                unawaited(_player.startWithDetail(detail, startIndex: i)),
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
    final result = await showModalBottomSheet<NewsSetCreateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => NewsSetCreateModal(
        initialName: detail.name,
        isNameEditable: false,
        title: 'ニュースセットに追加',
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final initialUrl = resolveInitialUrlForNewsSet(result);
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
    final domain =
        currentItem != null ? (Uri.tryParse(currentItem.url)?.host ?? currentItem.url) : '-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCurrentSet
                  ? '再生中 ${index + 1} / ${player.currentItems.length}'
                  : 'まだ再生していません',
              style: theme.titleMedium,
            ),
            if (currentItem != null) ...[
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
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: isCurrentSet && player.canPlayPrevious
                      ? player.playPrevious
                      : null,
                  iconSize: 28,
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: hasItems
                      ? (isCurrentSet ? player.togglePlayPause : onStartSet)
                      : null,
                  icon: Icon(isCurrentSet && player.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow),
                  label: Text(isCurrentSet && player.isPlaying ? '一時停止' : '再生'),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_next),
                  onPressed: isCurrentSet && player.canPlayNext
                      ? player.playNext
                      : null,
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
    final color = isCurrent
        ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
        : null;
    return Card(
      color: color,
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
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '再生対象',
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
