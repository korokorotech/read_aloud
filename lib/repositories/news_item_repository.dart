import 'dart:math';

import 'package:read_aloud/entities/news_item_record.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

class DuplicateArticleException implements Exception {
  const DuplicateArticleException();
}

class NewsItemRepository {
  NewsItemRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  final Random _random = Random();

  Future<NewsItemRecord> insertArticle({
    required String setId,
    required String setName,
    required String url,
    required String previewText,
    required String? articleText,
  }) async {
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final addedAt = DateTime.now().millisecondsSinceEpoch;
        final orderIndex = await _nextOrderIndex(txn, setId);
        await _ensureSetExists(txn, setId, setName, addedAt);

        final id = _generateId();
        final values = <String, Object?>{
          'id': id,
          'set_id': setId,
          'url': url,
          'preview_text': previewText,
          'article_text': articleText,
          'added_at': addedAt,
          'order_index': orderIndex,
          'deleted_at': null,
        };

        await txn.insert('news_items', values);
        await txn.update(
          'news_sets',
          {'updated_at': addedAt},
          where: 'id = ?',
          whereArgs: [setId],
        );

        return NewsItemRecord(
          id: id,
          setId: setId,
          url: url,
          previewText: previewText,
          articleText: articleText,
          addedAt: addedAt,
          orderIndex: orderIndex,
        );
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const DuplicateArticleException();
      }
      rethrow;
    }
  }

  Future<void> deleteArticle(String id) async {
    final db = await _database.database;
    await db.delete('news_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> _nextOrderIndex(Transaction txn, String setId) async {
    final result = await txn.rawQuery(
      'SELECT MAX(order_index) as max_order FROM news_items WHERE set_id = ?',
      [setId],
    );
    final value = (result.first['max_order'] as int?) ?? 0;
    return value + 1;
  }

  Future<void> _ensureSetExists(
    Transaction txn,
    String setId,
    String setName,
    int timestamp,
  ) async {
    final inserted = await txn.insert(
      'news_sets',
      {
        'id': setId,
        'name': setName,
        'created_at': timestamp,
        'updated_at': timestamp,
        'playhead_item_id': null,
        'playhead_pos_ms': null,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (inserted == 0) {
      await txn.update(
        'news_sets',
        {'name': setName},
        where: 'id = ?',
        whereArgs: [setId],
      );
    }
  }

  String _generateId() {
    final randomPart = _random.nextInt(0x7fffffff);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'item-$timestamp-$randomPart';
  }
}
