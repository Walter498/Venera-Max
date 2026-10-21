import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/chapter_metadata.dart';
import 'package:venera/foundation/comic_details_cache.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

ComicDetails _details({
  required String id,
  Map<String, dynamic>? chapters,
  String title = 'Title',
  Map<String, ChapterMetadata> metadata = const {},
}) {
  return ComicDetails.fromJson({
    'title': title,
    'subtitle': null,
    'cover': 'cover.jpg',
    'description': 'desc',
    'tags': {
      'Author': ['Someone'],
    },
    'chapters': chapters,
    'chapterMetadata': {
      for (final entry in metadata.entries) entry.key: entry.value.toJson(),
    },
    'sourceKey': 'test_source',
    'comicId': id,
    'thumbnails': null,
    'recommend': null,
    'isFavorite': false,
    'subId': null,
    'likesCount': null,
    'isLiked': null,
    'commentCount': null,
    'uploader': null,
    'uploadTime': null,
    'updateTime': null,
    'url': null,
    'stars': null,
    'maxPage': null,
    'comments': null,
  });
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  });

  late Directory tempDir;
  late ComicDetailsCache cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('venera_details_cache_');
    cache = ComicDetailsCache.openForTesting('${tempDir.path}/details_cache.db');
  });

  tearDown(() {
    cache.close();
    ComicDetailsCache.maxEntries = 2000;
    tempDir.deleteSync(recursive: true);
  });

  test('returns null before anything is cached', () {
    expect(cache.readStoredForTesting('test_source', 'a'), isNull);
  });

  test('round-trips flat chapters through cache', () {
    final details = _details(
      id: 'a',
      chapters: {'c1': 'Chapter 1', 'c2': 'Chapter 2'},
    );
    cache.update('test_source', 'a', details);

    final restored = cache.readStoredForTesting('test_source', 'a');
    expect(restored, isNotNull);
    expect(restored!.chapters!.isGrouped, isFalse);
    expect(restored.chapters!.length, 2);
    expect(restored.chapters!.titles.toList(), ['Chapter 1', 'Chapter 2']);
    expect(restored.title, 'Title');
    expect(restored.tags['Author'], contains('Someone'));
  });

  test('round-trips grouped chapters and tabs', () {
    final details = _details(
      id: 'g',
      chapters: {
        'Main': {'m1': 'M1', 'm2': 'M2'},
        'Extra': {'e1': 'E1'},
      },
    );
    cache.update('test_source', 'g', details);

    final restored = cache.readStoredForTesting('test_source', 'g')!;
    expect(restored.chapters!.isGrouped, isTrue);
    expect(restored.chapters!.groups.toList(), ['Main', 'Extra']);
    expect(restored.chapters!.length, 3);
  });

  test('overwrites an existing entry with new chapters', () {
    cache.update(
      'test_source',
      'a',
      _details(id: 'a', chapters: {'c1': 'Chapter 1'}),
    );
    cache.update(
      'test_source',
      'a',
      _details(id: 'a', chapters: {'c1': 'Chapter 1', 'c2': 'Chapter 2'}),
    );
    expect(cache.readStoredForTesting('test_source', 'a')!.chapters!.length, 2);
  });

  test('does not cache local comics', () {
    cache.update('local', 'x', _details(id: 'x', chapters: {'c1': 'C1'}));
    expect(cache.readStoredForTesting('local', 'x'), isNull);
  });

  test('does not cache collection sources', () {
    const key = 'comic_collection_1';
    cache.update(key, 'x', _details(id: 'x', chapters: {'c1': 'C1'}));
    expect(cache.readStoredForTesting(key, 'x'), isNull);
  });

  test('prunes oldest entries beyond the cap', () {
    ComicDetailsCache.maxEntries = 3;
    // Re-open so the cap takes effect from a clean table.
    cache.close();
    cache = ComicDetailsCache.openForTesting('${tempDir.path}/details_cache.db');

    for (var i = 0; i < 5; i++) {
      cache.update(
        'test_source',
        'id$i',
        _details(id: 'id$i', chapters: {'c': 'C'}),
      );
    }
    // Pruning runs on open; force it by re-opening after the writes.
    cache.close();
    cache = ComicDetailsCache.openForTesting('${tempDir.path}/details_cache.db');

    var remaining = 0;
    for (var i = 0; i < 5; i++) {
      if (cache.readStoredForTesting('test_source', 'id$i') != null) remaining++;
    }
    expect(remaining, 3);
  });

  Map<String, dynamic> storedJson(String comicId) {
    final db = sqlite3.open('${tempDir.path}/details_cache.db');
    try {
      final rows = db.select(
        'SELECT data FROM details_cache WHERE source_key = ? AND comic_id = ?;',
        ['test_source', comicId],
      );
      expect(rows, hasLength(1));
      return jsonDecode(rows.single['data'] as String) as Map<String, dynamic>;
    } finally {
      db.dispose();
    }
  }

  void expectNoLikes(Map<String, ChapterMetadata> metadata) {
    for (final value in metadata.values) {
      expect(value.likesCount, isNull);
      expect(value.likesSource, isNull);
    }
  }

  test('date-only read returns empty for a miss and does not create a row', () {
    expect(cache.readChapterMetadata('test_source', 'missing'), isEmpty);
    cache.mergeChapterMetadata('test_source', 'missing', {
      'a': const ChapterMetadata(tencentUpdateTime: '2022-04-23'),
    });
    expect(cache.readStoredForTesting('test_source', 'missing'), isNull);
    expect(cache.readChapterMetadata('local', 'missing'), isEmpty);
    expect(cache.readChapterMetadata('comic_collection_1', 'missing'), isEmpty);
  });

  test('date merges preserve both providers and earlier chapter batches', () {
    cache.update('test_source', 'dates', _details(id: 'dates', metadata: {
      'a': const ChapterMetadata(updateTime: '2026-01-17'),
      'b': const ChapterMetadata(tencentUpdateTime: '2022-04-24'),
    }));
    cache.mergeChapterMetadata('test_source', 'dates', {
      'a': const ChapterMetadata(tencentUpdateTime: '2022-04-23', likesCount: 0),
      'b': const ChapterMetadata(updateTime: '2026-01-18', likesCount: 8),
    });
    cache.mergeChapterMetadata('test_source', 'dates', {
      'c': const ChapterMetadata(tencentUpdateTime: '2022-04-25'),
    });
    // A later incomplete response cannot erase either independent date.
    cache.mergeChapterMetadata('test_source', 'dates', {
      'a': const ChapterMetadata(likesCount: 42, likesSource: 'tencent'),
      'b': const ChapterMetadata(),
    });
    cache.close();
    cache = ComicDetailsCache.openForTesting('${tempDir.path}/details_cache.db');

    final dates = cache.readChapterMetadata('test_source', 'dates');
    expect(dates.keys, unorderedEquals(['a', 'b', 'c']));
    expect(dates['a']!.updateTime, '2026-01-17');
    expect(dates['a']!.tencentUpdateTime, '2022-04-23');
    expect(dates['b']!.updateTime, '2026-01-18');
    expect(dates['b']!.tencentUpdateTime, '2022-04-24');
    expect(dates['c']!.updateTime, isNull);
    expect(dates['c']!.tencentUpdateTime, '2022-04-25');
    expectNoLikes(dates);
    expectNoLikes(cache.readStoredForTesting('test_source', 'dates')!.chapterMetadata);
  });

  test('details refresh keeps Tencent dates while updating Lizi and catalog', () {
    cache.update('test_source', 'refresh', _details(
      id: 'refresh', chapters: {'a': 'A', 'b': 'B'}, metadata: {
        'a': const ChapterMetadata(
          updateTime: '2026-01-17', tencentUpdateTime: '2022-04-23'),
        'b': const ChapterMetadata(tencentUpdateTime: '2022-04-24'),
      },
    ));
    cache.update('test_source', 'refresh', _details(
      id: 'refresh', title: 'Refreshed',
      chapters: {'a': 'A revised', 'b': 'B', 'c': 'C'}, metadata: {
        'a': const ChapterMetadata(updateTime: '2026-02-01', likesCount: 0),
        'c': const ChapterMetadata(updateTime: '2026-02-02'),
      },
    ));
    // A further refresh without any metadata must preserve the enrichment.
    cache.update('test_source', 'refresh', _details(
      id: 'refresh', title: 'Latest',
      chapters: {'a': 'A revised', 'b': 'B', 'c': 'C'},
    ));

    final stored = cache.readStoredForTesting('test_source', 'refresh')!;
    expect(stored.title, 'Latest');
    expect(stored.chapters!.length, 3);
    final dates = cache.readChapterMetadata('test_source', 'refresh');
    expect(dates['a']!.updateTime, '2026-02-01');
    expect(dates['a']!.tencentUpdateTime, '2022-04-23');
    expect(dates['b']!.updateTime, isNull);
    expect(dates['b']!.tencentUpdateTime, '2022-04-24');
    expect(dates['c']!.updateTime, '2026-02-02');
    expect(dates['c']!.tencentUpdateTime, isNull);
    expectNoLikes(stored.chapterMetadata);
    expectNoLikes(dates);
    expect(cache.find('test_source', 'refresh'), isNull);
  });

  test('missing date fields remain unknown and can be filled by later data', () {
    cache.update('test_source', 'partial', _details(id: 'partial', metadata: {
      'a': const ChapterMetadata(updateTime: '2026-01-17'),
      'b': const ChapterMetadata(likesCount: 0, likesSource: 'tencent'),
    }));
    cache.mergeChapterMetadata('test_source', 'partial', {
      'a': const ChapterMetadata(),
      'b': const ChapterMetadata(likesCount: 2),
    });
    final missing = cache.readChapterMetadata('test_source', 'partial');
    expect(missing['a']!.tencentUpdateTime, isNull);
    expect(missing['b']!.updateTime, isNull);
    expect(missing['b']!.tencentUpdateTime, isNull);
    expectNoLikes(missing);
    final raw = storedJson('partial')['chapterMetadata'] as Map;
    expect((raw['a'] as Map).containsKey('tencentUpdateTime'), isFalse);
    expect((raw['b'] as Map).containsKey('updateTime'), isFalse);
    expect((raw['b'] as Map).containsKey('tencentUpdateTime'), isFalse);

    cache.mergeChapterMetadata('test_source', 'partial', {
      'a': const ChapterMetadata(tencentUpdateTime: '2022-04-23'),
      'b': const ChapterMetadata(updateTime: '2026-01-18'),
    });
    final filled = cache.readChapterMetadata('test_source', 'partial');
    expect(filled['a']!.updateTime, '2026-01-17');
    expect(filled['a']!.tencentUpdateTime, '2022-04-23');
    expect(filled['b']!.updateTime, '2026-01-18');
    expect(filled['b']!.tencentUpdateTime, isNull);
  });

  test('real zero and positive chapter likes never reach the disk JSON', () {
    final details = _details(id: 'likes', metadata: {
      'zero': const ChapterMetadata(updateTime: '2026-01-17',
        likesCount: 0, likesSource: 'tencent'),
      'positive': const ChapterMetadata(tencentUpdateTime: '2022-04-23',
        likesCount: 123, likesSource: 'tencent'),
    });
    expect(details.chapterMetadata['zero']!.displayLikes, '0');
    cache.update('test_source', 'likes', details);
    void checkDisk() {
      final raw = storedJson('likes')['chapterMetadata'] as Map;
      for (final entry in raw.values) {
        expect((entry as Map).containsKey('likesCount'), isFalse);
        expect(entry.containsKey('likesSource'), isFalse);
      }
      expectNoLikes(cache.readChapterMetadata('test_source', 'likes'));
      expectNoLikes(cache.readStoredForTesting('test_source', 'likes')!.chapterMetadata);
    }
    checkDisk();
    cache.mergeChapterMetadata('test_source', 'likes', {
      'zero': const ChapterMetadata(tencentUpdateTime: '2022-04-24',
        likesCount: 0, likesSource: 'tencent'),
      'positive': const ChapterMetadata(likesCount: 456, likesSource: 'tencent'),
    });
    checkDisk();
    cache.update('test_source', 'likes', details);
    checkDisk();
  });

  test('date-only reader strips likes even from a legacy disk record', () {
    final json = ComicDetailsCache.encode(_details(id: 'legacy'));
    json['chapterMetadata'] = {
      'zero': {'updateTime': '2026-01-17', 'likesCount': 0,
        'likesSource': 'tencent'},
      'positive': {'tencentUpdateTime': '2022-04-23', 'likesCount': 200,
        'likesSource': 'tencent'},
    };
    final db = sqlite3.open('${tempDir.path}/details_cache.db');
    try {
      db.execute('INSERT INTO details_cache '
        '(source_key, comic_id, data, time) VALUES (?, ?, ?, ?);',
        ['test_source', 'legacy', jsonEncode(json), 1]);
    } finally {
      db.dispose();
    }
    // Prove the reader itself strips historical likes, not just the writer.
    expect(cache.readStoredForTesting('test_source', 'legacy')!
        .chapterMetadata['zero']!.likesCount, 0);
    final dates = cache.readChapterMetadata('test_source', 'legacy');
    expect(dates.keys, unorderedEquals(['zero', 'positive']));
    expect(dates['zero']!.updateTime, '2026-01-17');
    expect(dates['positive']!.tencentUpdateTime, '2022-04-23');
    expectNoLikes(dates);
  });

  test('chapter metadata stays isolated by comic and source key', () {
    cache.update('test_source', 'a', _details(id: 'a', metadata: {
      'chapter': const ChapterMetadata(updateTime: '2026-01-17'),
    }));
    cache.update('other_source', 'a', _details(id: 'a', metadata: {
      'chapter': const ChapterMetadata(tencentUpdateTime: '2022-04-23'),
    }));
    cache.update('test_source', 'b', _details(id: 'b'));
    cache.mergeChapterMetadata('test_source', 'b', {
      'chapter': const ChapterMetadata(updateTime: '2026-02-01'),
    });
    expect(cache.readChapterMetadata('test_source', 'a')['chapter']!.updateTime,
      '2026-01-17');
    expect(cache.readChapterMetadata('test_source', 'a')['chapter']!.tencentUpdateTime,
      isNull);
    expect(cache.readChapterMetadata('other_source', 'a')['chapter']!.tencentUpdateTime,
      '2022-04-23');
    expect(cache.readChapterMetadata('test_source', 'b')['chapter']!.updateTime,
      '2026-02-01');
  });

  test('drops a malformed row instead of throwing', () {
    final db = sqlite3.open('${tempDir.path}/details_cache.db');
    db.execute(
      "INSERT OR REPLACE INTO details_cache "
      "(source_key, comic_id, data, time) VALUES (?, ?, ?, ?);",
      ['test_source', 'bad', 'not json', 1],
    );
    db.dispose();

    expect(cache.readStoredForTesting('test_source', 'bad'), isNull);
    // The bad row is gone, so a later good write is retrievable.
    cache.update(
      'test_source',
      'bad',
      _details(id: 'bad', chapters: {'c1': 'C1'}),
    );
    expect(cache.readStoredForTesting('test_source', 'bad'), isNotNull);
  });
}
