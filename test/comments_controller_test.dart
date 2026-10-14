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
