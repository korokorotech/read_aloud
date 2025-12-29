import 'package:read_aloud/database/app_database.dart';
import 'package:read_aloud/entities/news_item_record.dart';
import 'package:read_aloud/entities/news_set_detail.dart';
import 'package:read_aloud/entities/news_set_summary.dart';

class NewsSetRepository {
  NewsSetRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<NewsSetSummary>> fetchSummaries() async {
    final db = await _database.database;
    final result = await db.rawQuery('''
      SELECT
        ns.id,
        ns.name,
        ns.updated_at,
        (
          SELECT COUNT(*) FROM news_items AS ni
          WHERE ni.set_id = ns.id AND ni.deleted_at IS NULL
        ) AS article_count,
        (
          SELECT preview_text FROM news_items AS ni
          WHERE ni.set_id = ns.id AND ni.deleted_at IS NULL
          ORDER BY ni.order_index ASC
          LIMIT 1
        ) AS first_item_title
      FROM news_sets AS ns
      ORDER BY ns.updated_at DESC
    ''');

    return result
        .map(
          (row) => NewsSetSummary(
            id: row['id'] as String,
            name: row['name'] as String,
            articleCount: _asInt(row['article_count']),
            updatedAt: _toDateTime(row['updated_at']),
            firstItemTitle: row['first_item_title'] as String?,
          ),
        )
        .toList();
  }

  Future<NewsSetDetail?> fetchDetail(String setId) async {
    final db = await _database.database;
    final setRows = await db.query(
      'news_sets',
      where: 'id = ?',
      whereArgs: [setId],
      limit: 1,
    );

    if (setRows.isEmpty) {
      return null;
    }

    final itemsRaw = await db.query(
      'news_items',
      where: 'set_id = ? AND (deleted_at IS NULL)',
      whereArgs: [setId],
      orderBy: 'order_index ASC',
    );

    final items = itemsRaw
        .map(
          (row) => NewsItemRecord(
            id: row['id'] as String,
            setId: row['set_id'] as String,
            url: row['url'] as String,
            previewText: row['preview_text'] as String,
            articleText: row['article_text'] as String?,
            addedAt: _asInt(row['added_at']),
            orderIndex: _asInt(row['order_index']),
          ),
        )
        .toList();

    final setRow = setRows.first;
    return NewsSetDetail(
      id: setRow['id'] as String,
      name: setRow['name'] as String,
      createdAt: _toDateTime(setRow['created_at']),
      updatedAt: _toDateTime(setRow['updated_at']),
      items: items,
    );
  }

  Future<bool> exists(String setId) async {
    final db = await _database.database;
    final result = await db.query(
      'news_sets',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [setId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> deleteSet(String setId) async {
    final db = await _database.database;
    await db.delete('news_sets', where: 'id = ?', whereArgs: [setId]);
  }

  static DateTime _toDateTime(Object? value) {
    final millis = _asInt(value);
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
