import 'package:read_aloud/entities/news_set_add_option.dart';
import 'package:read_aloud/entities/preferred_news_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _keyDefaultAddOption = 'default_add_option';
  static const _keyPreferredNewsSource = 'preferred_news_source';
  static const _keyReadPreviewBeforeArticle =
      'read_preview_before_article_enabled';
  static const _keyPlaybackSpeed = 'playback_speed';

  Future<NewsSetAddOption> getDefaultAddOption() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyDefaultAddOption);
    return NewsSetAddOption.values.firstWhere(
      (option) => option.name == value,
      orElse: () => NewsSetAddOption.googleNews,
    );
  }

  Future<void> setDefaultAddOption(NewsSetAddOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultAddOption, option.name);
  }

  Future<PreferredNewsSource> getPreferredNewsSource() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyPreferredNewsSource);
    return PreferredNewsSource.values.firstWhere(
      (source) => source.name == value,
      orElse: () => PreferredNewsSource.googleNews,
    );
  }

  Future<void> setPreferredNewsSource(PreferredNewsSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreferredNewsSource, source.name);
  }

  Future<bool> getReadPreviewBeforeArticle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReadPreviewBeforeArticle) ?? true;
  }

  Future<void> setReadPreviewBeforeArticle(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReadPreviewBeforeArticle, enabled);
  }

  Future<double> getPlaybackSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyPlaybackSpeed) ?? 1.0;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyPlaybackSpeed, speed);
  }
}
