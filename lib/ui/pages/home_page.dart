import 'dart:async';

import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_set_summary.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/services/player_service.dart';
import 'package:read_aloud/ui/modals/news_set_create_modal.dart';
import 'package:read_aloud/ui/routes/app_router.dart';
import 'package:read_aloud/ui/widgets/snack_bar_helper.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final NewsSetRepository _newsSetRepository = NewsSetRepository();
  final PlayerService _player = PlayerService.instance;
  List<NewsSetSummary> _newsSets = [];
  bool _isLoading = true;
  String? _errorMessage;

  DateTime? _lastGeneratedDate;
  int _generatedCountForDay = 0;

  @override
  void initState() {
    super.initState();
    _loadNewsSets();
  }

  Future<void> _handleCreateNewSet() async {
    final (initialName, suggestedDate, suggestedSequence) =
        _buildDefaultSetNameSuggestion();
    final result = await showModalBottomSheet<NewsSetCreateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => NewsSetCreateModal(
        initialName: initialName,
      ),
    );

    if (!mounted) {
      return;
    }

    if (result == null) {
      return;
    }

    _commitDefaultSetNameSuggestion(suggestedDate, suggestedSequence);

    final initialUrl = resolveInitialUrlForNewsSet(result);
    if (initialUrl == null) {
      showAutoHideSnackBar(
        context,
        message: '遷移先URLを決定できませんでした。',
      );
      return;
    }

    final tempSetId = _generateTempSetId();
    await context.pushWebView(
      setId: tempSetId,
      setName: result.setName,
      initialUrl: initialUrl,
      openAddMode: result.option == NewsSetAddOption.customUrl,
    );
    if (!mounted) return;
    await _loadNewsSets(showSpinner: false);
  }

  Future<void> _handleOpenSet(NewsSetSummary set) async {
    await context.pushSetDetail(set.id);
    if (!mounted) return;
    await _loadNewsSets(showSpinner: false);
  }

  Future<void> _handlePlaySet(NewsSetSummary set) async {
    final success =
        await _player.startSetById(set.id, fallbackSetName: set.name);
    if (!mounted) return;
    if (!success) {
      final message = _player.errorMessage ?? '再生できませんでした。';
      showAutoHideSnackBar(
        context,
        message: message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ニュースセット一覧'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              showAutoHideSnackBar(
                context,
                message: '設定画面はまだありません。',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: () =>
                                  _loadNewsSets(showSpinner: false),
                              child: _errorMessage != null
                                  ? _ErrorList(
                                      message: _errorMessage!,
                                      onRetry: () => _loadNewsSets(),
                                    )
                                  : _newsSets.isEmpty
                                      ? const _EmptyList()
                                      : AnimatedBuilder(
                                          animation: _player,
                                          builder: (context, _) {
                                            return ListView.separated(
                                              physics:
                                                  const AlwaysScrollableScrollPhysics(),
                                              padding: const EdgeInsets.only(
                                                bottom: 160,
                                                top: 16,
                                              ),
                                              itemCount: _newsSets.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 12),
                                              itemBuilder: (context, index) {
                                                final set = _newsSets[index];
                                                final isActive =
                                                    _player.currentSetId ==
                                                        set.id;
                                                final isPlaying = isActive &&
                                                    _player.isPlaying;
                                                final isLoadingPlayer =
                                                    isActive &&
                                                        _player.isLoading;
                                                return _NewsSetCard(
                                                  newsSet: set,
                                                  subtitle:
                                                      '${set.articleCount}件・最終更新 ${_formatUpdatedAt(set.updatedAt)}',
                                                  onTap: () =>
                                                      _handleOpenSet(set),
                                                  onPlay: () =>
                                                      _handlePlaySet(set),
                                                  onTogglePlay:
                                                      _player.togglePlayPause,
                                                  isActive: isActive,
                                                  isPlaying: isPlaying,
                                                  isLoading: isLoadingPlayer,
                                                );
                                              },
                                            );
                                          },
                                        ),
                            ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                bottom: 112,
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  elevation: 6,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'ニュースセットを新規作成',
                    onPressed: _handleCreateNewSet,
                    icon: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _player,
                builder: (context, _) => Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildPlayerControls(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatUpdatedAt(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference < const Duration(hours: 24) && now.day == dateTime.day) {
      return '今日 ${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
    }

    return '${dateTime.year}/${_twoDigits(dateTime.month)}/${_twoDigits(dateTime.day)}'
        ' ${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
  }

  String _generateTempSetId() => 'set-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _handleOpenCurrentSet() async {
    final setId = _player.currentSetId;
    if (setId == null) {
      return;
    }
    await context.pushSetDetail(setId);
    if (!mounted) return;
    await _loadNewsSets(showSpinner: false);
  }

  void _handlePlayFirstAvailableSet() {
    if (_newsSets.isEmpty) {
      return;
    }
    unawaited(_handlePlaySet(_newsSets.first));
  }

  Widget _buildPlayerControls(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = _player.isLoading;
    final hasAnySet = _newsSets.isNotEmpty;
    final hasActiveSet =
        _player.currentSetId != null && _player.currentItems.isNotEmpty;
    final surfaceColor = theme.colorScheme.surface.withOpacity(0.95);
    final outlineColor = theme.colorScheme.outlineVariant;

    IconButton buildControlButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton.filledTonal(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(12),
        ),
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }

    final playIcon = hasActiveSet && _player.isPlaying
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final playTooltip = hasActiveSet && _player.isPlaying ? '一時停止' : '再生';

    final playAction = !hasAnySet || isLoading
        ? null
        : hasActiveSet
            ? _player.togglePlayPause
            : () => _handlePlayFirstAvailableSet();

    final previousAction =
        (!hasAnySet || !hasActiveSet || !_player.canPlayPrevious || isLoading)
            ? null
            : () => _player.playPrevious();

    final nextAction =
        (!hasAnySet || !hasActiveSet || !_player.canPlayNext || isLoading)
            ? null
            : () => _player.playNext();

    final openSetAction = (!hasAnySet || !hasActiveSet || isLoading)
        ? null
        : _handleOpenCurrentSet;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: outlineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            buildControlButton(
              icon: Icons.skip_previous_rounded,
              tooltip: '一つ前',
              onPressed: previousAction,
            ),
            buildControlButton(
              icon: playIcon,
              tooltip: playTooltip,
              onPressed: playAction,
            ),
            buildControlButton(
              icon: Icons.skip_next_rounded,
              tooltip: '一つ先',
              onPressed: nextAction,
            ),
            buildControlButton(
              icon: Icons.open_in_new_rounded,
              tooltip: '再生中ニュースセット',
              onPressed: openSetAction,
            ),
          ],
        ),
      ),
    );
  }

  (String, DateTime, int) _buildDefaultSetNameSuggestion() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isSameDay =
        _lastGeneratedDate != null && _isSameDate(_lastGeneratedDate!, today);
    final nextSequence = isSameDay ? _generatedCountForDay + 1 : 1;
    final dateStr = '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}';
    final suffix = _twoDigits(nextSequence);
    return ('$dateStr-$suffix', today, nextSequence);
  }

  void _commitDefaultSetNameSuggestion(DateTime date, int sequence) {
    _lastGeneratedDate = date;
    _generatedCountForDay = sequence;
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  Future<void> _loadNewsSets({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final sets = await _newsSetRepository.fetchSummaries();
      if (!mounted) return;
      setState(() {
        _newsSets = sets;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ニュースセットを取得できませんでした: $e';
        _isLoading = false;
      });
    }
  }
}

class _NewsSetCard extends StatelessWidget {
  const _NewsSetCard({
    required this.newsSet,
    required this.subtitle,
    required this.onTap,
    required this.onPlay,
    required this.onTogglePlay,
    required this.isActive,
    required this.isPlaying,
    required this.isLoading,
  });

  final NewsSetSummary newsSet;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onTogglePlay;
  final bool isActive;
  final bool isPlaying;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(14),
                child: Icon(
                  Icons.queue_music,
                  color: primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      newsSet.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        icon: isActive && isPlaying
                            ? const Icon(Icons.pause)
                            : const Icon(Icons.play_arrow),
                        label: Text(
                            isActive ? (isPlaying ? '一時停止' : '再生再開') : '再生'),
                        onPressed: isLoading
                            ? null
                            : (isActive ? onTogglePlay : onPlay),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final color = Colors.grey[500];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            color: color,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(
            '保存されたニュースセットがありません',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '右下の＋ボタンからセットを作成して\nお気に入りの記事をキューに追加しましょう',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 60),
        _EmptyState(),
      ],
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 60),
        Center(
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
        ),
      ],
    );
  }
}
