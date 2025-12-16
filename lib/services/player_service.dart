import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';

class PlayerService extends ChangeNotifier {
  PlayerService._() {
    _setupTts();
  }

  static const CHUNK_END_CHECK_START_LENGTH = 500;
  static const CHUNK_MAX_LENGTH = 1000;

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

  bool get isLoading => _isLoading;
  bool get isPlaying => _isPlaying;
  String? get currentSetId => _currentSetId;
  String? get currentSetName => _currentSetName;
  int get currentIndex => _currentIndex;
  List<NewsItemRecord> get currentItems => List.unmodifiable(_items);
  String? get errorMessage => _errorMessage;

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
        final text = _resolveTextForItem(item);
        final chunks = _splitIntoChunks(text);
        if (chunks.isEmpty) {
          if (!_advanceToNextItem()) {
            break;
          }
          continue;
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
