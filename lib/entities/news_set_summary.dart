class NewsSetSummary {
  const NewsSetSummary({
    required this.id,
    required this.name,
    required this.articleCount,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int articleCount;
  final DateTime updatedAt;
}
