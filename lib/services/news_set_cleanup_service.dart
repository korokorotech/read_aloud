import 'package:flutter/foundation.dart';
import 'package:read_aloud/entities/news_set_retention_option.dart';
import 'package:read_aloud/repositories/news_set_repository.dart';
import 'package:read_aloud/services/app_settings.dart';

class NewsSetCleanupService {
  NewsSetCleanupService._();

  static final NewsSetCleanupService instance = NewsSetCleanupService._();

  final AppSettings _settings = AppSettings.instance;
  final NewsSetRepository _repository = NewsSetRepository();
  bool _hasRun = false;

  Future<void> run() async {
    if (_hasRun) return;
    _hasRun = true;

    try {
      final option = await _settings.getNewsSetRetentionOption();
      final days = option.days;
      if (days == null) {
        return;
      }

      final cutoff = DateTime.now().subtract(Duration(days: days));
      await _repository.deleteSetsNotUpdatedSince(cutoff);
    } catch (e, stack) {
      debugPrint('Failed to clean up old news sets: $e\n$stack');
    }
  }
}
