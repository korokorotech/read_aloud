import 'package:read_aloud/entities/news_item_record.dart';

class NewsSetDetail {
  const NewsSetDetail({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<NewsItemRecord> items;

  NewsSetDetail copyWith({
    String? name,
    DateTime? updatedAt,
    List<NewsItemRecord>? items,
  }) {
    return NewsSetDetail(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }
}
