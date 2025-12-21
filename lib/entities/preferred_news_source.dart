enum PreferredNewsSource {
  googleNews,
  yahooNews,
}

extension PreferredNewsSourceLabel on PreferredNewsSource {
  String get label {
    switch (this) {
      case PreferredNewsSource.googleNews:
        return 'Google News';
      case PreferredNewsSource.yahooNews:
        return 'Yahoo!ニュース';
    }
  }
}
