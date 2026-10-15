import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/sqlite_connection.dart';

class _CacheFixture {
  final root = Directory.systemTemp.createTempSync('reader-cache-cleanup-');
  late final String dbPath = '${root.path}/cache.db';
  late final Database db;

  _CacheFixture() {
    App.dataPath = root.path;
    App.cachePath = root.path;
    appdata.settings[CacheManager.directorySetting] = '';
    CacheManager.instance = null;
    db = sqlite3.open(dbPath);
    // Deliberately use the old schema without either secondary index.
    db.execute('CREATE TABLE cache (key TEXT PRIMARY KEY NOT NULL, '
        'dir TEXT NOT NULL, name TEXT NOT NULL, expires INTEGER NOT NULL, type TEXT)');
  }

  File add(String key, int expires, [int size = 3]) {
    final file = File('${root.path}/cache/1/$key')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(size, 7));
    db.execute('INSERT INTO cache VALUES (?, ?, ?, ?, ?)',
        [key, '1', key, expires, 'image']);
    return file;
  }

  List<String> get keys => db.select('SELECT key FROM cache ORDER BY key')
      .map((row) => row['key'] as String).toList();

  Future<void> dispose() async {
    await CacheManager.instance?.ready;
    DatabaseGateway.instance.closeManaged(dbPath);
    db.dispose();
    CacheManager.instance = null;
    root.deleteSync(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old database gains expiry index for both real cleanup queries', () async {
    final f = _CacheFixture();
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    final live = f.add('live', expires);
    try {
      final manager = CacheManager();
      await manager.ready;
      for (final query in [
        'SELECT * FROM cache WHERE expires < ?',
        'SELECT * FROM cache ORDER BY expires ASC LIMIT 10',
      ]) {
        final plan = f.db.select('EXPLAIN QUERY PLAN $query',
            query.contains('?') ? [expires - 1] : []);
        final details = plan.map((row) => row['detail']).join(' ');
        expect(details, contains('USING INDEX cache_expires'));
        expect(details, isNot(contains('USE TEMP B-TREE')));
      }
      expect(f.keys, ['live']);
      expect(live.readAsBytesSync(), [7, 7, 7]);
      expect(f.db.select('SELECT expires, type FROM cache').single['expires'], expires);
      expect(f.db.select('SELECT type FROM cache').single['type'], 'image');
      expect(manager.currentSize, 3);
    } finally {
      await f.dispose();
    }
  });

  test('cleanup SQL failure releases lock and preserves live TTL', () async {
    final f = _CacheFixture();
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    final stale = f.add('stale', expires);
    final live = f.add('live', expires);
    try {
      final manager = CacheManager();
      await manager.ready;
      f.db.execute('UPDATE cache SET expires = 0 WHERE key = ?', ['stale']);
      // A real SQLite failure, without exposing a production fault-injection API.
      f.db.execute("CREATE TRIGGER fail_cleanup BEFORE DELETE ON cache "
          "BEGIN SELECT RAISE(FAIL, 'cleanup fault'); END");
      await expectLater(manager.checkCache(), throwsA(isA<SqliteException>()));
      expect(stale.existsSync(), isFalse);
      expect(manager.currentSize, 3);
      f.db.execute('DROP TRIGGER fail_cleanup');
      await manager.checkCache();
      expect(f.keys, ['live']);
      expect(live.existsSync(), isTrue);
      expect(manager.currentSize, 3);
      expect(f.db.select('SELECT expires FROM cache').single['expires'], expires);
      // A subsequent check must also be harmless (no duplicate size decrement).
      await manager.checkCache();
      expect(manager.currentSize, 3);
    } finally {
      await f.dispose();
    }
  });

  test('size eviction keeps earliest expiry order and stops at existing limit', () async {
    final f = _CacheFixture();
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    final oldest = f.add('oldest', expires, 600000);
    final middle = f.add('middle', expires + 1000, 600000);
    final newest = f.add('newest', expires + 2000, 600000);
    try {
      final manager = CacheManager();
      await manager.ready;
      manager.setLimitSize(1);
      await manager.checkCache();
      expect(oldest.existsSync(), isFalse);
      expect(middle.existsSync(), isFalse);
      expect(newest.existsSync(), isTrue);
      expect(f.keys, ['newest']);
      expect(manager.currentSize, 600000);
      expect(f.db.select('SELECT expires FROM cache').single['expires'], expires + 2000);
    } finally {
      await f.dispose();
    }
  });

  test('size eviction continues across ten-row batches without over-deleting', () async {
    final f = _CacheFixture();
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    for (var i = 0; i < 25; i++) {
      f.add('entry-${i.toString().padLeft(2, '0')}', expires + i * 1000, 100000);
    }
    try {
      final manager = CacheManager();
      await manager.ready;
      manager.setLimitSize(1);
      await manager.checkCache();
      expect(manager.currentSize, 1000000);
      expect(f.keys, List.generate(10, (i) => 'entry-${i + 15}'));
      expect(f.db.select('SELECT MIN(expires) AS oldest FROM cache')
          .single['oldest'], expires + 15000);
    } finally {
      await f.dispose();
    }
  });

  test('size eviction can retry after SQL failure without double accounting', () async {
    final f = _CacheFixture();
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    final oldest = f.add('oldest', expires, 600000);
    final newest = f.add('newest', expires + 1000, 600000);
    try {
      final manager = CacheManager();
      await manager.ready;
      manager.setLimitSize(1);
      f.db.execute("CREATE TRIGGER fail_cleanup BEFORE DELETE ON cache "
          "BEGIN SELECT RAISE(FAIL, 'cleanup fault'); END");
      await expectLater(manager.checkCache(), throwsA(isA<SqliteException>()));
      expect(oldest.existsSync(), isFalse);
      expect(manager.currentSize, 600000);
      f.db.execute('DROP TRIGGER fail_cleanup');
      manager.setLimitSize(0);
      await manager.checkCache();
      expect(newest.existsSync(), isFalse);
      expect(f.keys, isEmpty);
      expect(manager.currentSize, 0);
    } finally {
      await f.dispose();
    }
  });

  test('explicit cleanup before startup size is known does not break ready', () async {
    final f = _CacheFixture();
    final stale = f.add('stale', 0);
    final release = Completer<void>();
    final gate = DatabaseGateway.instance.runExclusive(() => release.future);
    try {
      final manager = CacheManager();
      await manager.checkCache();
      expect(stale.existsSync(), isFalse);
      expect(f.keys, isEmpty);
      release.complete();
      await manager.ready;
      expect(manager.currentSize, 0);
    } finally {
      if (!release.isCompleted) release.complete();
      await gate;
      await f.dispose();
    }
  });
}
