import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_details_cache.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_translation/translation_store.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/read_later.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'comments_fixtures.dart';

// Dart mock loaders sit behind the real source registry, repository and page.
// Real JS/source/local readiness is initialized below; comment loaders remain
// Dart fixtures. No HTTP, device plugin boot or App.isInitialized override.
ComicSource _source(LoadComicFunc info, CommentsLoader comments) => ComicSource(
  'Details fixture', 'details_page_fixture', null, null, null, null,
  const [], null, null, info, null, null, null, null, '', '', '1.0',
  comments, null, null, null, null, null, null, null, null, null, null,
  null, false, false, null, null,
  commentCapabilities: const CommentCapabilities(canLoadReplies: false),
)..data['settings'] = <String, dynamic>{'domain': 'fixture.invalid'};

ComicDetails _details(String cover, {String? subId}) => ComicDetails.fromJson({
  'title': 'Real details host', 'cover': cover,
  'tags': <String, List<String>>{}, 'sourceKey': 'details_page_fixture',
  'comicId': 'work', 'subId': subId,
});

Comment _comment(String id) => Comment.fromJson({
  'id': id, 'userName': 'Details reader', 'content': 'Discussion $id',
  'time': '2026-10-14', 'score': 3, 'replyCount': 2,
});

Finder get _topEntry => find.byIcon(Icons.chat_bubble_outline_rounded);
Finder get _previewEntry => find.text('View more');

// SideBarRoute is a non-opaque PopupRoute: the detail preview stays mounted.
// Check route identity/count BEFORE scoping text so a duplicate full route is
// a failure, not something hidden by .first or hitTestable filtering.
Finder get _fullRoute => find.byType(CommentsPage, skipOffstage: false);

CommentsPage _activeFullPage(WidgetTester tester) {
  expect(_fullRoute, findsOneWidget);
  final route = ModalRoute.of(tester.element(_fullRoute));
  expect(route, isA<SideBarRoute>());
  expect(route!.isCurrent, isTrue);
  return tester.widget<CommentsPage>(_fullRoute);
}

Finder _fullText(String text) => find.descendant(
  of: _fullRoute,
  matching: find.text(text, skipOffstage: false),
  skipOffstage: false,
);

Finder _previewText(String text) => find.descendant(
  of: find.byType(ComicPage, skipOffstage: false),
  matching: find.text(text, skipOffstage: false),
  skipOffstage: false,
);

void _expectFullText(WidgetTester tester, String text) {
  _activeFullPage(tester);
  // Exact count within the full page also catches duplicate feed rendering.
  expect(_fullText(text), findsOneWidget);
  expect(_fullText(text).hitTestable(), findsOneWidget);
}

// Real database/file work must get real event turns. Fixed-clock settling is
// unsuitable for a pending probe (spinner), so all polling has a hard bound.
// setUpAll runs on the real event loop (not a testWidgets fake clock).
// Fail with the exact pending dependency instead of consuming the CI step.
Future<void> _hostStage(String name, FutureOr<void> Function() action) async {
  final elapsed = Stopwatch()..start();
  debugPrint('COMMENTS_DETAILS_HOST start $name');
  try {
    await Future<void>.sync(action).timeout(const Duration(seconds: 30));
    debugPrint('COMMENTS_DETAILS_HOST done $name ${elapsed.elapsedMilliseconds}ms');
  } catch (error) {
    debugPrint('COMMENTS_DETAILS_HOST failed $name '
        '${elapsed.elapsedMilliseconds}ms: $error');
    rethrow;
  }
}

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 120; i++) {
    await _frames(tester, 1);
    if (ready()) return;
  }
  fail('Details host did not reach the expected state in 120 frames');
}

Future<void> _bottom(WidgetTester tester) async {
  final scroll = find.descendant(
    of: find.byType(ComicPage), matching: find.byType(CustomScrollView),
  ).first;
  final state = tester.state<ScrollableState>(find.descendant(
    of: scroll, matching: find.byType(Scrollable),
  ).first);
  // SliverLazyToBoxAdapter may materialize the section header one frame later.
  for (var i = 0; i < 3; i++) {
    state.position.jumpTo(state.position.maxScrollExtent);
    await _frames(tester, 2);
  }
}

Future<void> _top(WidgetTester tester) async {
  final scroll = find.descendant(
    of: find.byType(ComicPage), matching: find.byType(CustomScrollView),
  ).first;
  final state = tester.state<ScrollableState>(find.descendant(
    of: scroll, matching: find.byType(Scrollable),
  ).first);
  state.position.jumpTo(0);
  await _frames(tester, 4);
}

Future<void> _entries(WidgetTester tester, bool visible) async {
  await _top(tester);
  expect(_topEntry, visible ? findsOneWidget : findsNothing);
  await _bottom(tester);
  expect(_previewEntry, visible ? findsOneWidget : findsNothing);
  expect(find.byType(CommentsPage), findsNothing);
}

void _pageTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(520, 1100);
      tester.view.devicePixelRatio = 1;
      try {
        await body(tester);
        expect(tester.takeException(), isNull);
      } finally {
        // Borrowed page and owner must unmount before registry/DB teardown.
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester, 2);
          expect(tester.takeException(), isNull);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          App.mainNavigatorKey = null;
        }
      }
    });
  });
}

void main() {
  setUpCommentsTestHost();
  late Directory directory;
  late String oldDataPath;
  late String oldCachePath;
  late String cover;
  final sources = <ComicSource>[];

  final closers = <void Function()>[];
  var pathsChanged = false;
  var hostReady = false;

  // Run every close even if saving or a preceding close fails. Consume the
  // stack so failed setup and tearDownAll cannot close the same host twice.
  Future<void> closeStores() async {
    if (closers.isEmpty) return;
    final stage = closers.length;
    final close = closers.removeLast();
    try {
      await _hostStage('cleanup.resource.$stage', close);
    } finally {
      await closeStores();
    }
  }

  void registerStore(String filename, void Function() close) {
    final path = '${directory.path}/$filename';
    closers.add(() {
      try {
        close();
      } finally {
        // Some managers' close() returns before isInitialized becomes true.
        // Release a handle opened by a failed/partial init as well.
        DatabaseGateway.instance.closeManaged(path);
      }
    });
  }

  Future<void> releaseHost() async {
    if (!pathsChanged) return;
    try {
      // Drain settings/implicit-data writes before removing their real files.
      await _hostStage('appdata.saveData', () => appdata.saveData(false));
    } finally {
      try {
        await closeStores();
      } finally {
        App.dataPath = oldDataPath;
        App.cachePath = oldCachePath;
        pathsChanged = false;
        hostReady = false;
        directory.deleteSync(recursive: true);
      }
    }
  }

  setUpAll(() async {
    oldDataPath = App.dataPath;
    oldCachePath = App.cachePath;
    directory = Directory.systemTemp.createTempSync('comments_details_page_');
    App.dataPath = directory.path;
    App.cachePath = directory.path;
    pathsChanged = true;
    try {
      // The shared host already awaited real translations and FontLoader.load.
      debugPrint('COMMENTS_DETAILS_HOST translations/fonts ready');
      // LocalFavoritesManager.init awaits appdata.ensureInit(). That is a
      // readiness barrier, NOT an initializer. Complete the real Init contract
      // in this isolated directory before awaiting the dependent store.
      await _hostStage('appdata.init', appdata.init);
      closers.add(App.domain.close);
      await _hostStage('domain.init', () => App.domain.init(directory.path));
      await _hostStage('authorIndex.init',
          () => App.authorIndex.init(directory.path));
      registerStore('history.db', HistoryManager().close);
      await _hostStage('history.init', HistoryManager().init);
      registerStore('local_favorite.db', LocalFavoritesManager().close);
      await _hostStage('favorites.init', LocalFavoritesManager().init);
      // initCounts starts a gateway isolate read without awaiting it. Drain
      // that real read before any test can fail and start closing stores.
      await _hostStage('favorites.backgroundRead',
          () => DatabaseGateway.instance.runExclusive(() async {}));
      registerStore('read_later.db', ReadLaterManager().close);
      await _hostStage('readLater.init', ReadLaterManager().init);
      registerStore('image_translation.db', TranslationStore().close);
      await _hostStage('translationStore.init', TranslationStore().init);
      // ensureInit() only waits: initialize JS, then the source registry, then
      // LocalManager so ComicPage.onDataLoaded can query the real local DB.
      // Register cleanup before init to release partially initialized resources.
      final js = JsEngine();
      closers.add(js.dispose);
      await _hostStage('jsEngine.init', js.init);
      expect(js.runCode('typeof ComicSource'), 'function',
          reason: 'real JS init must expose the source contract');
      expect(js.runCode('typeof ComicSource.sources'), 'object');
      final registry = ComicSourceManager();
      closers.add(() {
        try {
          for (final source in registry.all()) {
            registry.remove(source.key);
          }
        } finally {
          registry.dispose();
        }
      });
      await _hostStage('sourceManager.init', registry.init);
      // Use LocalManager's real persisted path contract in the isolated host;
      // this keeps local files here without a path-provider plugin or override.
      await _hostStage('localPath.write', () async {
        final local = Directory('${directory.path}/local');
        await local.create();
        await File('${directory.path}/local_path').writeAsString(local.path);
      });
      final localManager = LocalManager();
      registerStore('local.db', () {
        try {
          localManager.close();
        } finally {
          localManager.dispose();
        }
      });
      await _hostStage('localManager.init', localManager.init);
      // init schedules auto-resume after 3s. Drain that real callback while
      // dependencies are alive, including when an assertion/setup later fails.
      await _hostStage('localManager.deferredResume',
          () => Future<void>.delayed(const Duration(seconds: 3)));
      // Open the real cache here so teardown never creates an unused database.
      await _hostStage('detailsCache.open', () {
        closers.add(ComicDetailsCache().close);
      });
      // A local valid image prevents a cover request without mocking providers.
      await _hostStage('cover.write', () {
        final file = File('${directory.path}/cover.gif');
        file.writeAsBytesSync(const [
          71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0,
          255, 255, 255, 33, 249, 4, 1, 0, 0, 0, 0, 44, 0, 0, 0, 0,
          1, 0, 1, 0, 0, 2, 2, 68, 1, 0, 59,
        ]);
        cover = 'file://${file.path}';
      });
      hostReady = true;
    } finally {
      if (!hostReady) await releaseHost();
    }
  });

  tearDown(() {
    for (final source in sources) {
      ComicSourceManager().remove(source.key);
    }
    sources.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  tearDownAll(releaseHost);

  Future<void> mount(WidgetTester tester, ComicSource source) async {
    expect(ComicSourceManager().add(source), isTrue);
    sources.add(source);
    // Exercise the production cache write path. find() currently intentionally
    // returns null; do not pretend this host has cached subId hydration.
    ComicDetailsCache().update(source.key, 'work', _details(cover));
    expect(ComicDetailsCache().find(source.key, 'work'), isNull);
    App.mainNavigatorKey = App.rootNavigatorKey;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: App.rootNavigatorKey,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const ComicPage(
            id: 'work', sourceKey: 'details_page_fixture',
          ),
        )),
        child: const Text('Open real details'),
      ))),
    ));
    await tester.tap(find.text('Open real details'));
    await _until(tester, () => find.text('Real details host').evaluate().isNotEmpty);
    await _frames(tester);
  }

  Future<CommentsPage> openFull(WidgetTester tester) async {
    await _top(tester);
    await tester.ensureVisible(_topEntry);
    await tester.tap(_topEntry);
    await _until(tester, () => find.byType(CommentsPage).evaluate().isNotEmpty);
    await _frames(tester, 20);
    final full = _activeFullPage(tester);
    expect(full.sharedSession, isNotNull);
    expect(full.sharedSession!.controller.loaded, isTrue);
    return full;
  }

  _pageTest('real ComicPage pending then nonempty gates both entries', (tester) async {
    var calls = 0;
    final pending = Completer<Res<List<Comment>>>();
    await mount(tester, _source((_) async => Res(_details(cover)),
      (id, sub, page, reply) {
        expect((id, sub, page, reply), ('work', null, 1, null));
        calls++;
        return pending.future;
      }));
    expect(calls, 1, reason: 'preload happens before scrolling to preview');
    await _bottom(tester);
    await _entries(tester, false);
    pending.complete(Res([_comment('visible')], subData: 1, total: 1));
    await _frames(tester, 20);
    await _bottom(tester);
    await _entries(tester, true);
    expect(find.text('Discussion visible'), findsOneWidget);
    expect(calls, 1);
  });

  for (final outcome in ['no-match', 'nonunique', 'available-false', 'empty']) {
    _pageTest('real ComicPage $outcome hides top and preview without failure route', (tester) async {
      final pending = Completer<Res<List<Comment>>>();
      var calls = 0;
      await mount(tester, _source((_) async => Res(_details(cover)),
        (a, b, c, d) { calls++; return pending.future; }));
      await _bottom(tester);
      await _entries(tester, false);
      pending.complete(outcome == 'empty'
        ? const Res<List<Comment>>([], subData: 1, total: 0)
        : const Res<List<Comment>>([], available: false, total: 0, subData: 0));
      await _frames(tester, 20);
      await _bottom(tester);
      await _entries(tester, false);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(NetworkError), findsNothing);
      expect(calls, 1);
    });
  }

  _pageTest('real ComicPage network diagnostics Retry recovers without failed full page', (tester) async {
    var calls = 0;
    await mount(tester, _source((_) async => Res(_details(cover)),
      (a, b, c, d) async {
        calls++;
        return calls == 1
          ? const Res.error('Timeout: no-match connection failed')
          : Res([_comment('retry')], subData: 1, total: 1);
      }));
    await _bottom(tester);
    await _entries(tester, false);
    expect(find.textContaining('Timeout: no-match connection failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _frames(tester, 20);
    await _bottom(tester);
    await _entries(tester, true);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Discussion retry'), findsOneWidget);
    expect(calls, 2);
  });

  _pageTest('real top and preview routes borrow and reopen without another first page', (tester) async {
    var calls = 0;
    await mount(tester, _source((_) async => Res(_details(cover)),
      (a, b, c, d) async {
        calls++;
        return Res([_comment('shared')], subData: 1, total: 1);
      }));
    final first = await openFull(tester);
    _expectFullText(tester, 'Discussion shared');
    expect(calls, 1);
    App.rootNavigatorKey.currentState!.pop();
    await _frames(tester, 20);
    expect(first.sharedSession!.isCurrent, isTrue);
    await _bottom(tester);
    await _entries(tester, true);
    await tester.tap(_previewEntry);
    await _until(tester, () => find.byType(CommentsPage).evaluate().isNotEmpty);
    await _frames(tester, 20);
    final reopened = _activeFullPage(tester);
    expect(reopened.sharedSession, same(first.sharedSession));
    _expectFullText(tester, 'Discussion shared');
    expect(calls, 1);
    App.rootNavigatorKey.currentState!.pop();
    // Wait for actual unmount, not for a visible host behind a non-opaque route.
    await _until(tester, () => _fullRoute.evaluate().isEmpty);
    App.rootNavigatorKey.currentState!.pop();
    await _until(tester, () => find.byType(ComicPage,
        skipOffstage: false).evaluate().isEmpty);
    expect(find.text('Open real details'), findsOneWidget);
    expect(first.sharedSession!.isCurrent, isFalse);
  });

  _pageTest('existing settings event invalidates open borrowed route without retry', (tester) async {
    var calls = 0;
    final source = _source((_) async => Res(_details(cover)),
      (a, b, c, d) async {
        calls++;
        return Res([_comment(calls == 1 ? 'settings-old' : 'settings-new')],
          subData: 1, total: 1);
      });
    await mount(tester, source);
    final full = await openFull(tester);
    final oldSession = full.sharedSession!;
    final oldWords = appdata.settings['blockedCommentWords'];
    try {
      source.data['settings'] = {'domain': 'settings-event.invalid'};
      // The application already publishes settings changes through Settings.
      // Do not drive LoadingState.retry: this tests the actual listener wire.
      appdata.settings['blockedCommentWords'] = List.of(oldWords as List);
      await _until(tester, () => calls == 2);
      await _frames(tester, 20);
      expect(oldSession.isCurrent, isFalse);
      expect(oldSession.controller.comments, isEmpty);
      expect(find.text('Discussion settings-old'), findsNothing);
      expect(find.byType(CommentsPage), findsOneWidget);
      expect(_activeFullPage(tester), same(full));
      expect(_fullText('Discussion settings-old'), findsNothing);
      expect(tester.takeException(), isNull);
      App.rootNavigatorKey.currentState!.pop();
      await _frames(tester, 20);
      final reopened = await openFull(tester);
      expect(reopened.sharedSession, isNot(same(oldSession)));
      _expectFullText(tester, 'Discussion settings-new');
      expect(calls, 2, reason: 'new scope and reopening share one first page');
    } finally {
      appdata.settings['blockedCommentWords'] = oldWords;
    }
  });

  for (final change in ['source', 'revision', 'subId']) {
    for (final refreshPending in [false, true]) {
    _pageTest('real owner $change invalidates borrowed full page '
      '(refresh pending: $refreshPending)', (tester) async {
      var sourceRevisionChanged = false;
      var oldCalls = 0;
      var newCalls = 0;
      String? subId;
      final late = Completer<Res<List<Comment>>>();
      final source = _source((_) async => Res(_details(cover, subId: subId)),
        (a, sub, page, reply) {
          if (oldCalls++ == 0) {
            return Future.value(Res([_comment('old')], subData: 1, total: 1));
          }
          if (change == 'subId' && sub == 'new-sub') {
            newCalls++;
            return Future.value(Res([_comment('new')], subData: 1, total: 1));
          }
          if (change == 'revision' && sourceRevisionChanged) {
            newCalls++;
            return Future.value(Res([_comment('new')], subData: 1, total: 1));
          }
          return late.future;
        });
      await mount(tester, source);
      final full = await openFull(tester);
      final oldSession = full.sharedSession!;
      _expectFullText(tester, 'Discussion old');
      // Start a real controller refresh while the borrowed route remains open.
      final oldRefresh = refreshPending
        ? oldSession.controller.refresh() : Future<void>.value();
      await _frames(tester, 2);
      expect(oldCalls, refreshPending ? 2 : 1);
      if (change == 'source') {
        ComicSourceManager().remove(source.key);
        final replacement = _source((_) async => Res(_details(cover)),
          (a, b, c, d) async {
            newCalls++;
            return Res([_comment('new')], subData: 1, total: 1);
          });
        expect(ComicSourceManager().add(replacement), isTrue);
        sources.add(replacement);
      } else if (change == 'revision') {
        source.data['settings'] = {'domain': 'changed.invalid'};
        sourceRevisionChanged = true;
      } else {
        subId = 'new-sub';
      }
      // Use the existing public LoadingState retry path, not a hand-built
      // session. It runs the real repository/cache/background-info lifecycle.
      final owner = tester.state<LoadingState<ComicPage, ComicDetails>>(
        find.byType(ComicPage, skipOffstage: false));
      owner.retry();
      await _until(tester, () => newCalls == 1);
      expect(oldSession.isCurrent, isFalse);
      late.complete(Res([_comment('late-old')], subData: 1, total: 1));
      await oldRefresh;
      await _frames(tester, 20);
      if (refreshPending) expect(oldSession.controller.comments, isEmpty);
      expect(find.text('Discussion old'), findsNothing);
      expect(find.text('Discussion late-old'), findsNothing);
      expect(_activeFullPage(tester), same(full));
      expect(_fullText('Discussion old'), findsNothing);
      expect(_fullText('Discussion late-old'), findsNothing);
      expect(tester.takeException(), isNull);
      App.rootNavigatorKey.currentState!.pop();
      await _frames(tester, 20);
      await _bottom(tester);
      await _entries(tester, true);
      expect(_previewText('Discussion new'), findsOneWidget);
      final reopened = await openFull(tester);
      expect(reopened.sharedSession, isNot(same(oldSession)));
      expect(reopened.sharedSession!.subId, change == 'subId' ? 'new-sub' : null);
      expect(reopened.sharedSession!.source, same(ComicSource.find(source.key)));
      _expectFullText(tester, 'Discussion new');
      expect(newCalls, 1, reason: 'new scope first page is reused on reopen');
      App.rootNavigatorKey.currentState!.pop();
      await _frames(tester, 20);
      App.rootNavigatorKey.currentState!.pop();
      await _frames(tester, 20);
      expect(find.text('Open real details'), findsOneWidget);
    });
    }
  }

  _pageTest('unmount detail owner and borrowed route before late response is safe', (tester) async {
    var calls = 0;
    final late = Completer<Res<List<Comment>>>();
    await mount(tester, _source((_) async => Res(_details(cover)),
      (a, b, c, d) {
        calls++;
        return calls == 1
          ? Future.value(Res([_comment('exit')], subData: 1, total: 1))
          : late.future;
      }));
    final full = await openFull(tester);
    final session = full.sharedSession!;
    final refresh = session.controller.refresh();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(session.isCurrent, isFalse);
    late.complete(Res([_comment('after-exit')], subData: 1, total: 1));
    await refresh;
    await _frames(tester, 20);
    expect(session.controller.comments, isEmpty);
    expect(find.byType(CommentsPage), findsNothing);
    expect(find.byType(ComicPage), findsNothing);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
