import 'package:flutter/material.dart';
import 'package:read_aloud/entities/news_set_add_option.dart';
import 'package:read_aloud/entities/preferred_news_source.dart';

Uri? resolveInitialUrlForNewsSet(
  NewsSetCreateResult result, {
  required PreferredNewsSource newsSource,
}) {
  switch (result.option) {
    case NewsSetAddOption.searchGoogle:
      final keyword = result.searchKeyword;
      if (keyword != null && keyword.isNotEmpty) {
        final query = Uri.encodeQueryComponent(keyword);
        return Uri.parse('https://www.google.com/search?q=$query');
      }
      return Uri.parse('https://www.google.com');
    case NewsSetAddOption.googleNews:
      return _buildNewsSiteUrl(newsSource, result.searchKeyword);
    case NewsSetAddOption.customUrl:
      return result.customUrl;
  }
}

Uri _buildNewsSiteUrl(PreferredNewsSource source, String? keyword) {
  final hasKeyword = keyword != null && keyword.isNotEmpty;
  final query = hasKeyword ? Uri.encodeQueryComponent(keyword) : null;
  switch (source) {
    case PreferredNewsSource.googleNews:
      if (query != null) {
        return Uri.parse('https://news.google.com/search?q=$query');
      }
      return Uri.parse('https://news.google.com');
    case PreferredNewsSource.yahooNews:
      if (query != null) {
        return Uri.parse('https://news.yahoo.co.jp/search?p=$query');
      }
      return Uri.parse('https://news.yahoo.co.jp/');
  }
}

class NewsSetCreateResult {
  const NewsSetCreateResult({
    required this.setName,
    required this.option,
    this.customUrl,
    this.searchKeyword,
  });

  final String setName;
  final NewsSetAddOption option;
  final Uri? customUrl;
  final String? searchKeyword;
}

class NewsSetCreateModal extends StatefulWidget {
  const NewsSetCreateModal({
    super.key,
    required this.initialName,
    this.title,
    required this.initialOption,
    required this.preferredNewsSource,
  });

  final String initialName;
  final String? title;
  final NewsSetAddOption initialOption;
  final PreferredNewsSource preferredNewsSource;

  @override
  State<NewsSetCreateModal> createState() => _NewsSetCreateModalState();
}

class _NewsSetCreateModalState extends State<NewsSetCreateModal> {
  late final TextEditingController _urlController;
  late final TextEditingController _keywordController;
  late NewsSetAddOption _selectedOption;
  String? _urlErrorText;

  bool get _requiresUrl => _selectedOption == NewsSetAddOption.customUrl;
  bool get _showsKeywordField =>
      _selectedOption == NewsSetAddOption.googleNews ||
      _selectedOption == NewsSetAddOption.searchGoogle;

  bool get _isNextEnabled {
    if (_requiresUrl) {
      return Uri.tryParse(_urlController.text.trim()) != null;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _keywordController = TextEditingController();
    _selectedOption = widget.initialOption;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _handleNext() {
    Uri? customUrl;
    if (_requiresUrl) {
      customUrl = Uri.tryParse(_urlController.text.trim());
      if (customUrl == null) {
        setState(() {
          _urlErrorText = '有効なURLを入力してください';
        });
        return;
      }
    }

    String? searchKeyword;
    if (_showsKeywordField) {
      final keywordText = _keywordController.text.trim();
      if (keywordText.isNotEmpty) {
        searchKeyword = keywordText;
      }
    }
    final setName = searchKeyword ?? widget.initialName;

    Navigator.of(context).pop(
      NewsSetCreateResult(
        setName: setName,
        option: _selectedOption,
        customUrl: customUrl,
        searchKeyword: searchKeyword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets +
        const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
    final modalTitle = widget.title ?? 'ニュースセット新規作成';

    return SafeArea(
      child: Padding(
        padding: padding,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                modalTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              DropdownButtonHideUnderline(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '追加方法',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButton<NewsSetAddOption>(
                    value: _selectedOption,
                    isExpanded: true,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (option) {
                      if (option == null) return;
                      setState(() {
                        _selectedOption = option;
                        if (!_requiresUrl) {
                          _urlErrorText = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              if (_showsKeywordField) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _keywordController,
                  decoration: const InputDecoration(
                    labelText: '検索キーワード(任意)',
                    hintText: '検索キーワード(任意)',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (_isNextEnabled) {
                      _handleNext();
                    }
                  },
                ),
              ],
              if (_requiresUrl) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: '移動先URL',
                    border: const OutlineInputBorder(),
                    errorText: _urlErrorText,
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) {
                    setState(() {
                      _urlErrorText = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isNextEnabled ? _handleNext : null,
                  child: const Text('次へ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
