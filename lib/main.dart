import 'package:flutter/material.dart';

void main() {
  runApp(const ReadAloudApp());
}

class ReadAloudApp extends StatelessWidget {
  const ReadAloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Read Aloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

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

  void _handleCreateNewSet() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('新規作成のモックです。')),
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
