import 'dart:async';
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
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

// Regression coverage for issue #259: a chapter-comment request that never
// resolves (or fails) must not pin the reader to the last page.
//
// These tests mount the real Reader/PhotoView widget tree against a real
// ComicSource implemented in Dart, with a comment loader whose futures the test
// controls. Navigation is driven through the same public API the tap/volume
// fallback uses: `toNextPage()`, and `toNextChapter()` when that returns false.
// No copied geometry helper decides the outcome; the mounted reader does.
void main() {
  setUpCommentsTestHost();
  late Directory directory;
  late String oldPath;
  late String imageUrl;
  late ui.Image testImage;
  var serial = 0;
  final keys = <String>[];

  const memoryChannel = MethodChannel('flutter_memory_info');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(memoryChannel, (call) async {
      if (call.method == 'getFreePhysicalMemorySize') return 512 * 1024 * 1024;
      throw MissingPluginException(
          'Unexpected Reader memory method: ${call.method}');
    });
    oldPath = App.dataPath;
    directory = Directory.systemTemp.createTempSync('reader_nav_comments_');
    App.dataPath = directory.path;

    Future<void> stage(String name, Future<void> Function() action) async {
      debugPrint('READER_NAV_PENDING start $name');
      await action().timeout(const Duration(seconds: 30));
      debugPrint('READER_NAV_PENDING done $name');
    }

    await stage('appdata.init', appdata.init);
    await stage('js.init', JsEngine().init);
    await stage('sources.init', ComicSourceManager().init);
    await stage('history.init', HistoryManager().init);
    await stage('readLater.init', ReadLaterManager().init);
    await stage('favorites.init', LocalFavoritesManager().init);
    await stage('favorites.backgroundRead',
        () => DatabaseGateway.instance.runExclusive(() async {}));
    final library = Directory('${directory.path}/library')..createSync();
    File('${directory.path}/local_path').writeAsStringSync(library.path);
    await stage('local.init', LocalManager().init);

    final image = await createTestImage(width: 390, height: 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${directory.path}/page.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
    imageUrl = file.uri.toString();
    // Kept for the synchronous image-cache entries in the reader widget; the
    // encoded file above is what the production image pipeline reads.
    testImage = image;
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
        JsEngine().dispose();
      }
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(memoryChannel, null);
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

  /// A source plus the completers handed to its chapter-comment loader.
  ({ComicSource source, Map<String, List<Completer<Res<List<Comment>>>>> loads})
      source() {
    final key = 'reader_nav_${serial++}';
    keys.add(key);
    final loads = <String, List<Completer<Res<List<Comment>>>>>{};
    final result = ComicSource(
      'Reader navigation fixture',
      key,
      null,
      null,
      null,
      null,
      const [],
      null,
      null,
      null,
      null,
      (id, ep) async => Res([imageUrl, imageUrl, imageUrl]),
      null,
      null,
      '',
      '',
      '1.0',
      null,
      null,
      (comicId, epId, page, replyTo) {
        final completer = Completer<Res<List<Comment>>>();
        (loads[epId] ??= []).add(completer);
        return completer.future;
      },
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      false,
      false,
      null,
      null,
    );
    expect(ComicSourceManager().add(result), isTrue);
    for (final ep in ['one', 'two']) {
      for (var page = 1; page <= 3; page++) {
        final provider = ReaderImageProvider(imageUrl, key, 'work', ep, page,
            enableResize: true);
        PaintingBinding.instance.imageCache.putIfAbsent(
            provider,
            () => OneFrameImageStreamCompleter(
                SynchronousFuture(ImageInfo(image: testImage.clone()))));
      }
    }
    return (source: result, loads: loads);
  }

  Future<dynamic> mount(WidgetTester tester, ComicSource source, String mode,
      {bool seamless = false}) async {
    appdata.settings.setEnabledComicSpecificSettings('work', source.key, true);
    for (final entry in <String, dynamic>{
      'readerMode': mode,
      'showChapterComments': true,
      'showChapterCommentsAtEnd': true,
      'enableContinuousChapterReading': seamless,
      'enablePageAnimation': false,
      'readerScreenPicNumberForPortrait': 1,
      'readerScreenPicNumberForLandscape': 1,
      'showSingleImageOnFirstPage': false,
      'enableTurnPageByVolumeKey': false,
      'autoPageTurningInterval': 60,
      'autoScrollSpeed': 60,
    }.entries) {
      appdata.settings.setReaderSetting(
          'work', source.key, entry.key, entry.value);
    }
    final type = ComicType.fromKey(source.key);
    final history = History.fromMap({
      'id': 'work',
      'type': type.value,
      'title': 'work',
      'cover': '',
      'time': DateTime.now().millisecondsSinceEpoch,
      'ep': 1,
      'page': 1,
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Reader(
          type: type,
          cid: 'work',
          name: 'Work',
          author: '',
          tags: const [],
          chapters: const ComicChapters(
              {'one': 'First chapter', 'two': 'Second chapter'}),
          history: history,
        ),
      ),
    ));
    await frames(tester, 40);
    final dynamic state = tester.state(find.byType(Reader));
    expect(state.isLoading, false);
    return state;
  }

  /// The same fallback chain used by taps, volume keys and the mouse wheel:
  /// try the in-chapter turn first, then chapter navigation.
  Future<bool> turnForward(WidgetTester tester, dynamic state,
      {int maxTurns = 10}) async {
    for (var i = 0; i < maxTurns; i++) {
      if (state.chapter as int > 1) return true;
      final turned = state.toNextPage() as bool;
      if (!turned) state.toNextChapter();
      await frames(tester, 30);
    }
    return state.chapter as int > 1;
  }

  void readerTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.runAsync(() async {
          try {
            await body(tester);
          } finally {
            await frames(tester, 10);
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester, 20);
            for (final key in keys) {
              ComicSourceManager().remove(key);
              appdata.settings.resetComicReaderSettings('work@$key');
            }
            keys.clear();
            await appdata.saveData(false);
          }
        });
      } finally {
        debugDefaultTargetPlatformOverride = previous;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  }

  readerTest('gallery pending comments still turns to the next chapter',
      (tester) async {
    final fixture = source();
    final dynamic state = await mount(tester, fixture.source, 'galleryLeftToRight');

    // The comments page exists (pending counts as available) and its footer is
    // still loading, so the chapter is not "read complete" yet.
    expect(state.totalPages, 4);
    state.toPage(4);
    await frames(tester, 30);
    expect(state.isOnChapterCommentsPage, true);
    expect(state.chapterEndReached, false);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // A real forward turn at the loaded-but-unresolved footer.
    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);

    // The old chapter's request arriving late must not drag the reader back.
    fixture.loads['one']!.last.complete(Res([commentFixture('old-late')],
        subData: 1));
    await frames(tester, 40);
    expect(state.chapter, 2);
    expect(state.page, 1);
    final newChapterCalls = fixture.loads['two'];
    if (newChapterCalls != null && newChapterCalls.isNotEmpty) {
      newChapterCalls.last.completeError(StateError('late chapter two failure'));
      await frames(tester, 40);
      expect(state.chapter, 2);
      expect(state.page, 1);
    }
    expect(tester.takeException(), isNull);
  });

  readerTest('gallery failed comments show retry yet still turn',
      (tester) async {
    final fixture = source();
    final dynamic state = await mount(tester, fixture.source, 'galleryLeftToRight');
    fixture.loads['one']!.last.completeError(StateError('fixture network failure'));
    await frames(tester, 40);

    state.toPage(4);
    await frames(tester, 30);
    expect(state.isOnChapterCommentsPage, true);
    expect(state.chapterEndReached, false);
    // The footer still offers its real retry affordance.
    expect(find.text('重试'), findsOneWidget);

    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);
    // The old chapter's feed stays errored; the new chapter's own footer is
    // independent and must not be replaced by the previous failure.
    await frames(tester, 40);
    expect(state.chapter, 2);
    expect(state.page, 1);
    expect(tester.takeException(), isNull);
  });

  readerTest('gallery confirmed-empty comments remove the page and still turn',
      (tester) async {
    final fixture = source();
    final dynamic state = await mount(tester, fixture.source, 'galleryLeftToRight');
    fixture.loads['one']!.last.complete(Res(const <Comment>[], subData: 1));
    await frames(tester, 40);

    // No comments page is fabricated for a confirmed empty feed.
    expect(state.totalPages, 3);
    expect(state.page, lessThanOrEqualTo(3));

    state.toPage(3);
    await frames(tester, 30);
    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);
    expect(tester.takeException(), isNull);
  });

  readerTest('continuous pending comments still turn; late replies do not move',
      (tester) async {
    final fixture = source();
    final dynamic state =
        await mount(tester, fixture.source, 'continuousTopToBottom');
    state.toPage(3);
    await frames(tester, 40);
    expect(state.page, 3);
    expect(state.chapterEndReached, false);

    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);

    // Late resolution of the chapter that was left behind.
    fixture.loads['one']!.last.complete(Res([commentFixture('one-late')],
        subData: 1));
    await frames(tester, 40);
    expect(state.chapter, 2);
    expect(state.page, 1);

    // Late failure of the chapter now being read.
    final two = fixture.loads['two'];
    if (two != null && two.isNotEmpty) {
      two.last.completeError(StateError('chapter two late failure'));
      await frames(tester, 40);
      expect(state.chapter, 2);
      expect(state.page, 1);
    }
    expect(tester.takeException(), isNull);
  });

  readerTest('continuous confirmed-empty comments still turn', (tester) async {
    final fixture = source();
    final dynamic state =
        await mount(tester, fixture.source, 'continuousTopToBottom');
    fixture.loads['one']!.last.complete(Res(const <Comment>[], subData: 1));
    await frames(tester, 40);
    state.toPage(3);
    await frames(tester, 40);
    expect(state.chapter, 1);
    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);
    expect(tester.takeException(), isNull);
  });

  readerTest('continuous failed comments still turn', (tester) async {
    final fixture = source();
    final dynamic state =
        await mount(tester, fixture.source, 'continuousTopToBottom');
    fixture.loads['one']!.last.completeError(StateError('fixture network failure'));
    await frames(tester, 40);
    state.toPage(3);
    await frames(tester, 40);
    expect(state.chapter, 1);
    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);
    expect(tester.takeException(), isNull);
  });

  readerTest('seamless continuous pending comments still turn', (tester) async {
    final fixture = source();
    final dynamic state = await mount(
        tester, fixture.source, 'continuousTopToBottom',
        seamless: true);
    state.toPage(3);
    await frames(tester, 60);
    expect(state.chapter, 1);
    expect(state.chapterEndReached, false);

    expect(await turnForward(tester, state), isTrue);
    expect(state.chapter, 2);
    expect(state.page, 1);

    fixture.loads['one']!.last.complete(Res([commentFixture('one-late')],
        subData: 1));
    await frames(tester, 40);
    expect(state.chapter, 2);
    expect(tester.takeException(), isNull);
  });
}
