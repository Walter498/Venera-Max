import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comments_feed.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

ComicSource sortSource({bool declared = true, CommentsOptionsLoader? loader}) {
  late ComicSource source;
  source = ComicSource(
    'Sort fixture', 'sort_fixture', null, null, null, null, const [], null,
    {'provider': {'type': 'select', 'default': 'tencent', 'options': [
      {'value': 'tencent', 'text': '腾讯'}, {'value': 'qingman', 'text': '青漫'}]}},
    null, null, null, null, null, '', '', '1', null, null, null, null,
    null, null, null, null, null, null, null, null, false, false, null, null,
    commentProviderSetting: declared ? 'provider' : null,
    commentsOptionsLoader: loader ?? (_, __, ___, ____, _____) async => const Res([]),
    chapterCommentsOptionsLoader: loader ?? (_, __, ___, ____, _____) async => const Res([]),
    resolveCommentCapabilities: (chapter) {
      if (source.commentProviderValue == 'qingman') {
        return chapter ? const CommentCapabilities(sorts: ['new', 'hot'], defaultSort: 'new')
          : const CommentCapabilities();
      }
      return const CommentCapabilities(sorts: ['new', 'hot', 'wonderful'], defaultSort: 'new');
    });
  return source;
}

void main() {
  setUpCommentsTestHost();
  late Directory temp;
  late String oldPath;
  setUp(() async {
    oldPath = App.dataPath;
    temp = await Directory.systemTemp.createTemp('comments-sort-');
    App.dataPath = temp.path;
  });
  tearDown(() async { App.dataPath = oldPath; await temp.delete(recursive: true); });

  test('read resolution is pure; explicit default selection persists across restart', () async {
    final source = sortSource();
    final original = jsonEncode(source.data);
    final revision = source.commentScopeRevision;
    for (var i = 0; i < 5; i++) { expect(source.preferredCommentSort(chapter: true), 'new'); }
    expect(jsonEncode(source.data), original);
    expect(source.commentScopeRevision, revision);
    expect(await File('${temp.path}/comic_source/sort_fixture.data').exists(), isFalse);
    await source.setPreferredCommentSort('wonderful', chapter: true);
    await source.setPreferredCommentSort('hot');
    final restarted = sortSource();
    await restarted.loadData();
    expect(restarted.preferredCommentSort(chapter: true), 'wonderful');
    expect(restarted.preferredCommentSort(), 'hot');
    expect(restarted.data['commentSortPreferences']['tencent'], {'chapter': 'wonderful', 'work': 'hot'});
  });

  test('provider and work/chapter isolation; invalid and unavailable never write', () async {
    final source = sortSource();
    await source.setPreferredCommentSort('wonderful', chapter: true);
    await source.setPreferredCommentSort('hot');
    await source.setCommentProvider('qingman');
    expect(source.preferredCommentSort(chapter: true), 'new');
    expect(source.preferredCommentSort(), isNull);
    final before = jsonEncode(source.data);
    final revision = source.commentScopeRevision;
    await source.setPreferredCommentSort('wonderful', chapter: true);
    await source.setPreferredCommentSort('hot');
    expect(jsonEncode(source.data), before);
    expect(source.commentScopeRevision, revision);
    await source.setPreferredCommentSort('hot', chapter: true);
    await source.setCommentProvider('tencent');
    expect(source.preferredCommentSort(chapter: true), 'wonderful');
    expect(source.preferredCommentSort(), 'hot');
  });

  test('legacy providerless source uses source key; effective revision emits once', () async {
    final source = sortSource(declared: false);
    var events = 0;
    void changed() { events++; }
    ComicSource.settingsChanges.addListener(changed);
    addTearDown(() => ComicSource.settingsChanges.removeListener(changed));
    final revision = source.commentScopeRevision;
    await source.setPreferredCommentSort('hot', chapter: true);
    expect(source.commentScopeRevision, isNot(revision));
    expect(source.data['commentSortPreferences']['sort_fixture']['chapter'], 'hot');
    await source.setPreferredCommentSort('hot', chapter: true);
    expect(events, 1);
    final restarted = sortSource(declared: false);
    await restarted.loadData();
    expect(restarted.preferredCommentSort(chapter: true), 'hot');
  });

  test('pending old-sort result cannot paint new chapter; exactly one replacement', () async {
    final pending = Completer<Res<List<Comment>>>();
    final calls = <String>[];
    final source = sortSource(loader: (_, ep, page, __, options) async {
      calls.add('$ep:${options['sort']}:$page');
      if (options['sort'] == 'new') return pending.future;
      return Res([commentFixture('hot-result')]);
    });
    final feeds = ReaderChapterCommentsFeeds();
    addTearDown(feeds.dispose);
    final old = feeds.chapterLoading(source, 'work', 'ep');
    await source.setPreferredCommentSort('hot', chapter: true);
    final current = feeds.chapterLoading(source, 'work', 'ep');
    expect(identical(old, current), isFalse);
    pending.complete(Res([commentFixture('late-new')]));
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['ep:new:1', 'ep:hot:1']);
    expect(current.comments.single.id, 'hot-result');
    expect(old.comments, isEmpty);
  });

  test('details session constructor reads stored work sort without writing', () async {
    final source = sortSource();
    await source.setPreferredCommentSort('hot');
    final before = jsonEncode(source.data);
    final session = DetailsCommentsSession(source: source, cid: 'work', subId: null);
    expect(session.controller.sort, 'hot');
    expect(jsonEncode(source.data), before);
    session.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('menu current value and only available options at scale $scale', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: CommentSortSelector(sorts: const ['new', 'hot'],
          value: 'hot', onSelected: (value) { selected = value; })))));
      expect(find.text('最热 ▾'), findsOneWidget);
      expect(find.text('精彩'), findsNothing);
      await tester.tap(find.byType(CommentSortSelector));
      await tester.pumpAndSettle();
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('最热'), findsOneWidget);
      expect(find.text('精彩'), findsNothing);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(selected, 'new');
      expect(tester.takeException(), isNull);
    });
  }

  for (final productionCallback in [false, true]) {
    testWidgets('feed callback=$productionCallback avoids double refresh; legacy still refreshes', (tester) async {
      final calls = <String?>[];
      final selected = <String>[];
      final feed = CommentsController(sort: 'new', loader: (_, sort) async {
        calls.add(sort); return const Res([]);
      });
      await feed.refresh();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommentsFeed(
        controller: feed, sorts: const ['new', 'hot'], itemBuilder: (_) => const Text('comment'),
        onSortSelected: productionCallback ? (sort) { selected.add(sort); } : null))));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CommentSortSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最热'));
      await tester.pumpAndSettle();
      expect(calls, productionCallback ? ['new'] : ['new', 'hot']);
      expect(selected, productionCallback ? ['hot'] : isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      feed.dispose();
    });
  }

  testWidgets('shared footer user selection reuses reader replacement request', (tester) async {
    final calls = <String?>[];
    final source = sortSource(loader: (_, __, ___, ____, options) async {
      calls.add(options['sort'] as String?);
      return Res([commentFixture('result', preview: false)]);
    });
    final feeds = ReaderChapterCommentsFeeds();
    Widget host() => MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      ChapterCommentsPreview(comicId: 'work', epId: 'ep', source: source,
        comicTitle: 'Work', chapterTitle: 'Chapter',
        sharedFeed: feeds.chapterLoading(source, 'work', 'ep')))));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CommentSortSelector));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('最热'));
      await source.saveData();
    });
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(calls, ['new', 'hot']);
    expect(find.text('最热 ▾'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    feeds.dispose();
    await tester.pump();
  });

  testWidgets('horizontal 200% keeps two real replies and metadata without nested scroll', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = commentsSource(chapterLegacy: (_, __, ___, ____) async => Res([
      Comment.fromJson({'id': 'parent', 'userName': 'Parent', 'content': 'Body text',
        'userLevel': 9, 'viewCount': 125, 'replyCount': 20, 'replyPreviews': [
          {'id': 'r1', 'userName': 'First reply', 'content': 'Actual first preview'},
          {'id': 'r2', 'userName': 'Second reply', 'content': 'Actual second preview'},
        ]}),
    ]));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
      data: const MediaQueryData(size: Size(844, 390), textScaler: TextScaler.linear(2)),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:
        ChapterCommentsPreview(comicId: 'work', epId: 'ep', source: source,
          comicTitle: 'Work', chapterTitle: 'Chapter', horizontal: true))))));
    await tester.pumpAndSettle();
    expect(find.text('Actual first preview'), findsOneWidget);
    expect(find.text('Actual second preview'), findsOneWidget);
    expect(find.text('Lv9'), findsOneWidget);
    expect(find.text('125 浏览'), findsOneWidget);
    expect(find.descendant(of: find.byType(ChapterCommentsPreview),
      matching: find.byType(Scrollable)), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
