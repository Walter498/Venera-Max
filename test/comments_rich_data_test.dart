import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_context_stats.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/res.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  Map<String, dynamic> reply(String id) => {'id': id, 'userName': 'user $id',
    'content': 'body $id', 'time': '2026-10-15'};
  const context = <String, dynamic>{'provider': 'tencent',
    'comicFavoriteCount': 0, 'chapterLikeCount': 12345};

  test('legacy Comment and genuine zero retain source compatibility', () {
    final c = Comment.fromJson({'replyPreview': reply('legacy'),
      'userLevel': 0, 'viewCount': 0, 'replyCount': 0});
    expect(c.replyPreview?.id, 'legacy');
    expect(c.effectiveReplyPreviews.single.id, 'legacy');
    expect(c.userLevel, 0); expect(c.viewCount, 0); expect(c.replyCount, 0);
    final empty = Comment.fromJson({});
    expect(empty.replyPreview, isNull); expect(empty.replyPreviews, isEmpty);
    expect(empty.userLevel, isNull); expect(empty.viewCount, isNull);
  });
  test('unknown malformed negative and unsafe integers do not invent metadata', () {
    for (final value in [null, -1, '0', 1.5, true, {}, 9007199254740992]) {
      final c = Comment.fromJson({'userLevel': value, 'viewCount': value,
        'badges': [null, 0, '', ' 热评 ', '关联作品：原文']});
      expect(c.userLevel, isNull); expect(c.viewCount, isNull);
      expect(c.badges, [' 热评 ', '关联作品：原文']);
      expect(Res.parseCommentContext({'provider': 'tencent',
        'comicFavoriteCount': value})?.containsKey('comicFavoriteCount'), isFalse);
    }
  });
  for (final size in [0, 1, 2, 5]) {
    test('$size actual previews are bounded at two without replyCount synthesis', () {
      final c = Comment.fromJson({'replyCount': 99,
        'replyPreviews': [for (var i = 0; i < size; i++) reply('$i')]});
      expect(c.replyPreviews.length, size > 2 ? 2 : size);
      expect(c.replyCount, 99);
    });
  }
  test('deduplicate ids and id-less identity, include distinct legacy fallback', () {
    final c = Comment.fromJson({'id': 'parent', 'replyPreviews': [
      reply('parent'), reply('a'), reply('a'), null, 7], 'replyPreview': reply('b')});
    expect(c.replyPreviews.map((e) => e.id), ['a', 'b']);
    final anonymous = {'userName': 'reader', 'content': 'same', 'time': 'today'};
    final d = Comment.fromJson({'replyPreviews': [anonymous, {...anonymous},
      {...anonymous, 'content': 'different'}]});
    expect(d.replyPreviews.map((e) => e.content), ['same', 'different']);
  });
  test('strip both nested preview protocols including cyclic malformed maps', () {
    final child = reply('child');
    child['replyPreview'] = child; child['replyPreviews'] = [child];
    final c = Comment.fromJson({'replyPreviews': [child]});
    expect(c.replyPreviews.single.replyPreviews, isEmpty);
    expect(c.replyPreviews.single.replyPreview, isNull);
  });
  test('context sanitizer preserves zero and never invents a provider', () {
    expect(Res.parseCommentContext(context), context);
    for (final value in [null, [], {}, {'provider': ''}, {'comicFavoriteCount': 1}]) {
      expect(Res.parseCommentContext(value), isNull);
    }
    expect(const Res.error('offline').commentContext, isNull);
  });
  test('next page omission preserves context, provider switch never borrows counts', () async {
    final c = CommentsController(loader: (page, _) async => Res<List<Comment>>(
      [Comment.fromJson(reply('$page'))], subData: 3,
      commentContext: page == 1 ? context : page == 3 ? {'provider': 'qingman'} : null));
    await c.refresh(); await c.loadMore();
    expect(c.commentContext, context);
    await c.loadMore(); expect(c.commentContext, {'provider': 'qingman'});
    c.dispose();
  });
  test('generation reset and late response cannot restore stale Tencent context', () async {
    final slow = Completer<Res<List<Comment>>>();
    var calls = 0;
    final c = CommentsController(loader: (_, __) => ++calls == 1 ? slow.future :
      Future.value(const Res<List<Comment>>([], commentContext: {'provider': 'qingman'})));
    final old = c.refresh(); await c.refresh(nextSort: 'hot');
    slow.complete(const Res<List<Comment>>([], commentContext: context)); await old;
    expect(c.commentContext, {'provider': 'qingman'});
    c.invalidate(); expect(c.commentContext, isNull); c.dispose();
  });
  test('unavailable clears context; failed later page does not fabricate or erase it', () async {
    var mode = 0;
    final c = CommentsController(loader: (page, _) async {
      if (mode == 1) return const Res.error('offline');
      if (mode == 2) {
        return const Res<List<Comment>>([], available: false,
          commentContext: context);
      }
      return Res([Comment.fromJson(reply('a'))], subData: 3, commentContext: context);
    });
    await c.refresh(); mode = 1; await c.loadMore();
    expect(c.commentContext, context); expect(c.pageError, isNotNull);
    await c.refresh(); expect(c.commentContext, isNull); expect(c.error, isNotNull);
    mode = 0; await c.refresh(); mode = 2; await c.loadMore();
    expect(c.commentContext, isNull); expect(c.unavailable, isTrue); c.dispose();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('shared presentation real previews and metadata scale $scale', (tester) async {
      var opened = 0;
      final c = Comment.fromJson({'userName': 'parent', 'content': 'parent body',
        'userLevel': 0, 'viewCount': 12345, 'badges': ['热评'],
        'replyPreviews': [reply('a'), reply('b'), reply('c')]});
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: CommentPresentation(
          comment: c, selectable: false, onReply: () => opened++,
          actions: const Text('custom actions')))))));
      expect(find.text('body a'), findsOneWidget); expect(find.text('body b'), findsOneWidget);
      expect(find.text('body c'), findsNothing); expect(find.text('Lv0'), findsOneWidget);
      expect(find.text('热评'), findsOneWidget); expect(find.text('1.2万 浏览'), findsOneWidget);
      expect(find.byTooltip('浏览量 12345'), findsOneWidget);
      expect(find.byType(Scrollable), findsOneWidget); // Outer only.
      expect(find.byType(SelectableText), findsNothing);
      await tester.ensureVisible(find.text('查看回复详情').first);
      await tester.tap(find.text('查看回复详情').first); expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Tencent stats are read-only, zero real and unknown hidden', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: CommentContextStats(context: context))));
    expect(find.text('收藏0'), findsOneWidget); expect(find.text('本章获赞1.2万'), findsOneWidget);
    expect(find.byTooltip('本章获赞 12345'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing); expect(find.byType(InkWell), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      CommentContextStats(context: {'provider': 'qingman', 'comicFavoriteCount': 99}))));
    expect(find.textContaining('收藏'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('full presentation remains selectable and missing metadata is hidden', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommentPresentation(
      comment: Comment.fromJson({'content': 'selectable actual body'})))));
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(CommentMetadata), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.textContaining('Lv'), findsNothing);
    expect(find.text('查看回复详情'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('invalidate pending response cannot restore any context', () async {
    final pending = Completer<Res<List<Comment>>>();
    final c = CommentsController(loader: (_, __) => pending.future);
    final loading = c.refresh(); c.invalidate();
    pending.complete(const Res<List<Comment>>([], commentContext: context));
    await loading;
    expect(c.commentContext, isNull); expect(c.loaded, isFalse);
    c.dispose();
  });
  group('real parser context routes', () {
    late Directory temp;
    late String oldPath;
    final keys = <String>[];
    setUpAll(() async {
      oldPath = App.dataPath;
      temp = Directory.systemTemp.createTempSync('comments_rich_');
      App.dataPath = temp.path;
      await initCommentsTestHost();
      await JsEngine().init();
    });
    tearDown(() {
      for (final key in keys) {
        JsEngine().runCode('delete ComicSource.sources.$key;');
      }
      keys.clear();
    });
    tearDownAll(() {
      try { JsEngine().dispose(); } finally {
        App.dataPath = oldPath;
        temp.deleteSync(recursive: true);
      }
    });
    var serial = 0;
    for (final chapter in [false, true]) {
      for (final options in [false, true]) {
        test('${chapter ? "chapter" : "work"} ${options ? "options" : "legacy"} forwards context', () async {
          final key = 'rich_context_${serial++}'; keys.add(key);
          final method = chapter ? 'loadChapterComments' : 'loadComments';
          final name = '$method${options ? "WithOptions" : ""}';
          final capability = chapter ? 'chapterCommentCapabilities' : 'commentCapabilities';
          final source = await ComicSourceParser().parse('''
class RichContextFixture extends ComicSource {
  name = "Rich fixture"; key = "$key"; version = "1.0.0";
  minAppVersion = null; search = {}; categoryComics = {};
  init() { super.init(); this.richReady = true; }
  comic = {
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    ${options ? '$capability: {sorts: ["hot"], canLoadReplies: true},' : ''}
    async $name(id, sub, page, reply, options) {
      if (page === 2) return {available: false, commentContext: {provider: 'tencent', chapterLikeCount: 99}};
      if (page === 3) throw new Error('offline fixture');
      return {comments: [{id: 'parent', userLevel: 0, viewCount: 2,
        replyPreviews: [{id: 'a', content: 'one'}, {id: 'b', content: 'two'}]}],
        maxPage: 4, total: 7, commentContext: {
          provider: 'tencent', comicFavoriteCount: 0, chapterLikeCount: 12345}};
    }
  };
}
''', '${temp.path}/$key.js');
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(JsEngine().runCode('ComicSource.sources.$key.richReady'), isTrue);
          final res = await source.loadCommentPage('book', 'ep', 1, null,
            chapter: chapter, sort: 'hot');
          expect(res.error, isFalse); expect(res.commentContext, context);
          expect(res.subData, 4); expect(res.total, 7);
          expect(res.data.single.replyPreviews.length, 2);
          expect(res.data.single.userLevel, 0);
          final absent = await source.loadCommentPage('book', 'ep', 2, null,
            chapter: chapter, sort: 'hot');
          expect(absent.available, isFalse); expect(absent.commentContext, isNull);
          final failed = await source.loadCommentPage('book', 'ep', 3, null,
            chapter: chapter, sort: 'hot');
          expect(failed.error, isTrue); expect(failed.commentContext, isNull);
        });
      }
    }
  });
}
