class NewsItemRecord {
  NewsItemRecord({
    required this.id,
    required this.setId,
    required this.url,
    required this.previewText,
    required this.articleText,
    required this.addedAt,
    required this.orderIndex,
  });

  final String id;
  final String setId;
  final String url;
  final String previewText;
  final String? articleText;
  final int addedAt;
  final int orderIndex;
}
