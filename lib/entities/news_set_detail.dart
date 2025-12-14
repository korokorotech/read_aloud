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
}
