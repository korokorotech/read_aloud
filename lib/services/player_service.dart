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
    _flutterTts.setCompletionHandler(_handlePlaybackComplete);
    _flutterTts.setErrorHandler((msg) {
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

    _currentSetId = detail.id;
    _currentSetName = detail.name;
    _items = List.unmodifiable(detail.items);
    _currentIndex = startIndex.clamp(0, _items.length - 1);
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> togglePlayPause() async {
    if (_items.isEmpty) {
      _errorMessage = '再生する記事がありません。';
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      await _flutterTts.stop();
      _isPlaying = false;
      notifyListeners();
    } else {
      await _playCurrent();
    }
  }

  Future<void> playNext() async {
    if (!canPlayNext) return;
    _currentIndex += 1;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> playPrevious() async {
    if (!canPlayPrevious) return;
    _currentIndex -= 1;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> selectIndex(int index) async {
    if (_items.isEmpty || index < 0 || index >= _items.length) {
      return;
    }
    _currentIndex = index;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> _playCurrent() async {
    if (_items.isEmpty) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    final item = _items[_currentIndex];
    final text =
        item.articleText?.trim().isNotEmpty == true ? item.articleText! : item.previewText;
    _isPlaying = true;
    _errorMessage = null;
    notifyListeners();
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  void _handlePlaybackComplete() {
    if (canPlayNext) {
      _currentIndex += 1;
      notifyListeners();
      unawaited(_playCurrent());
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }
}
