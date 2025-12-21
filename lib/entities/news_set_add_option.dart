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
        return '指定のURLから追加';
    }
  }

  String get description {
    switch (this) {
      case NewsSetAddOption.searchGoogle:
        return 'キーワード検索します';
      case NewsSetAddOption.googleNews:
        return 'ニュースサイトへ遷移します';
      case NewsSetAddOption.customUrl:
        return 'URLを入力して任意のサイトへ遷移します';
    }
  }
}
