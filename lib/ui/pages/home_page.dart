import 'package:flutter/material.dart';
import 'package:read_aloud/ui/modals/news_set_create_modal.dart';
import 'package:read_aloud/ui/routes/app_router.dart';

class NewsSet {
  NewsSet({
    required this.name,
    required this.articleCount,
    required this.updatedAt,
  });

  final String name;
  final int articleCount;
  final DateTime updatedAt;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<NewsSet> _savedSets = [
    NewsSet(
      name: '朝のながら聴き',
      articleCount: 12,
      updatedAt: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    NewsSet(
      name: 'AIリサーチセット',
      articleCount: 7,
      updatedAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 12)),
    ),
    NewsSet(
      name: 'あとで読む（週末）',
      articleCount: 23,
      updatedAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    ),
  ];

  DateTime? _lastGeneratedDate;
  int _generatedCountForDay = 0;

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

    final initialUrl = _resolveInitialUrl(result);
    if (initialUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('遷移先URLを決定できませんでした。')),
      );
      return;
    }

    final tempSetId = _generateTempSetId();
    context.goWebView(
      setId: tempSetId,
      setName: result.setName,
      initialUrl: initialUrl,
      openAddMode: result.option == NewsSetAddOption.customUrl,
    );
  }

  void _handleOpenSet(NewsSet set) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${set.name}" を開く想定です。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('設定画面はまだありません。')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ニュースセット',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _savedSets.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        itemCount: _savedSets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final set = _savedSets[index];
                          return _NewsSetCard(
                            newsSet: set,
                            subtitle:
                                '${set.articleCount}件・最終更新 ${_formatUpdatedAt(set.updatedAt)}',
                            onTap: () => _handleOpenSet(set),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('＋ 新規作成'),
            onPressed: _handleCreateNewSet,
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

  Uri? _resolveInitialUrl(NewsSetCreateResult result) {
    switch (result.option) {
      case NewsSetAddOption.searchGoogle:
        final query = Uri.encodeQueryComponent(result.setName);
        return Uri.parse('https://www.google.com/search?q=$query');
      case NewsSetAddOption.googleNews:
        return Uri.parse('https://news.google.com/home?hl=ja&gl=JP&ceid=JP:ja');
      case NewsSetAddOption.customUrl:
        return result.customUrl;
    }
  }

  String _generateTempSetId() =>
      'set-${DateTime.now().millisecondsSinceEpoch}';

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
}

class _NewsSetCard extends StatelessWidget {
  const _NewsSetCard({
    required this.newsSet,
    required this.subtitle,
    required this.onTap,
  });

  final NewsSet newsSet;
  final String subtitle;
  final VoidCallback onTap;

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
            '「＋ 新規作成」からセットを作成して\nお気に入りの記事をキューに追加しましょう',
            style:
                Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
