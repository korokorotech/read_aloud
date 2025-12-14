import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.setId,
    this.initialSetName,
  });

  final String setId;
  final String? initialSetName;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final NewsSetRepository _repository = NewsSetRepository();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isLoading = true;
  bool _isPlaying = false;
  int _currentIndex = 0;
  NewsSetDetail? _detail;
  String? _errorMessage;
  late Future<void> _ttsInitFuture;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final detail = await _repository.fetchDetail(widget.setId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _isLoading = false;
        _currentIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'プレイリストを取得できませんでした: $e';
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
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.name ?? widget.initialSetName ?? 'プレイヤー'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: _loadDetail,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _PlayerErrorView(
                    message: _errorMessage!,
                    onRetry: _loadDetail,
                  )
                : detail == null
                    ? const Center(child: Text('セットが見つかりませんでした。'))
                    : _buildPlayer(detail),
      ),
    );
  }

  Widget _buildPlayer(NewsSetDetail detail) {
    if (detail.items.isEmpty) {
      return const Center(
        child: Text('この記事セットには再生可能な記事がありません。'),
      );
    }

    final currentItem = detail.items[_currentIndex];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '再生中 ${_currentIndex + 1} / ${detail.items.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentItem.previewText,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Uri.tryParse(currentItem.url)?.host ?? currentItem.url,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.skip_previous),
                onPressed: _currentIndex > 0 ? () => _skipTo(-1) : null,
                iconSize: 32,
              ),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: _handlePlayOrPause,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    const SizedBox(width: 8),
                    Text(_isPlaying ? '一時停止' : '再生'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                icon: const Icon(Icons.skip_next),
                onPressed: _currentIndex < detail.items.length - 1
                    ? () => _skipTo(1)
                    : null,
                iconSize: 32,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: detail.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = detail.items[index];
                final isCurrent = index == _currentIndex;
                return ListTile(
                  tileColor: isCurrent
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                      : null,
                  title: Text(
                    item.previewText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    Uri.tryParse(item.url)?.host ?? item.url,
                  ),
                  leading: isCurrent
                      ? const Icon(Icons.volume_up)
                      : Text('${index + 1}'),
                  onTap: () {
                    setState(() {
                      _currentIndex = index;
                    });
                    if (_isPlaying) {
                      unawaited(_playCurrent());
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerErrorView extends StatelessWidget {
  const _PlayerErrorView({required this.message, required this.onRetry});

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
