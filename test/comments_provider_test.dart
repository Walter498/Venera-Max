import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

ComicSource providerSource({ChapterCommentsLoader? loader, bool declared = true, CommentCapabilities? capabilities}) => ComicSource(
  'Provider fixture', 'provider_fixture', null, null, null, null, const [], null,
  {'provider': {'title':'默认评论接口', 'type':'select', 'default':'tencent',
    'options':[{'value':'tencent','text':'腾讯'}, {'value':'qingman','text':'青漫'}]}},
  null, null, null, null, null, '', '', '1', null, null, loader, null,
  null, null, null, null, null, null, null, null, false, false, null, null,
  chapterCommentCapabilities: capabilities,
  commentProviderSetting: declared ? 'provider' : null);

void main() {
  setUpCommentsTestHost();
  late Directory temp;
  late String oldPath;
  setUp(() async {
    oldPath = App.dataPath;
    temp = await Directory.systemTemp.createTemp('comments-provider-');
    App.dataPath = temp.path;
  });
  tearDown(() async { App.dataPath = oldPath; await temp.delete(recursive: true); });

  test('declared options default and persisted setting share source storage/event', () async {
    final source = providerSource();
    var events = 0;
    void changed() { events++; }
    ComicSource.settingsChanges.addListener(changed);
    addTearDown(() => ComicSource.settingsChanges.removeListener(changed));
    expect(source.commentProviderValue, 'tencent');
    expect(source.commentProviderOptions, {'tencent':'腾讯','qingman':'青漫'});
    final before = source.commentScopeRevision;
    await source.setCommentProvider('qingman');
    expect(source.commentScopeRevision, isNot(before));
    expect(events, 1);
    final stored = jsonDecode(await File('${temp.path}/comic_source/provider_fixture.data').readAsString());
    expect(stored['settings']['provider'], 'qingman');
    // Original source settings page uses exactly this mutation/save path.
    source.data['settings']['provider'] = 'tencent';
    await source.saveData();
    expect(events, 2);
    await source.setCommentProvider('unknown');
    expect(events, 2);
  });

  test('source revision preload rejects pending old-provider response', () async {
    final old = Completer<Res<List<Comment>>>();
    late ComicSource source;
    source = providerSource(loader: (_, __, ___, ____) async {
      if (source.commentProviderValue == 'tencent') return old.future;
      return Res([commentFixture('qingman-only')]);
    });
    final feeds = ReaderChapterCommentsFeeds();
    addTearDown(feeds.dispose);
    final first = feeds.chapterLoading(source, 'work', 'ep');
    await source.setCommentProvider('qingman');
    final next = feeds.chapterLoading(source, 'work', 'ep');
    expect(identical(first, next), isFalse);
    old.complete(Res([commentFixture('tencent-late')]));
    await Future<void>.delayed(Duration.zero);
    expect(next.comments.map((c) => c.id), ['qingman-only']);
    expect(first.comments, isEmpty);
  });

  test('disabled chapter capability keeps recovery but never invokes loader', () async {
    var calls = 0;
    final source = providerSource(capabilities: const CommentCapabilities(enabled: false),
      loader: (_, __, ___, ____) async { calls++; return const Res([]); });
    expect(source.hasChapterComments, isTrue);
    expect((await source.loadCommentPage('work', 'ep', 1, null, chapter: true)).error, isTrue);
    expect(calls, 0);
  });

  test('save failure restores provider and notifies rollback', () async {
    final source = providerSource();
    final blocked = File('${temp.path}/blocked');
    await blocked.writeAsString('not a directory');
    App.dataPath = blocked.path;
    await expectLater(source.setCommentProvider('qingman'), throwsA(isA<FileSystemException>()));
    expect(source.commentProviderValue, 'tencent');
  });

  test('profile return invalidates settings revision without changing stored default', () {
    final source = providerSource();
    final before = source.commentScopeRevision;
    source.refreshCommentProvider();
    expect(source.commentScopeRevision, isNot(before));
    expect(source.commentProviderValue, 'tencent');
    expect(source.data['settings'], isNull);
  });

  testWidgets('legacy source never exposes provider menu', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CommentProviderSelector(source: providerSource(declared: false)))));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    for (final unavailable in [false, true]) {
    testWidgets('footer recovery error/unavailable=$unavailable at scale $scale', (tester) async {
      final source = providerSource(loader: (_, __, ___, ____) async => unavailable
        ? const Res<List<Comment>>([], available: false) : const Res.error('offline'));
      await source.setCommentProvider('qingman');
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: const Size(320, 700), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: ChapterCommentsPreview(
          source: source, comicId: 'work', epId: 'ep', comicTitle: 'Work', chapterTitle: 'Chapter'))))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(ChapterCommentsPreview), matching: find.byType(Scrollable)), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('青漫连接配置'), findsOneWidget);
      await tester.tap(find.text('腾讯'));
      await tester.pumpAndSettle();
      expect(source.commentProviderValue, 'tencent');
      expect(tester.takeException(), isNull);
    });
    }
  }
}
