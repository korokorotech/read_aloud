import 'package:flutter/material.dart';

enum NewsSetAddOption {
  searchGoogle,
  googleNews,
  customUrl,
}

extension NewsSetAddOptionLabel on NewsSetAddOption {
  String get label {
    switch (this) {
      case NewsSetAddOption.searchGoogle:
        return '検索して追加';
      case NewsSetAddOption.googleNews:
        return 'ニュースから追加';
      case NewsSetAddOption.customUrl:
        return 'その他のサイトから追加';
    }
  }

  String get description {
    switch (this) {
      case NewsSetAddOption.searchGoogle:
        return '検索へ遷移します';
      case NewsSetAddOption.googleNews:
        return 'ニュース検索へ遷移します';
      case NewsSetAddOption.customUrl:
        return 'URLを入力して任意のサイトへ遷移します';
    }
  }
}

Uri? resolveInitialUrlForNewsSet(NewsSetCreateResult result) {
  switch (result.option) {
    case NewsSetAddOption.searchGoogle:
      final query = Uri.encodeQueryComponent(result.setName);
      return Uri.parse('https://www.google.com');
    case NewsSetAddOption.googleNews:
      return Uri.parse('https://news.google.com');
    case NewsSetAddOption.customUrl:
      return result.customUrl;
  }
}

class NewsSetCreateResult {
  const NewsSetCreateResult({
    required this.setName,
    required this.option,
    this.customUrl,
  });

  final String setName;
  final NewsSetAddOption option;
  final Uri? customUrl;
}

class NewsSetCreateModal extends StatefulWidget {
  const NewsSetCreateModal({
    super.key,
    required this.initialName,
    this.isNameEditable = true,
    this.title,
  });

  final String initialName;
  final bool isNameEditable;
  final String? title;

  @override
  State<NewsSetCreateModal> createState() => _NewsSetCreateModalState();
}

class _NewsSetCreateModalState extends State<NewsSetCreateModal> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  NewsSetAddOption _selectedOption = NewsSetAddOption.searchGoogle;
  String? _urlErrorText;

  bool get _requiresUrl => _selectedOption == NewsSetAddOption.customUrl;

  bool get _isNextEnabled {
    final nameFilled = _nameController.text.trim().isNotEmpty;
    if (!nameFilled) return false;
    if (!_requiresUrl) return true;
    return Uri.tryParse(_urlController.text.trim()) != null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _handleNext() {
    final setName = _nameController.text.trim();
    if (setName.isEmpty) return;

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

    Navigator.of(context).pop(
      NewsSetCreateResult(
        setName: setName,
        option: _selectedOption,
        customUrl: customUrl,
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
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ニュースセット名',
                  border: OutlineInputBorder(),
                ),
                readOnly: !widget.isNameEditable,
                enabled: widget.isNameEditable,
                onChanged:
                    widget.isNameEditable ? (_) => setState(() {}) : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<NewsSetAddOption>(
                initialValue: _selectedOption,
                isExpanded: true,
                items: NewsSetAddOption.values
                    .map(
                      (option) => DropdownMenuItem(
                        value: option,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                decoration: const InputDecoration(
                  labelText: '追加方法',
                  border: OutlineInputBorder(),
                ),
                selectedItemBuilder: (context) => NewsSetAddOption.values
                    .map(
                      (option) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(option.label),
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
