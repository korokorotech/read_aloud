import 'dart:async';

import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_set_add_option.dart';
import 'package:read_aloud/entities/news_set_retention_option.dart';
import 'package:read_aloud/entities/preferred_news_source.dart';
import 'package:read_aloud/services/app_settings.dart';
import 'package:read_aloud/services/player_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppSettings _settings = AppSettings.instance;

  bool _isLoading = true;
  NewsSetAddOption _defaultAddOption = NewsSetAddOption.googleNews;
  PreferredNewsSource _preferredNewsSource = PreferredNewsSource.googleNews;
  bool _readPreviewBeforeArticle = true;
  double _playbackSpeed = 1.0;
  NewsSetRetentionOption _newsSetRetentionOption = NewsSetRetentionOption.keep;
  int _minArticleLength = 200;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final addOption = await _settings.getDefaultAddOption();
    final newsSource = await _settings.getPreferredNewsSource();
    final readPreviewBeforeArticle =
        await _settings.getReadPreviewBeforeArticle();
    final playbackSpeed = await _settings.getPlaybackSpeed();
    final newsSetRetention = await _settings.getNewsSetRetentionOption();
    final minArticleLength = await _settings.getMinArticleLength();
    if (!mounted) return;
    setState(() {
      _defaultAddOption = addOption;
      _preferredNewsSource = newsSource;
      _readPreviewBeforeArticle = readPreviewBeforeArticle;
      _playbackSpeed = playbackSpeed;
      _newsSetRetentionOption = newsSetRetention;
      _minArticleLength = minArticleLength;
      _isLoading = false;
    });
  }

  Future<void> _updateDefaultOption(NewsSetAddOption option) async {
    setState(() {
      _defaultAddOption = option;
    });
    await _settings.setDefaultAddOption(option);
  }

  Future<void> _updateNewsSource(PreferredNewsSource source) async {
    setState(() {
      _preferredNewsSource = source;
    });
    await _settings.setPreferredNewsSource(source);
  }

  Future<void> _updateReadPreviewBeforeArticle(bool value) async {
    setState(() {
      _readPreviewBeforeArticle = value;
    });
    await _settings.setReadPreviewBeforeArticle(value);
  }

  Future<void> _updatePlaybackSpeed(double speed) async {
    setState(() {
      _playbackSpeed = speed;
    });
    await PlayerService.instance.setPlaybackSpeed(speed);
  }

  Future<void> _updateNewsSetRetentionOption(
    NewsSetRetentionOption option,
  ) async {
    setState(() {
      _newsSetRetentionOption = option;
    });
    await _settings.setNewsSetRetentionOption(option);
  }

  Future<void> _updateMinArticleLength(double value) async {
    final length = value.round();
    setState(() {
      _minArticleLength = length;
    });
    await _settings.setMinArticleLength(length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '記事追加の既定値',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PreferredNewsSource>(
                    initialValue: _preferredNewsSource,
                    decoration: const InputDecoration(
                      labelText: 'ニュースから追加のサイト',
                      border: OutlineInputBorder(),
                    ),
                    items: PreferredNewsSource.values
                        .map(
                          (source) => DropdownMenuItem(
                            value: source,
                            child: Text(source.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _updateNewsSource(value);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonHideUnderline(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '新規作成時のデフォルト追加方法',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButton<NewsSetAddOption>(
                        isExpanded: true,
                        value: _defaultAddOption,
                        items: NewsSetAddOption.values
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(option.label),
                                    const SizedBox(height: 4),
                                    Text(
                                      option.description,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            _updateDefaultOption(value);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('本文の前にタイトルを読み上げ'),
                    value: _readPreviewBeforeArticle,
                    onChanged: _updateReadPreviewBeforeArticle,
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<double>(
                    initialValue: _playbackSpeed,
                    decoration: const InputDecoration(
                      labelText: '再生速度',
                      border: OutlineInputBorder(),
                    ),
                    items: PlayerService.playbackSpeedOptions
                        .map(
                          (speed) => DropdownMenuItem(
                            value: speed,
                            child: Text(_formatSpeed(speed)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _updatePlaybackSpeed(value);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<NewsSetRetentionOption>(
                    initialValue: _newsSetRetentionOption,
                    decoration: const InputDecoration(
                      labelText: '起動時に古いニュースセットを削除',
                      helperText: '指定した日より古いニュースセットを削除します',
                      border: OutlineInputBorder(),
                    ),
                    items: NewsSetRetentionOption.values
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _updateNewsSetRetentionOption(value);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '記事の最小文字数 (キュー追加時)',
                      helperText: '0で制限なし、最大1000文字',
                      border: OutlineInputBorder(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Slider(
                          value: _minArticleLength.toDouble(),
                          min: 0,
                          max: 1000,
                          divisions: 100,
                          label: _minArticleLength == 0
                              ? '制限なし'
                              : '$_minArticleLength 文字以上',
                          onChanged: (value) {
                            setState(() {
                              _minArticleLength = value.round();
                            });
                          },
                          onChangeEnd: _updateMinArticleLength,
                        ),
                        Text(
                          _minArticleLength == 0
                              ? '制限なし'
                              : '${_minArticleLength}文字以上で追加',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  String _formatSpeed(double speed) {
    if (speed % 1 == 0) {
      return '${speed.toStringAsFixed(0)}x';
    }
    final trimmed = speed
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return '${trimmed}x';
  }
}
