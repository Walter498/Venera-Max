import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/image_provider/reader_image.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/read_later.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

// Mount the REAL Reader, image shells, slivers, and scroll-listener resolver.
// Count candidate visits, not elapsed time, with hundreds of historical pages.
// Native host setup intentionally mirrors comments_reader_integration_test.
void main() {
  setUpCommentsTestHost();
  late Directory directory;
  late String oldPath;
  var serial = 0;
  final keys = <String>[];
  const pageCount = 240;
  late String imageUrl;

  const memoryChannel = MethodChannel('flutter_memory_info');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(memoryChannel,(call) async {
        if(call.method=='getFreePhysicalMemorySize') return 512 * 1024 * 1024;
        throw MissingPluginException('Unexpected Reader memory method: ${call.method}');
      });
    oldPath = App.dataPath;
    directory = Directory.systemTemp.createTempSync('geometry_reader_');
    App.dataPath = directory.path;
    Future<void> stage(String name, Future<void> Function() action) async {
      debugPrint('COMMENTS_READER_HOST start $name');
      await action().timeout(const Duration(seconds: 30));
      debugPrint('COMMENTS_READER_HOST done $name');
    }
    // ensureInit is a readiness barrier, not an initializer. Satisfy the real
    // dependencies before favorites/local can await them; no readiness mocks.
    await stage('appdata.init', appdata.init);
    await stage('js.init', JsEngine().init);
    await stage('sources.init', ComicSourceManager().init);
    await stage('history.init', HistoryManager().init);
    await stage('readLater.init', ReadLaterManager().init);
    await stage('favorites.init', LocalFavoritesManager().init);
    await stage('favorites.backgroundRead', () =>
      DatabaseGateway.instance.runExclusive(() async {}));
    final library = Directory('${directory.path}/library')..createSync();
    File('${directory.path}/local_path').writeAsStringSync(library.path);
    await stage('local.init', LocalManager().init);
  });
  tearDownAll(() async {
    try {
      try {
        await appdata.saveData(false);
        LocalManager().close();
        ReadLaterManager().close();
        LocalFavoritesManager().close();
        HistoryManager().close();
      } finally {
        JsEngine().dispose(); // strict QuickJS disposal, even on host failure
      }
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(memoryChannel,null);
      App.dataPath = oldPath;
      directory.deleteSync(recursive: true);
    }
  });

  Future<void> frames(WidgetTester tester, [int count = 20]) async {
    for (var i = 0; i < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<ComicSource> source(WidgetTester tester, String mode) async {
    final image = await createTestImage(width: 390, height: 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${directory.path}/page_$serial.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    imageUrl = file.uri.toString();
    final key = 'reader_comments_${serial++}';
    keys.add(key);
    final parsed = await ComicSourceParser().parse('''
class ReaderCommentsFixture extends ComicSource {
  name = "Reader comments fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  search = {}; categoryComics = {};
  init = null;
  settings = {
    provider: {type:'select', default:'tencent', options:[{value:'tencent',text:'Tencent'}]},
    one: {type:'callback', callback:() => 'one'},
    two: {type:'callback', callback:() => 'two'},
    three: {type:'callback', callback:() => 'three'}
  };
  comic = {
    commentProviderSetting: 'provider',
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    async loadEp(id, ep) {
      return {images: Array($pageCount).fill(${jsonEncode(imageUrl)})};
    },
    chapterCommentCapabilities: {canLoadReplies: true},
    async loadChapterComments(id, ep, page, reply) {
      if (reply != null) return {comments: [{id:"reply",userName:"reply",content:"actual reply"}],maxPage:1};
      if (ep === "two") return {available:false};
      globalThis.readerCommentCalls = (globalThis.readerCommentCalls || 0) + 1;
      return {comments:[{id:'mother',userName:'Reader',content:'Fixed local comment',replyCount:0}], maxPage:1};
    }
  };
}
''', '${directory.path}/$key.js');
    expect(ComicSourceManager().add(parsed), isTrue);
    // Mirror the existing shelf/home fixture: supply decoded real image bytes
    // to the production provider cache. This avoids unrelated file:// parsing
    // and HTTP, while ComicImage/PhotoView still lay out real image dimensions.
    for(final ep in ['one','two']) {
      final provider = ReaderImageProvider(imageUrl,key,'work',ep,1,
        enableResize:mode.startsWith('continuous'));
      PaintingBinding.instance.imageCache.putIfAbsent(provider,() =>
        OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image:image.clone()))));
    }
    image.dispose();
    return parsed;
  }

  Future<dynamic> mount(WidgetTester tester, ComicSource s, String mode) async {
    appdata.settings.setEnabledComicSpecificSettings('work', s.key, true);
    for (final entry in <String, dynamic>{
      'readerMode': mode,
      'showChapterComments': true,
      'showChapterCommentsAtEnd': true,
      'enableContinuousChapterReading': true,
      'enablePageAnimation': false,
      'enableTurnPageByVolumeKey': false,
      'readerPageSpacing': 0.0,
      'readerCenterPageOnTurn': false,
      'limitImageWidth': false,
    }.entries) {
      appdata.settings.setReaderSetting('work', s.key, entry.key, entry.value);
    }
    final type = ComicType.fromKey(s.key);
    final history = History.fromMap({
      'id': 'work', 'type': type.value, 'title': 'work', 'cover': '',
      'time': DateTime.now().millisecondsSinceEpoch, 'ep': 1, 'page': 1,
    });
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Reader(type: type, cid: 'work', name: 'Work', author: '',
        tags: const [],
        chapters: const ComicChapters({'one': 'First', 'two': 'Second'}),
        history: history),
    )));
    await frames(tester, 40);
    final dynamic state = tester.state(find.byType(Reader));
    expect(state.isLoading, isFalse);
    expect(state.images.length, pageCount);
    return state;
  }

  for (final mode in ['continuousTopToBottom']) {
    testWidgets('$mode settled provider footer keeps native exports constant during long reading',
      (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final samples = <ReaderContinuousGeometryWork>[];
      try {
        await tester.runAsync(() async {
          try {
            final s = await source(tester, mode);
            final dynamic state = await mount(tester, s, mode);
            final ownedBefore = ComicSourceParser.debugOwnedFunctionCount(s.key);
            expect(ownedBefore, greaterThanOrEqualTo(3));
            final requestsBefore = JsEngine().runCode('globalThis.readerCommentCalls');
            expect(requestsBefore, greaterThan(0));
            debugReaderContinuousGeometryWork = samples.add;
            final scroll = tester.widget<CustomScrollView>(find.descendant(
              of: find.byType(Reader), matching: find.byType(CustomScrollView)));
            final controller = scroll.controller!;
            final firstShell = find.byWidgetPredicate((widget) =>
              widget.runtimeType.toString() == '_ContinuousImageGeometry',
              skipOffstage: false).first;
            final actualSize = tester.getSize(firstShell);
            final extent = mode == 'continuousTopToBottom'
                ? actualSize.height : actualSize.width;
            // Real listener + layout for every step, not a copied geometry
            // helper, synthetic list, or one direct far-page repivot.
            for (var page = 2; page <= 190; page++) {
              controller.jumpTo((page - 1) * extent + 20);
              await frames(tester, 2);
            }
            expect(state.chapter, 1);
            expect(state.page, greaterThanOrEqualTo(180));
            expect(samples.length, greaterThan(100));
            final lateSamples = samples.sublist(samples.length - 40);
            for (final work in lateSamples) {
              expect(work.entries, greaterThanOrEqualTo(pageCount));
              expect(work.mountedImages, inInclusiveRange(1, 20));
              // A forward pass plus (only at the scroll tail) a reverse pass.
              expect(work.visitedImages, inInclusiveRange(1, 2 * work.mountedImages));
              expect(work.visitedImages, lessThan(work.entries ~/ 4));
            }
            // Independently count actual mounted layout shells, ensuring the
            // diagnostic is not merely reporting a constant "window size".
            final mounted = find.byWidgetPredicate((widget) =>
              widget.runtimeType.toString() == '_ContinuousImageGeometry',
              skipOffstage: false).evaluate().length;
            expect(mounted, inInclusiveRange(1, 20));
            expect(samples.last.mountedImages, mounted);

            // Exercise both directions and a real GlobalKey repivot lifecycle;
            // image state replacement must not leave stale geometry records.
            state.toPage(30);
            await frames(tester, 20);
            expect(state.page, 30);
            state.toPage(200);
            await frames(tester, 20);
            expect(state.page, 200);
            for (var i = 0; i < 4; i++) {
              controller.jumpTo(controller.offset + extent / 4);
              await frames(tester, 2);
            }
            for (final work in samples.reversed.take(4)) {
              expect(work.mountedImages, inInclusiveRange(1, 20));
              expect(work.visitedImages, lessThanOrEqualTo(2 * work.mountedImages));
            }
            final ownedAfter = ComicSourceParser.debugOwnedFunctionCount(s.key);
            expect(ownedAfter, ownedBefore,
              reason:'Provider checks on actual scroll frames must not retain settings callback exports');
            expect(JsEngine().runCode('globalThis.readerCommentCalls'), requestsBefore,
              reason:'Settled same-chapter scrolling must not reload comments');
            stdout.writeln('READER_METADATA_NATIVE before=$ownedBefore after=$ownedAfter samples=${samples.length}');
            expect(tester.takeException(), isNull);
          } finally {
            debugReaderContinuousGeometryWork = null;
            JsEngine().runCode('if (globalThis.resolveReaderComments) globalThis.resolveReaderComments({available:false});');
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester, 20);
            for (final key in keys) {
              ComicSourceManager().remove(key);
              JsEngine().runCode('delete ComicSource.sources.$key;');
              appdata.settings.resetComicReaderSettings('work@$key');
            }
            keys.clear();
            JsEngine().runCode('delete globalThis.resolveReaderComments; delete globalThis.rejectReaderComments; delete globalThis.readerCommentCalls;');
            await appdata.saveData(false);
          }
        });
      } finally {
        debugReaderContinuousGeometryWork = null;
        debugDefaultTargetPlatformOverride = previous;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
