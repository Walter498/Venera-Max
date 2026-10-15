import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/sqlite_connection.dart';

History _item(int ep, int page, {int type = 0, int? group}) =>
    History.fromMap({
      'id': 'reader',
      'type': type,
      'title': 'chapter-$ep',
      'subtitle': 'subtitle',
      'cover': 'cover-$ep',
      'time': ep * 1000 + page,
      'ep': ep,
      'page': page,
      'chapter_group': group,
      'max_page': 100,
      'readEpisode': {'$ep'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryManager manager;
  late HistoryManager? originalManager;
  late String originalPath;
  late Map<String, dynamic> originalImplicitData;

  setUp(() async {
    // Exercise init/schema/write/cache/listeners, not a copy of their SQL.
    originalPath = App.dataPath;
    originalManager = HistoryManager.cache;
    originalImplicitData = appdata.implicitData;
    directory = await Directory.systemTemp.createTemp('history-reader-queue-');
    App.dataPath = directory.path;
    appdata.implicitData = {'image_favorites_cache_key_fix_v1': true};
    manager = HistoryManager.create();
    HistoryManager.cache = manager;
    await manager.init();
  });

  tearDown(() async {
    // writeImplicitData is async-void. Queue a final sentinel and wait for its
    // atomic rename before removing the temp directory or restoring App paths.
    appdata.implicitData['queueTestDrained'] = true;
    appdata.writeImplicitData();
    final file = File('${directory.path}/implicitData.json');
    await (() async {
      while (!await file.exists() ||
          (jsonDecode(await file.readAsString()) as Map)['queueTestDrained'] !=
              true) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    })().timeout(const Duration(seconds: 10));
    // A prior write can also include the sentinel: allow the finite batch of
    // async-void appdata writers (at most eight here, 20ms retry) to finish.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    manager.close();
    manager.dispose();
    HistoryManager.cache = originalManager;
    App.dataPath = originalPath;
    appdata.implicitData = originalImplicitData;
    await directory.delete(recursive: true);
  });

  test('an injected failure reaches its caller, then queued saves still run',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    manager.beforeAsyncHistoryWrite = () async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
        throw StateError('injected reader save failure');
      }
    };
    final failed = manager.addHistoryAsync(_item(1, 1));
    final failure = expectLater(failed, throwsA(isA<StateError>()));
    await entered.future;
    final next = manager.addHistoryAsync(_item(2, 42));
    release.complete();
    await failure;
    await next.timeout(const Duration(seconds: 10));
    expect(calls, 2);
    expect(manager.find('reader', ComicType.local)!.page, 42);
    // Also verify persisted state through an independent real DB connection.
    final db = openRawDatabase('${directory.path}/history.db');
    try {
      expect(db.select('select ep, page from history').single['ep'], 2);
      expect(db.select('select ep, page from history').single['page'], 42);
    } finally {
      db.dispose();
    }
  });

  test('concurrent saves snapshot reused History and preserve every transition',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    manager.beforeAsyncHistoryWrite = () async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
    };
    final item = _item(1, 11, group: 7);
    final saves = <Future<void>>[manager.addHistoryAsync(item)];
    await entered.future;
    final observed = <List<int>>[];
    manager.addListener(() {
      final stored = manager.find('reader', ComicType.local)!;
      observed.add([stored.ep, stored.page]);
    });
    for (var ep = 2; ep <= 6; ep++) {
      item.ep = ep;
      item.page = ep * 11;
      item.time = DateTime.fromMillisecondsSinceEpoch(ep * 1000);
      item.readEpisode.add('$ep');
      saves.add(manager.addHistoryAsync(item));
    }
    item.id = 'mutated-after-enqueue';
    item.ep = 999;
    item.page = 999;
    item.readEpisode.clear();
    release.complete();
    await Future.wait(saves).timeout(const Duration(seconds: 15));
    expect(observed, [for (var ep = 1; ep <= 6; ep++) [ep, ep * 11]]);
    final finalItem = manager.find('reader', ComicType.local)!;
    expect(finalItem.ep, 6);
    expect(finalItem.page, 66);
    expect(finalItem.group, 7);
    expect(finalItem.readEpisode, {'1', '2', '3', '4', '5', '6'});
    expect(manager.find('mutated-after-enqueue', ComicType.local), isNull);
    final previous = manager.previousPositions('reader', ComicType.local);
    expect(previous.map((e) => e['ep']).toList(), [5, 4, 3]);
    expect(previous.map((e) => e['page']).toList(), [55, 44, 33]);
    expect(previous.first['group'], 7);
    expect(previous.first['time'],
        DateTime.fromMillisecondsSinceEpoch(5000).toIso8601String());
    manager.close();
    await manager.init();
    expect(manager.find('reader', ComicType.local)!.page, 66);
  });

  test('old position is persisted row, not mutated cache; no unrelated rows read',
      () async {
    final original = _item(2, 19, group: 4);
    manager.addHistory(original);
    // The recent cache holds the caller's object for the synchronous API.
    original.ep = 8;
    original.page = 99;
    original.group = 9;
    final db = openRawDatabase('${directory.path}/history.db');
    try {
      // Materializing all History rows would fail on these invalid fields.
      // The indexed old-position query must not inspect another id or type.
      db.execute('''insert into history (id, type, time, readEpisode)
                    values ('unrelated', 0, 0, null), ('reader', 123, 0, null)''');
      await manager.addHistoryAsync(_item(3, 27, group: 5));
      expect(manager.previousPositions('reader', ComicType.local), [
        {
          'ep': 2,
          'page': 19,
          'group': 4,
          'time': DateTime.fromMillisecondsSinceEpoch(2019).toIso8601String(),
        },
      ]);
      expect(db.select('select page from history where id = ? and type = ?',
          ['reader', 0]).single['page'], 27);
    } finally {
      db.dispose();
    }
  });

  test('hidden row is excluded from previous positions but reading unhides it',
      () async {
    manager.addHistory(_item(1, 10));
    manager.clearHistory();
    await manager.addHistoryAsync(_item(2, 20));
    expect(manager.previousPositions('reader', ComicType.local), isEmpty);
    expect(manager.getAll().single.page, 20);
    await manager.addHistoryAsync(_item(3, 30));
    expect(manager.previousPositions('reader', ComicType.local).single['ep'], 2);
  });

  test('same episode and duplicate positions keep legacy three-entry semantics',
      () async {
    manager.addHistory(_item(1, 10, group: 1));
    appdata.implicitData['prevReadPos'] = {
      '0:reader': {'ep': 9, 'page': 90, 'group': null, 'time': 'legacy'},
    };
    await manager.addHistoryAsync(_item(1, 11, group: 2));
    // Group changes alone never created a previous-position entry.
    expect(manager.previousPositions('reader', ComicType.local).single['ep'], 9);
    await manager.addHistoryAsync(_item(2, 20));
    var previous = manager.previousPositions('reader', ComicType.local);
    expect(previous.map((e) => e['ep']).toList(), [1, 9]);
    expect(previous.first['page'], 11);
    expect(previous.first['group'], 2);
    await manager.addHistoryAsync(_item(1, 11, group: 8));
    await manager.addHistoryAsync(_item(3, 30));
    previous = manager.previousPositions('reader', ComicType.local);
    expect(previous.map((e) => e['ep']).toList(), [2, 1, 9]);
    // Dedup remains ep/page only: same position with another group is not new.
    expect(previous[1]['group'], 2);
    await manager.addHistoryAsync(_item(4, 40));
    expect(manager.previousPositions('reader', ComicType.local)
        .map((e) => e['ep']).toList(), [3, 2, 1]);
  });

  test('a real SQLite write failure also leaves the next save runnable',
      () async {
    final db = openRawDatabase('${directory.path}/history.db');
    try {
      db.execute('''create trigger reject_reader_write before insert on history
                    when new.ep = 1 begin
                    select raise(abort, 'injected SQL failure'); end;''');
      final failed = manager.addHistoryAsync(_item(1, 1));
      final failure = expectLater(failed, throwsA(isA<Exception>()));
      final next = manager.addHistoryAsync(_item(2, 22));
      await failure;
      await next.timeout(const Duration(seconds: 10));
      expect(db.select('select page from history').single['page'], 22);
      expect(manager.find('reader', ComicType.local)!.page, 22);
    } finally {
      db.dispose();
    }
  });
}
