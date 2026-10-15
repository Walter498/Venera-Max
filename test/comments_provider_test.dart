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
      final tag = 'recovery unavailable=$unavailable scale=$scale';
      void stage(String name) => debugPrintSynchronously('[$tag] $name');
      var calls = 0, events = 0;
      late ComicSource source;
      source = providerSource(loader: (_, __, ___, ____) async {
        calls++;
        stage('loader ${source.commentProviderValue} call=$calls');
        if (source.commentProviderValue == 'qingman') {
          return unavailable ? const Res<List<Comment>>([], available: false)
            : const Res.error('offline');
        }
        return Res(List.generate(6, (i) => Comment.fromJson({
          'id': 'tencent-$i', 'userName': 'Tencent reader',
          'content': 'tencent-recovered-$i',
        })));
      });
      stage('setup-save start');
      // Real filesystem IO must run outside testWidgets' fake-async zone.
      await tester.runAsync(() => source.setCommentProvider('qingman')
        .timeout(const Duration(seconds: 5)));
      stage('setup-save done');
      void changed() { events++; stage('settings-event $events'); }
      ComicSource.settingsChanges.addListener(changed);
      addTearDown(() => ComicSource.settingsChanges.removeListener(changed));
      stage('mount');
      await tester.pumpWidget(MaterialApp(home: MediaQuery(
        data: MediaQueryData(size: const Size(320, 700), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: ChapterCommentsPreview(
          source: source, comicId: 'work', epId: 'ep', comicTitle: 'Work', chapterTitle: 'Chapter'))))));
      final state = tester.state<ChapterCommentsPreviewState>(find.byType(ChapterCommentsPreview));
      Future<void> loaded(String phase) async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (!state.feed.loading) {
            stage('$phase loaded=${state.feed.loaded} error=${state.feed.error} available=${state.feed.available}');
            return;
          }
        }
        fail('$tag $phase spinner persisted after 20 frames; calls=$calls events=$events');
      }
      await loaded('initial');
      if (unavailable) {
        expect(state.feed.unavailable, isTrue);
      } else {
        expect(state.feed.error, contains('offline'));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.descendant(of: find.byType(ChapterCommentsPreview), matching: find.byType(Scrollable)), findsNothing);
      stage('menu open');
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('青漫连接配置'), findsOneWidget);
      stage('select tencent');
      await tester.tap(find.text('腾讯').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The menu callback performs real saveData IO, not just a UI mutation.
      var persisted = false;
      for (var i = 0; i < 50 && !persisted; i++) {
        persisted = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final file = File('${temp.path}/comic_source/provider_fixture.data');
          final saved = jsonDecode(await file.readAsString()
            .timeout(const Duration(seconds: 2)));
          return saved['settings']['provider'] == 'tencent';
        }) ?? false;
        // IO was launched by the real menu callback in fake-async: process
        // its continuations between real-IO checks instead of awaiting it there.
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(persisted, isTrue, reason: '$tag selection was not persisted after 50 checks');
      stage('selection-save done');
      await loaded('recovered');
      expect(source.commentProviderValue, 'tencent');
      expect(events, 1);
      expect(calls, 2);
      expect(state.feed.error, isNull);
      expect(state.feed.loaded, isTrue);
      expect(state.feed.comments.length, 6);
      for (var i = 0; i < 4; i++) {
        expect(find.text('tencent-recovered-$i'), findsOneWidget);
      }
      expect(find.text('tencent-recovered-4'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.descendant(of: find.byType(ChapterCommentsPreview), matching: find.byType(Scrollable)), findsNothing);
      expect(tester.takeException(), isNull);
      stage('unmount');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      stage('done');
    });
    }
  }
}
