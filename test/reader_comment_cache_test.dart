import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';

import 'comments_fixtures.dart';

// Real manager/controllers with mocked transport only. No UI, network, device,
// App.init, persisted source data, or font setup is needed for these tests.
Future<void> settleFeeds() => Future<void>.delayed(Duration.zero);

bool isAlive(CommentsController feed) {
  try {
    return ChangeNotifier.debugAssertNotDisposed(feed);
  } on FlutterError {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capacity = ReaderChapterCommentsFeeds.retainedIdleChapters;

  test('200 chapters retain only lookup LRU; owner is not a borrower', () async {
    final calls = <String>[];
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) async {
      calls.add(ep);
      return Res([commentFixture(ep)]);
    });
    final manager = ReaderChapterCommentsFeeds(onChanged: (_, __, ___) {});
    addTearDown(manager.dispose);
    final history = <CommentsController>[];
    for (var i = 0; i < 200; i++) {
      final feed = manager.chapterLoading(source, 'work', 'ep$i');
      history.add(feed);
      expect(identical(feed, manager.chapterLoading(source, 'work', 'ep$i')), isTrue);
    }
    await settleFeeds();
    expect(calls.length, 200, reason: 'Same chapter must share its first request');
    expect(history.where(isAlive).length, capacity);
    expect(history.take(200 - capacity).any(isAlive), isFalse);
    for (var i = 200 - capacity; i < 200; i++) {
      expect(identical(history[i], manager.chapterLoading(source, 'work', 'ep$i')), isTrue);
    }
    final revisited = manager.chapterLoading(source, 'work', 'ep0');
    await settleFeeds();
    expect(identical(history.first, revisited), isFalse);
    expect(calls.length, 201);
    expect(revisited.comments.single.id, 'ep0');
    expect(isAlive(history[200 - capacity]), isFalse);
  });

  test('borrowers protect old chapter; last detach reclaims without new lookup', () async {
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) async =>
      Res([commentFixture(ep)]));
    final manager = ReaderChapterCommentsFeeds();
    addTearDown(manager.dispose);
    final active = manager.chapterLoading(source, 'work', 'active');
    void first() {}
    void second() {}
    active.addListener(first);
    active.addListener(second);
    for (var i = 0; i < 200; i++) {
      manager.chapterLoading(source, 'work', 'ep$i');
    }
    await settleFeeds();
    expect(isAlive(active), isTrue);
    expect(active.comments.single.id, 'active');
    active.removeListener(first);
    await settleFeeds();
    expect(isAlive(active), isTrue);
    // AnimatedBuilder may replace a merged listenable synchronously.
    active.removeListener(second);
    active.addListener(second);
    await settleFeeds();
    expect(isAlive(active), isTrue);
    active.removeListener(second);
    await settleFeeds();
    expect(isAlive(active), isFalse);
  });

  test('settings reload only active plus recent window, never 200 history chapters', () async {
    final calls = <String>[];
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) async {
      calls.add(ep);
      return Res([commentFixture(ep)]);
    });
    final manager = ReaderChapterCommentsFeeds();
    addTearDown(manager.dispose);
    final active = manager.chapterLoading(source, 'work', 'active');
    void borrower() {}
    active.addListener(borrower);
    for (var i = 0; i < 200; i++) {
      manager.chapterLoading(source, 'work', 'ep$i');
    }
    await settleFeeds();
    calls.clear();
    source.refreshCommentProvider();
    await settleFeeds();
    final expected = {'active', for (var i = 200 - capacity; i < 200; i++) 'ep$i'};
    expect(calls.length, capacity + 1);
    expect(calls.toSet(), expected);
    expect(isAlive(active), isTrue, reason: 'Retirement cannot dispose a borrower');
    final replacement = manager.chapterLoading(source, 'work', 'active');
    expect(identical(replacement, active), isFalse);
    expect(replacement.comments.single.id, 'active');
    expect(calls.length, capacity + 1, reason: 'Footer joins settings replacement');
    // Neither generation is mounted yet, but the old borrow protects its key
    // across another revision and 200 more lookups before the reader rebuild.
    for (var i = 200; i < 400; i++) {
      manager.chapterLoading(source, 'work', 'ep$i');
    }
    calls.clear();
    source.refreshCommentProvider();
    await settleFeeds();
    expect(calls.length, capacity + 1);
    expect(calls.where((ep) => ep == 'active').length, 1);
    active.removeListener(borrower);
    await settleFeeds();
    expect(isAlive(active), isFalse);
    // active was made recent during replacement; it may stay in the idle LRU,
    // but the *total* idle set must again be exactly bounded after detach.
    calls.clear();
    source.refreshCommentProvider();
    await settleFeeds();
    expect(calls.length, capacity);
  });

  test('eviction cancels pending generation; retry and new singleflight survive', () async {
    final pending = Completer<Res<List<Comment>>>();
    var attempts = 0;
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) async {
      if (ep == 'pending') {
        attempts++;
        if (attempts == 1) return pending.future;
        if (attempts == 2) return const Res.error('retry me');
      }
      return Res([commentFixture(ep)]);
    });
    final manager = ReaderChapterCommentsFeeds();
    addTearDown(manager.dispose);
    final old = manager.chapterLoading(source, 'work', 'pending');
    expect(old.loading, isTrue);
    for (var i = 0; i < 200; i++) {
      manager.chapterLoading(source, 'work', 'ep$i');
    }
    await settleFeeds();
    expect(isAlive(old), isFalse);
    pending.complete(Res([commentFixture('late')]));
    await settleFeeds();
    expect(old.comments, isEmpty);
    final fresh = manager.chapterLoading(source, 'work', 'pending');
    expect(identical(fresh, manager.chapterLoading(source, 'work', 'pending')), isTrue);
    await settleFeeds();
    expect(attempts, 2);
    expect(fresh.error, contains('retry me'));
    await fresh.refresh();
    expect(attempts, 3);
    expect(fresh.comments.single.id, 'pending');
  });

  test('pending borrowed feed survives pressure and disposal waits for detach', () async {
    final pending = Completer<Res<List<Comment>>>();
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) async =>
      ep == 'pending' ? pending.future : Res([commentFixture(ep)]));
    final manager = ReaderChapterCommentsFeeds();
    addTearDown(manager.dispose);
    final active = manager.chapterLoading(source, 'work', 'pending');
    void borrower() {}
    active.addListener(borrower);
    for (var i = 0; i < 200; i++) {
      manager.chapterLoading(source, 'work', 'ep$i');
    }
    await settleFeeds();
    expect(isAlive(active), isTrue);
    expect(active.loading, isTrue);
    expect(identical(active, manager.chapterLoading(source, 'work', 'pending')), isTrue);
    pending.complete(Res([commentFixture('pending-result')]));
    await settleFeeds();
    expect(active.comments.single.id, 'pending-result');
    manager.dispose();
    await settleFeeds();
    expect(isAlive(active), isTrue);
    active.removeListener(borrower);
    await settleFeeds();
    expect(isAlive(active), isFalse);
  });
}
