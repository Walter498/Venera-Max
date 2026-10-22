import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/res.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  test('legacy source is called with exactly four ordered parameters', () async {
    final calls = <List<dynamic>>[];
    final source = commentsSource(legacy: (id,sub,page,reply) async {
      calls.add([id,sub,page,reply]); return const Res([],subData:1);
    });
    await source.loadCommentPage('book','chapter',1,null,sort:'hot');
    await source.loadCommentPage('book','chapter',2,'topic');
    expect(calls, [['book','chapter',1,null],['book','chapter',2,'topic']]);
    expect(source.commentCapabilities,isNull);
  });
  test('chapter invalid episode id rejects without invoking either hook', () async {
    var legacyCalls = 0, optionsCalls = 0;
    final legacySource = commentsSource(chapterLegacy: (id, ep, page, reply) async {
      legacyCalls++;
      return const Res<List<Comment>>([], subData: 1);
    });
    final optionsSource = commentsSource(
      chapterCapabilities: const CommentCapabilities(sorts: ['hot']),
      chapterOptions: (id, ep, page, reply, options) async {
        optionsCalls++;
        return const Res<List<Comment>>([], subData: 1);
      });
    for (final source in [legacySource, optionsSource]) {
      for (final epId in <String?>[null, '', '  ', 'null', ' null ']) {
        final result = await source.loadCommentPage('book', epId, 1, null,
          chapter: true, sort: 'hot');
        expect(result.error, isTrue);
        expect(result.errorMessage, 'Chapter comments require a valid episode id');
      }
      final result = await source.loadCommentPage('book', 'ep', 1, null, chapter: true);
      expect(result.error, isFalse);
    }
    expect(legacyCalls, 1);
    expect(optionsCalls, 1);
  });
  test('work legacy retains nullable second argument and four argument order', () async {
    final calls = <List<dynamic>>[];
    final source = commentsSource(legacy: (id, sub, page, reply) async {
      calls.add([id, sub, page, reply]);
      return const Res<List<Comment>>([], subData: 1);
    });
    final result = await source.loadCommentPage('book', null, 1, 'parent', sort: 'hot');
    expect(result.error, isFalse);
    expect(calls, [['book', null, 1, 'parent']]);
  });
  test('options gate forwards sort and parent id without mutating settings', () async {
    final calls = <List<dynamic>>[];
    final source = commentsSource(chapterCapabilities: const CommentCapabilities(
      sorts:['new','hot','wonderful'],defaultSort:'new',canLoadReplies:true),
      chapterOptions:(id,ep,page,reply,options) async {
        calls.add([id,ep,page,reply,options]); return const Res([],subData:1,total:0);
      });
    await source.loadCommentPage('b','ep',1,'topic-A',chapter:true,sort:'hot');
    await source.loadCommentPage('b','ep',1,'topic-B',chapter:true,sort:'wonderful');
    expect(calls[0],['b','ep',1,'topic-A',{'sort':'hot'}]);
    expect(calls[1],['b','ep',1,'topic-B',{'sort':'wonderful'}]);
    expect(source.canReadReplies(commentFixture('topic-A'),chapter:true),isTrue);
  });
  test('capability without hook falls back, missing declaration ignores options', () async {
    var legacyCalls = 0, newCalls = 0;
    Future<Res<List<Comment>>> old(String id,String? sub,int page,String? reply) async {
      legacyCalls++; return const Res<List<Comment>>([],subData:1);
    }
    Future<Res<List<Comment>>> options(String id,String? sub,int page,String? reply,Map<String,dynamic> opts) async {
      newCalls++; return const Res<List<Comment>>([],subData:1);
    }
    await commentsSource(legacy:old,capabilities:const CommentCapabilities(sorts:['hot']))
      .loadCommentPage('a',null,1,null,sort:'hot');
    await commentsSource(legacy:old,options:options).loadCommentPage('b',null,1,null);
    expect(legacyCalls,2); expect(newCalls,0);
  });
  test('disabled reply capability preserves readonly counters', () {
    final source = commentsSource(legacy:(a,b,c,d) async => const Res([],subData:1),
      capabilities:const CommentCapabilities(canLoadReplies:false));
    expect(source.canReadReplies(commentFixture('topic')),isFalse);
    expect(commentFixture('topic').replyCount,2);
    expect(source.canReadReplies(Comment.fromJson({'id':null})),isFalse);
    expect(source.canReadReplies(Comment.fromJson({'id':'null'})),isFalse);
  });
  test('late new response and its finally never overwrite hot', () async {
    final slow = Completer<Res<List<Comment>>>();
    final hot = Completer<Res<List<Comment>>>();
    final c = CommentsController(sort:'new',loader:(page,sort) => sort == 'new' ? slow.future : hot.future);
    final first = c.refresh(); final second = c.refresh(nextSort:'hot');
    slow.complete(Res([commentFixture('old')],subData:1)); await first;
    expect(c.loading,isTrue); expect(c.comments,isEmpty);
    hot.complete(Res([commentFixture('hot')],subData:1)); await second;
    expect(c.comments.single.id,'hot'); expect(c.loading,isFalse); c.dispose();
  });
  test('scope disposed ignores successful or failed late result', () async {
    final slow = Completer<Res<List<Comment>>>();
    final c = CommentsController(loader:(_,__) => slow.future);
    final pending = c.refresh(); c.dispose(); slow.complete(const Res.error('late'));
    await pending; expect(c.error,isNull);
  });
  test('first error is not empty; successful retry clears error', () async {
    var count=0;
    final c = CommentsController(loader:(_,__) async => count++ == 0 ?
      const Res.error('offline') : const Res([],subData:1,total:0));
    await c.refresh(); expect(c.confirmedEmpty,isFalse); expect(c.error,isNotNull);
    await c.refresh(); expect(c.error,isNull); expect(c.confirmedEmpty,isTrue); c.dispose();
  });
  test('pagination failure keeps next page, explicit retry deduplicates IDs', () async {
    var failed=false;
    final c=CommentsController(loader:(page,sort) async {
      if(page==1) return Res([commentFixture('one')],subData:3);
      if(!failed) { failed=true; return const Res.error('page unavailable'); }
      return Res([commentFixture('one'),commentFixture('two')],subData:3);
    });
    await c.refresh(); await c.loadMore(); expect(c.page,1); expect(c.pageError,isNotNull);
    await c.loadMore(); expect(c.page,2); expect(c.pageError,isNull);
    expect(c.comments.map((c)=>c.id),['one','two']); c.dispose();
  });
  testWidgets('opted-in failures retry every five seconds until success', (tester) async {
    var calls = 0;
    final c = CommentsController(autoRetry: true, loader: (_, __) async {
      calls++;
      if (calls < 3) return const Res.error('offline');
      return Res([commentFixture('recovered')], subData: 1);
    });
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.error, isNotNull);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    expect(c.error, isNotNull);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(calls, 2);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 3);
    expect(c.error, isNull);
    expect(c.comments.single.id, 'recovered');
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 3);
  });
  testWidgets('successful empty and unavailable results stop retrying', (tester) async {
    for (final available in [true, false]) {
      var calls = 0;
      final c = CommentsController(autoRetry: true, loader: (_, __) async {
        if (++calls == 1) return const Res.error('offline');
        return Res<List<Comment>>([], subData: 0, total: 0, available: available);
      });
      addTearDown(c.dispose);
      await c.refresh();
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 2);
      expect(c.error, isNull);
      expect(c.confirmedEmpty, isTrue);
      expect(c.unavailable, !available);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
    }
  });
  testWidgets('page retry keeps existing data and never overlaps a slow request', (tester) async {
    final calls = <int>[];
    final pending = Completer<Res<List<Comment>>>();
    var pageAttempts = 0;
    final c = CommentsController(autoRetry: true, loader: (page, _) async {
      calls.add(page);
      if (page == 1) return Res([commentFixture('one')], subData: 3);
      pageAttempts++;
      if (pageAttempts == 1) return const Res.error('page offline');
      if (pageAttempts == 2) return pending.future;
      return Res([commentFixture('two')], subData: 3);
    });
    addTearDown(c.dispose);
    await c.refresh();
    await c.loadMore();
    expect(c.page, 1);
    expect(c.pageError, isNotNull);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, [1, 2, 2]);
    expect(c.loadingMore, isTrue);
    expect(c.comments.single.id, 'one');
    await c.loadMore();
    await c.ensureLoaded();
    await tester.pump(const Duration(seconds: 20));
    expect(calls, [1, 2, 2]);
    pending.complete(const Res.error('still offline'));
    await tester.pump();
    expect(c.pageError, isNotNull);
    await tester.pump(const Duration(milliseconds: 4999));
    expect(calls, [1, 2, 2]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, [1, 2, 2, 2]);
    expect(c.page, 2);
    expect(c.pageError, isNull);
    expect(c.comments.map((comment) => comment.id), ['one', 'two']);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, [1, 2, 2, 2]);
  });
  testWidgets('manual refresh cancels timer and rejects a late retry result', (tester) async {
    final calls = <String?>[];
    final manual = Completer<Res<List<Comment>>>();
    final stale = Completer<Res<List<Comment>>>();
    final c = CommentsController(autoRetry: true, sort: 'new', loader: (_, sort) {
      calls.add(sort);
      if (calls.length == 1) return Future.value(const Res.error('offline'));
      if (calls.length == 2) return manual.future;
      if (calls.length == 3) return Future.value(const Res.error('offline again'));
      if (calls.length == 4) return stale.future;
      return Future.value(Res([commentFixture('hot')], subData: 1));
    });
    addTearDown(c.dispose);
    await c.refresh();
    await tester.pump(const Duration(seconds: 4));
    final refresh = c.refresh();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, ['new', 'new']);
    manual.complete(Res([commentFixture('manual')], subData: 1));
    await refresh;
    await tester.pump(const Duration(seconds: 10));
    expect(calls.length, 2);
    await c.refresh();
    await tester.pump(const Duration(seconds: 5));
    expect(calls.length, 4);
    await c.ensureLoaded();
    await tester.pump(const Duration(seconds: 10));
    expect(calls.length, 4, reason: 'probe must not overlap a first-page retry');
    await c.refresh(nextSort: 'hot');
    stale.complete(const Res.error('late old sort'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, ['new', 'new', 'new', 'new', 'hot']);
    expect(c.comments.single.id, 'hot');
    expect(c.error, isNull);
  });
  testWidgets('manual page retry replaces the pending automatic retry', (tester) async {
    final calls = <int>[];
    final pending = Completer<Res<List<Comment>>>();
    final c = CommentsController(autoRetry: true, loader: (page, _) {
      calls.add(page);
      if (page == 1) return Future.value(Res([commentFixture('one')], subData: 2));
      if (calls.length == 2) return Future.value(const Res.error('offline'));
      return pending.future;
    });
    addTearDown(c.dispose);
    await c.refresh();
    await c.loadMore();
    await tester.pump(const Duration(seconds: 4));
    final manual = c.loadMore();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, [1, 2, 2]);
    pending.complete(Res([commentFixture('two')], subData: 2));
    await manual;
    await tester.pump(const Duration(seconds: 10));
    expect(calls, [1, 2, 2]);
    expect(c.page, 2);
  });
  testWidgets('dispose and invalidate cancel pending timers and ignore late retries', (tester) async {
    for (final invalidate in [false, true]) {
      for (final inFlight in [false, true]) {
        for (final succeeds in [false, true]) {
          var calls = 0;
          final late = Completer<Res<List<Comment>>>();
          final c = CommentsController(autoRetry: true, loader: (_, __) {
            if (++calls == 1) return Future.value(const Res.error('offline'));
            return late.future;
          });
          await c.refresh();
          if (inFlight) await tester.pump(const Duration(seconds: 5));
          final previousError = c.error;
          if (invalidate) {
            c.invalidate();
          } else {
            c.dispose();
          }
          late.complete(succeeds ? Res([commentFixture('old-chapter')], subData: 1)
            : const Res.error('late failure'));
          await tester.pump();
          await c.refresh();
          await c.loadMore();
          await c.ensureLoaded();
          await tester.pump(const Duration(seconds: 30));
          expect(calls, inFlight ? 2 : 1);
          expect(c.comments, isEmpty);
          expect(c.error, invalidate ? null : previousError);
          if (invalidate) {
            expect(c.loaded, isFalse);
            expect(c.loading, isFalse);
            c.dispose();
          }
        }
      }
    }
  });
  testWidgets('ordinary comments do not retry by default, including page failures', (tester) async {
    for (final firstPageFails in [true, false]) {
      final calls = <int>[];
      final c = CommentsController(loader: (page, _) async {
        calls.add(page);
        if (firstPageFails || page > 1) return const Res.error('offline');
        return Res([commentFixture('one')], subData: 2);
      });
      addTearDown(c.dispose);
      await c.refresh();
      if (!firstPageFails) await c.loadMore();
      await tester.pump(const Duration(seconds: 30));
      expect(calls, firstPageFails ? [1] : [1, 2]);
    }
  });
  test('filtered empty never hides raw nonempty or ends unknown pagination', () async {
    final c=CommentsController(block:(_)=>true,loader:(_,__) async => Res([commentFixture('raw')]));
    await c.refresh(); expect(c.confirmedEmpty,isFalse); expect(c.hasMore,isTrue); c.dispose();
  });
  test('metadata preserves null versus zero, relative date and genuine preview', () {
    final c=Comment.fromJson({'id':null,'avatar':'','time':'  ','score':0,'replyCount':null,
      'replyPreview':{'content':'reply','userName':'R'}});
    expect(c.id,isNull);expect(c.avatar,isNull);expect(c.time,isNull);
    expect(c.score,0);expect(c.replyCount,isNull);expect(c.replyPreview!.content,'reply');
    expect(Comment.parseTime('3年前'),'3年前'); expect(Comment.parseTime(1700000000),isNotNull);
    expect(Comment.parseTime(1700000000000),Comment.parseTime(1700000000));
    expect(Comment.parseTime(1.2),isNull); expect(Comment.nonNegativeInt(-1),isNull);
  });
  test('settings migration default, range and reader-specific persistence store', () {
    expect(chapterCommentsScale(null),2);expect(chapterCommentsScale('bad'),2);
    expect(chapterCommentsScale(0.1),0.5);expect(chapterCommentsScale(10),4);
    expect(appdata.settings['chapterCommentsHeightScale'],2.0);
    appdata.settings.setEnabledComicSpecificSettings('fixture','comments_fixture',true);
    appdata.settings.setReaderSetting('fixture','comments_fixture','chapterCommentsHeightScale',3.0);
    expect(appdata.settings.getReaderSetting('fixture','comments_fixture','chapterCommentsHeightScale'),3.0);
    appdata.settings.resetComicReaderSettings('fixture@comments_fixture');
  });

  test('runtime unavailable is hidden and cannot paginate, refresh can recover', () async {
    var absent = true;
    final c = CommentsController(loader: (_,__) async => absent
      ? const Res<List<Comment>>([],subData:0,total:0,available:false)
      : Res([commentFixture('restored')],subData:1,available:true));
    await c.refresh();
    expect(c.unavailable,isTrue); expect(c.hasMore,isFalse); expect(c.error,isNull);
    absent=false; await c.refresh();
    expect(c.unavailable,isFalse); expect(c.comments.single.id,'restored'); c.dispose();
  });
  test('maxPage zero success is empty but first page error stays retryable', () async {
    final c=CommentsController(loader:(_,__) async => const Res([],subData:0,total:0));
    await c.refresh(); expect(c.confirmedEmpty,isTrue); expect(c.hasMore,isFalse); c.dispose();
    final error=CommentsController(loader:(_,__) async => const Res.error('offline'));
    await error.refresh(); expect(error.unavailable,isFalse); expect(error.confirmedEmpty,isFalse);
    expect(error.error,isNotNull); error.dispose();
  });
  test('unknown reply capability preserves only the proven legacy entry', () {
    final source=commentsSource(legacy:(a,b,c,d) async => const Res([],subData:1));
    // fa7afe19 exposed this path for non-null replyCount and a valid parent id.
    // The previous false assertion froze the B1 regression, not compatibility.
    expect(source.canReadReplies(commentFixture('topic')),isTrue);
    expect(source.canReadReplies(commentFixture('topic', replies: 0)),isTrue);
    expect(source.canReadReplies(commentFixture('topic', replies: null)),isFalse);
    expect(source.canReadReplies(Comment.fromJson({'id':null,'replyCount':2})),isFalse);
    expect(source.canReadReplies(Comment.fromJson({'id':'null','replyCount':2})),isFalse);
  });
  test('chapter legacy fallback keeps exactly four ordered arguments', () async {
    final calls=<List<dynamic>>[];
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(sorts:['new']),
      chapterLegacy:(id,ep,page,reply) async {
        calls.add([id,ep,page,reply]); return const Res([],subData:0);
      });
    await source.loadCommentPage('book','ep',2,'parent',chapter:true,sort:'new');
    expect(calls,[['book','ep',2,'parent']]);
  });
  testWidgets('shared chapter feeds opt in and retirement cancels retry', (tester) async {
    var calls = 0;
    final source = commentsSource(chapterLegacy: (_, __, ___, ____) async {
      calls++;
      return const Res.error('offline');
    });
    final feeds = ReaderChapterCommentsFeeds();
    final feed = feeds.chapterLoading(source, 'book', 'ep');
    await tester.pump();
    expect(feed.autoRetry, isTrue);
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    feeds.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2);
  });
  testWidgets('chapter switch ignores an in-flight old chapter retry', (tester) async {
    final calls = <String?>[];
    final oldRetry = Completer<Res<List<Comment>>>();
    final source = commentsSource(chapterLegacy: (_, ep, __, ___) {
      calls.add(ep);
      if (ep == 'old') {
        if (calls.length == 1) return Future.value(const Res.error('offline'));
        return oldRetry.future;
      }
      return Future.value(Res([commentFixture('new-chapter')], subData: 1));
    });
    Widget page(String ep) => MaterialApp(home: ChapterCommentsPage(
      comicId: 'book', epId: ep, source: source,
      comicTitle: 'Book', chapterTitle: ep));
    await tester.pumpWidget(page('old'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(calls, ['old']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['old', 'old']);
    await tester.pumpWidget(page('new'));
    await tester.pump();
    oldRetry.complete(Res([commentFixture('old-chapter')], subData: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, ['old', 'old', 'new']);
    final tiles = tester.widgetList<CommentPresentation>(find.byType(CommentPresentation));
    expect(tiles.map((tile) => tile.comment.id), ['new-chapter']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('explicit false keeps chapter reply counters but cannot navigate', (tester) async {
    var calls = 0;
    final source = commentsSource(
      chapterCapabilities: const CommentCapabilities(canLoadReplies: false),
      chapterLegacy: (id, ep, page, reply) async {
        calls++;
        expect(reply, isNull, reason: 'disabled replies must not navigate');
        return Res([commentFixture('parent')], subData: 1);
      });
    await tester.pumpWidget(MaterialApp(home: ChapterCommentsPage(
      comicId: 'work', epId: 'ep', source: source,
      comicTitle: 'Work', chapterTitle: 'Chapter')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ChapterCommentsPage), findsOneWidget);
    expect(find.text('查看回复详情'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(tester.widgetList<CommentPresentation>(find.byType(CommentPresentation))
        .every((tile) => tile.onReply == null), isTrue);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ChapterCommentsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
