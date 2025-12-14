PRAGMA foreign_keys = ON;

CREATE TABLE news_sets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  playhead_item_id TEXT,
  playhead_pos_ms INTEGER
);

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
);

CREATE INDEX idx_items_set_order ON news_items(set_id, order_index);
CREATE INDEX idx_items_deleted ON news_items(deleted_at);
