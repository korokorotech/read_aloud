import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  Database? _cachedDb;

  Future<Database> get database async {
    final existing = _cachedDb;
    if (existing != null) return existing;

    final db = await _open();
    _cachedDb = db;
    return db;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'read_aloud.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE news_sets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        playhead_item_id TEXT,
        playhead_pos_ms INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE news_items (
        id TEXT PRIMARY KEY,
        set_id TEXT NOT NULL,
        url TEXT NOT NULL,
        preview_text TEXT NOT NULL,
        article_text TEXT,
        added_at INTEGER NOT NULL,
        order_index INTEGER NOT NULL,
        deleted_at INTEGER,
        FOREIGN KEY (set_id) REFERENCES news_sets(id) ON DELETE CASCADE,
        UNIQUE (set_id, url)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_items_set_order ON news_items(set_id, order_index)',
    );
    await db.execute(
      'CREATE INDEX idx_items_deleted ON news_items(deleted_at)',
    );
  }

  Future<void> close() async {
    final db = _cachedDb;
    if (db == null) return;
    await db.close();
    _cachedDb = null;
  }
}
