import 'dart:async';

import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_set_add_option.dart';
import 'package:read_aloud/entities/preferred_news_source.dart';
import 'package:read_aloud/services/app_settings.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final addOption = await _settings.getDefaultAddOption();
    final newsSource = await _settings.getPreferredNewsSource();
    if (!mounted) return;
    setState(() {
      _defaultAddOption = addOption;
      _preferredNewsSource = newsSource;
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
                    value: _preferredNewsSource,
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
                ],
              ),
      ),
    );
  }
}
