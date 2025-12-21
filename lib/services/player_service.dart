import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/services/app_settings.dart';

class PlayerService extends ChangeNotifier {
  PlayerService._() {
    _setupTts();
    unawaited(_loadPlaybackPreferences());
  }

  static final PlayerService instance = PlayerService._();

  final FlutterTts _flutterTts = FlutterTts();
  final NewsSetRepository _repository = NewsSetRepository();

  bool _isLoading = false;
  bool _isPlaying = false;
  String? _currentSetId;
  String? _currentSetName;
  List<NewsItemRecord> _items = [];
  int _currentIndex = 0;
  String? _errorMessage;
  Future<void>? _playbackFuture;
  bool _stopRequested = false;
  static const _interItemSilence = Duration(seconds: 1);
  static const _preArticleDelay = Duration(seconds: 1);
  static const _chunkEndCheckStartLength = 25;
  static const _chunkMaxLength = 500;
  static const _chunkDelimiters = {
    '、',
    '。',
    '\n',
    ',',
    '.',
    '/',
    '?',
    '？',
    '!',
    '！',
    '・',
    '）',
    ')',
    '」',
    '』',
  };
  bool _readPreviewBeforeArticle = true;
  double _playbackSpeed = 1.0;

  static const List<double> playbackSpeedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  bool get isLoading => _isLoading;
  bool get isPlaying => _isPlaying;
  String? get currentSetId => _currentSetId;
  String? get currentSetName => _currentSetName;
  int get currentIndex => _currentIndex;
  List<NewsItemRecord> get currentItems => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;
  double get playbackSpeed => _playbackSpeed;

  bool get canPlayNext =>
      _items.isNotEmpty && _currentIndex < _items.length - 1;
  bool get canPlayPrevious => _items.isNotEmpty && _currentIndex > 0;

  Future<void> _setupTts() async {
    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setLanguage('ja-JP');
    await _flutterTts.setSpeechRate(1);
    await _flutterTts.awaitSpeakCompletion(true);
    _flutterTts.setErrorHandler((msg) {
      _stopRequested = true;
      _isPlaying = false;
      _errorMessage = 'TTSエラー: $msg';
      notifyListeners();
    });
  }

  Future<bool> startSetById(String setId, {String? fallbackSetName}) async {
    _isLoading = true;
    _errorMessage = null;
    _currentSetId = setId;
    _currentSetName = fallbackSetName;
    notifyListeners();

    try {
      final detail = await _repository.fetchDetail(setId);
      if (detail == null || detail.items.isEmpty) {
        _isLoading = false;
        _isPlaying = false;
        _currentSetId = null;
        _currentSetName = null;
        _items = [];
        _errorMessage = '再生できる記事がありません。';
        notifyListeners();
        return false;
      }
      _isLoading = false;
      await startWithDetail(detail);
      return true;
    } catch (e) {
      _isLoading = false;
      _isPlaying = false;
      _currentSetId = null;
      _currentSetName = null;
      _items = [];
      _errorMessage = '再生キューの取得に失敗しました: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> startWithDetail(NewsSetDetail detail,
      {int startIndex = 0}) async {
    if (detail.items.isEmpty) {
      _errorMessage = '再生できる記事がありません。';
      _isPlaying = false;
      notifyListeners();
      return;
    }

    await _loadPlaybackPreferences();
    await _stopPlaybackLoop();
    _currentSetId = detail.id;
    _currentSetName = detail.name;
    _items = List.unmodifiable(detail.items);
    _currentIndex = startIndex.clamp(0, _items.length - 1);
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    await _startPlaybackLoop();
  }

  Future<void> togglePlayPause() async {
    if (_items.isEmpty) {
      _errorMessage = '再生する記事がありません。';
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      await stop();
    } else {
      await _startPlaybackLoop();
    }
  }

  Future<void> playNext() async {
    if (!canPlayNext) return;
    await _stopPlaybackLoop();
    _currentIndex += 1;
    notifyListeners();
    await _startPlaybackLoop();
  }

  Future<void> playPrevious() async {
    if (!canPlayPrevious) return;
    await _stopPlaybackLoop();
    _currentIndex -= 1;
    notifyListeners();
    await _startPlaybackLoop();
  }

  Future<void> selectIndex(int index) async {
    if (_items.isEmpty || index < 0 || index >= _items.length) {
      return;
    }
    await _stopPlaybackLoop();
    _currentIndex = index;
    notifyListeners();
    await _startPlaybackLoop();
  }

  Future<void> stop() async {
    await _stopPlaybackLoop();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if ((speed - _playbackSpeed).abs() < 0.0001) {
      return;
    }
    _playbackSpeed = speed;
    await _flutterTts.setSpeechRate(speed);
    notifyListeners();
    await AppSettings.instance.setPlaybackSpeed(speed);
  }

  Future<void> _startPlaybackLoop() async {
    if (_items.isEmpty || _currentIndex < 0 || _currentIndex >= _items.length) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    if (_playbackFuture != null) {
      return;
    }
    _stopRequested = false;
    _errorMessage = null;
    final future = _playbackLoop();
    _playbackFuture = future;
    unawaited(future);
  }

  Future<void> _stopPlaybackLoop() async {
    if (_playbackFuture == null) {
      await _flutterTts.stop();
      _stopRequested = false;
      _isPlaying = false;
      notifyListeners();
      return;
    }
    _stopRequested = true;
    await _flutterTts.stop();
    try {
      await _playbackFuture;
    } finally {
      _playbackFuture = null;
    }
  }

  Future<void> _playbackLoop() async {
    _isPlaying = true;
    notifyListeners();
    try {
      while (!_stopRequested && _currentIndex < _items.length) {
        final item = _items[_currentIndex];
        final played = await _playItem(item);
        if (_stopRequested) break;
        if (!played) {
          if (!_advanceToNextItem()) {
            break;
          }
          continue;
        }
        await _waitBeforeAdvancing();
        if (_stopRequested) break;
        if (!_advanceToNextItem()) {
          break;
        }
      }
    } finally {
      _playbackFuture = null;
      _isPlaying = false;
      notifyListeners();
      _stopRequested = false;
    }
  }

  Future<void> _waitBeforeAdvancing() async {
    await _waitWithStopCheck(_interItemSilence);
  }

  Future<void> _waitBeforeArticle() async {
    await _waitWithStopCheck(_preArticleDelay);
  }

  Future<void> _waitWithStopCheck(Duration duration) async {
    const tick = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    while (!_stopRequested && elapsed < duration) {
      final remaining = duration - elapsed;
      final delay = remaining < tick ? remaining : tick;
      await Future.delayed(delay);
      elapsed += delay;
    }
  }

  bool _advanceToNextItem() {
    if (canPlayNext) {
      _currentIndex += 1;
      notifyListeners();
      return true;
    }
    return false;
  }

  String _resolveTextForItem(NewsItemRecord item) {
    final article = item.articleText?.trim() ?? '';
    if (article.isNotEmpty) {
      return article;
    }
    return item.previewText;
  }

  Future<void> playStandaloneArticle({
    required String url,
    required String previewText,
    required String articleText,
  }) async {
    await _loadPlaybackPreferences();
    await _stopPlaybackLoop();
    final tempItem = NewsItemRecord(
      id: 'standalone_${DateTime.now().microsecondsSinceEpoch}',
      setId: '_standalone',
      url: url,
      previewText: previewText,
      articleText: articleText,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      orderIndex: 0,
    );
    final future = _playStandaloneRecord(tempItem);
    _playbackFuture = future;
    unawaited(future);
  }

  Future<void> _playStandaloneRecord(NewsItemRecord item) async {
    _stopRequested = false;
    _isPlaying = true;
    notifyListeners();
    try {
      final played = await _playItem(item);
      if (!played) {
        _errorMessage = '読み上げできるテキストがありません。';
      }
    } finally {
      _playbackFuture = null;
      _isPlaying = false;
      _stopRequested = false;
      notifyListeners();
    }
  }

  Future<void> _loadPlaybackPreferences() async {
    final settings = AppSettings.instance;
    _readPreviewBeforeArticle = await settings.getReadPreviewBeforeArticle();
    final storedSpeed = await settings.getPlaybackSpeed();
    if ((storedSpeed - _playbackSpeed).abs() >= 0.0001) {
      _playbackSpeed = storedSpeed;
      await _flutterTts.setSpeechRate(_playbackSpeed);
      notifyListeners();
    }
  }

  Future<bool> _playItem(NewsItemRecord item) async {
    final preview = item.previewText.trim();
    final article = item.articleText?.trim() ?? '';
    if (_readPreviewBeforeArticle && preview.isNotEmpty && article.isNotEmpty) {
      final previewPlayed = await _speakText(preview);
      if (_stopRequested) {
        return previewPlayed;
      }
      if (previewPlayed) {
        await _waitBeforeArticle();
      }
      if (_stopRequested) {
        return previewPlayed;
      }
      final articlePlayed = await _speakText(article);
      return previewPlayed || articlePlayed;
    }

    final text = _resolveTextForItem(item);
    return await _speakText(text);
  }

  Future<bool> _speakText(String text) async {
    final chunks = _splitIntoChunks(text);
    if (chunks.isEmpty) {
      return false;
    }
    for (final chunk in chunks) {
      if (_stopRequested) break;
      try {
        await _flutterTts.speak(chunk);
      } catch (e) {
        _errorMessage = 'TTSエラー: $e';
        _stopRequested = true;
        break;
      }
      if (_stopRequested) break;
    }
    return true;
  }

  List<String> _splitIntoChunks(String text) {
    if (text.isEmpty) {
      return const [];
    }
    final chunks = <String>[];
    var index = 0;
    while (index < text.length) {
      final nextIndex = _findChunkEnd(text, index);
      chunks.add(text.substring(index, nextIndex));
      index = nextIndex;
    }
    return chunks;
  }

  int _findChunkEnd(String text, int startIndex) {
    final remaining = text.length - startIndex;
    if (remaining <= _chunkMaxLength) {
      return text.length;
    }
    final searchStart =
        startIndex + _chunkEndCheckStartLength.clamp(0, remaining);
    final searchEnd =
        (startIndex + _chunkMaxLength).clamp(startIndex, text.length);
    for (var i = searchStart; i < searchEnd; i++) {
      final char = text[i];
      if (_chunkDelimiters.contains(char)) {
        return i + 1;
      }
    }
    return searchEnd;
  }
}
