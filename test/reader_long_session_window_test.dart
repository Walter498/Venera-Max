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

// Mount the REAL Reader with 12 chapters and walk forward/back through all
// pages. Count production index probes and retained prefetch keys, not time.
// Native host setup intentionally mirrors comments_reader_integration_test.
void main() {
  setUpCommentsTestHost();
  late Directory directory;
  late String oldPath;
  var serial = 0;
  final keys = <String>[];
  const pageCount = 12;
  const chapterCount = 12;
  late String imageUrl;

  const memoryChannel = MethodChannel('flutter_memory_info');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(memoryChannel,(call) async {
        if(call.method=='getFreePhysicalMemorySize') return 512 * 1024 * 1024;
        throw MissingPluginException('Unexpected Reader memory method: ${call.method}');
      });
    oldPath = App.dataPath;
    directory = Directory.systemTemp.createTempSync('long_session_reader_');
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
  comic = {
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    async loadEp(id, ep) {
      return {images: Array($pageCount).fill(${jsonEncode(imageUrl)})};
    },
    chapterCommentCapabilities: {canLoadReplies: true},
    async loadChapterComments(id, ep, page, reply) {
      if (reply != null) return {comments: [{id:"reply",userName:"reply",content:"actual reply"}],maxPage:1};
      if (ep !== "c6" || globalThis.readerPendingResolved) return {available:false};
      globalThis.readerCommentCalls = (globalThis.readerCommentCalls || 0) + 1;
      return await new Promise((resolve, reject) => {
        globalThis.resolveReaderComments = resolve;
        globalThis.rejectReaderComments = reject;
      });
    }
  };
}
''', '${directory.path}/$key.js');
    expect(ComicSourceManager().add(parsed), isTrue);
    // Mirror the existing shelf/home fixture: supply decoded real image bytes
    // to the production provider cache. This avoids unrelated file:// parsing
    // and HTTP, while ComicImage/PhotoView still lay out real image dimensions.
    for(final ep in List.generate(chapterCount, (i) => 'c${i + 1}')) {
      final provider = ReaderImageProvider(imageUrl,key,'work',ep,1,
        enableResize:mode.startsWith('continuous'));
      PaintingBinding.instance.imageCache.putIfAbsent(provider,() =>
        OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image:image.clone()))));
    }
    image.dispose();
    return parsed;
  }

  Future<dynamic> mount(WidgetTester tester, ComicSource s, String mode,
      {bool comments = false}) async {
    appdata.settings.setEnabledComicSpecificSettings('work', s.key, true);
    for (final entry in <String, dynamic>{
      'readerMode': mode,
      'showChapterComments': comments,
      'showChapterCommentsAtEnd': comments,
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
        chapters: ComicChapters({for (var i = 1; i <= chapterCount; i++)
          'c$i': 'Chapter $i'}),
        history: history),
    )));
    await frames(tester, 40);
    final dynamic state = tester.state(find.byType(Reader));
    expect(state.isLoading, isFalse);
    expect(state.images.length, pageCount);
    return state;
  }

  for (final mode in ['continuousTopToBottom', 'continuousLeftToRight',
    'continuousRightToLeft']) {
    testWidgets('$mode multi-chapter forward/back keeps lookup and dedup bounded',
      (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final sessions = <ReaderContinuousSessionWork>[];
      final probes = <int>[];
      final navigation = <Map<String, Object?>>[];
      try {
        await tester.runAsync(() async {
          try {
            final s = await source(tester, mode);
            final dynamic state = await mount(tester, s, mode, comments: true);
            debugReaderContinuousSessionWork = sessions.add;
            debugReaderContinuousIndexProbes = probes.add;
            debugReaderContinuousNavigation = (event) {
              navigation.add(event);
              if (navigation.length > 16) {
                navigation.removeAt(0);
              }
            };
            ScrollController controller() => tester.widget<CustomScrollView>(
              find.descendant(of: find.byType(Reader),
                matching: find.byType(CustomScrollView))).controller!;
            Finder shell(int chapter, int page) => find.byWidgetPredicate((w) {
              if (w.runtimeType.toString() != '_ContinuousImageGeometry') {
                return false;
              }
              final dynamic geometry = w;
              return geometry.entry.chapter == chapter && geometry.entry.page == page;
            });
            double leading(Finder item) {
              final rect = tester.getRect(item);
              return mode == 'continuousTopToBottom' ? rect.top :
                mode == 'continuousRightToLeft' ? 390 - rect.right : rect.left;
            }
            // Walk every image using real scrolling. Adjacent boundary turns
            // cross the real separator without guessing its extent. No remount
            // or direct far-chapter jump can reset bookkeeping along this run.
            for (var chapter = 1; chapter <= chapterCount; chapter++) {
              expect(state.chapter, chapter);
              expect(state.page, 1);
              for (var page = 2; page <= pageCount; page++) {
                final before = shell(chapter, page - 1);
                final size = tester.getSize(before);
                final extent = mode == 'continuousTopToBottom' ? size.height : size.width;
                controller().jumpTo(controller().offset + extent);
                await frames(tester, 2);
                expect(state.chapter, chapter);
                expect(state.page, page);
                // Loading next-chapter metadata must not move this image.
                final current = shell(chapter, page);
                final position = leading(current);
                await frames(tester, 1);
                expect(leading(current), closeTo(position, 0.5));
              }
              if (chapter == 6) {
                expect(state.chapterEndReached, isFalse);
                expect(state.toNextPage(), isTrue);
                await frames(tester, 24);
                expect(state.chapter, 6);
                expect(state.page, pageCount);
                expect(state.chapterEndReached, isFalse);
                JsEngine().runCode('globalThis.readerPendingResolved = true; globalThis.resolveReaderComments({available:false});');
                await frames(tester, 20);
                expect(state.chapter, 6);
                expect(state.page, pageCount);
                expect(state.chapterEndReached, isTrue);
              }
              if (chapter < chapterCount) {
                expect(state.toNextPage(), isTrue);
                await frames(tester, 24);
              }
            }
            expect(state.chapterEndReached, isTrue);
            expect(state.toNextPage(), isFalse);
            expect(sessions.last.chapters, chapterCount);
            expect(sessions.last.indexedChapters, chapterCount);
            expect(sessions.last.entries, greaterThan(chapterCount * pageCount));
            // Reverse through the same history, exercising page indexes,
            // separators and in-flight navigation without rebuilding Reader.
            for (var chapter = chapterCount; chapter >= 1; chapter--) {
              for (var page = pageCount; page >= 1; page--) {
                expect(state.chapter, chapter);
                expect(state.page, page);
                if (chapter != 1 || page != 1) {
                  final targetChapter = page > 1 ? chapter : chapter - 1;
                  final targetPage = page > 1 ? page - 1 : pageCount;
                  expect(state.toPrevPage(), isTrue);
                  // Preparation/navigation futures may outlive two frames,
                  // especially horizontal short images. Await the exact real
                  // location, retaining all per-page and boundary assertions.
                  for (var wait = 0; wait < 40; wait++) {
                    await frames(tester, 1);
                    if (state.chapter == targetChapter &&
                        state.page == targetPage) {
                      break;
                    }
                  }
                  if (state.chapter != targetChapter || state.page != targetPage) {
                    final pos = controller().position;
                    debugPrint('READER_REVERSE_FAILURE ${jsonEncode({
                      'mode': mode, 'fromChapter': chapter, 'fromPage': page,
                      'targetChapter': targetChapter, 'targetPage': targetPage,
                      'actualChapter': state.chapter, 'actualPage': state.page,
                      'pixels': pos.pixels, 'min': pos.minScrollExtent,
                      'max': pos.maxScrollExtent,
                      'viewport': pos.viewportDimension,
                      'navigation': navigation,
                    })}');
                  }
                  expect(state.chapter, targetChapter);
                  expect(state.page, targetPage);
                }
              }
            }
            expect(state.toPrevPage(), isFalse);
            expect(probes.length, greaterThan(200));
            expect(probes, everyElement(1));
            expect(sessions.length, greaterThan(100));
            for (final work in sessions) {
              expect(work.prefetchKeys, lessThanOrEqualTo(work.prefetchLimit));
              expect(work.singleChapterPrefetchKeys,
                lessThanOrEqualTo(work.prefetchLimit));
            }
            expect(sessions.last.prefetchKeys, greaterThan(0));
            expect(tester.takeException(), isNull);
          } finally {
            debugReaderContinuousSessionWork = null;
            debugReaderContinuousIndexProbes = null;
            debugReaderContinuousNavigation = null;
            JsEngine().runCode('if (globalThis.resolveReaderComments) globalThis.resolveReaderComments({available:false});');
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester, 20);
            for (final key in keys) {
              ComicSourceManager().remove(key);
              JsEngine().runCode('delete ComicSource.sources.$key;');
              appdata.settings.resetComicReaderSettings('work@$key');
            }
            keys.clear();
            JsEngine().runCode('delete globalThis.resolveReaderComments; delete globalThis.rejectReaderComments; delete globalThis.readerCommentCalls; delete globalThis.readerPendingResolved;');
            await appdata.saveData(false);
          }
        });
      } finally {
        debugReaderContinuousSessionWork = null;
        debugReaderContinuousIndexProbes = null;
        debugReaderContinuousNavigation = null;
        debugDefaultTargetPlatformOverride = previous;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }
}
