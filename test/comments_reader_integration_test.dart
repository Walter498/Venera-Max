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

// Real domain/source/history/QuickJS + Reader/PhotoView mount. Image bytes are
// local fixture files, never HTTP. Dynamic access calls the actual mounted
// State's public navigation API, not a copied geometry/helper implementation.
void main() {
  setUpCommentsTestHost();
  late Directory directory;
  late String oldPath;
  var serial = 0;
  final keys = <String>[];
  late String imageUrl;

  const memoryChannel = MethodChannel('flutter_memory_info');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(memoryChannel,(call) async {
        if(call.method=='getFreePhysicalMemorySize') return 512 * 1024 * 1024;
        throw MissingPluginException('Unexpected Reader memory method: ${call.method}');
      });
    oldPath = App.dataPath;
    directory = Directory.systemTemp.createTempSync('comments_reader_');
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
    final image = await createTestImage(width: mode == 'continuousTopToBottom' ? 390 : 844,
      height: mode == 'continuousTopToBottom' ? 844 : 390);
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
      return {images: [${jsonEncode(imageUrl)}, ${jsonEncode(imageUrl)}, ${jsonEncode(imageUrl)}]};
    },
    chapterCommentCapabilities: {canLoadReplies: true},
    async loadChapterComments(id, ep, page, reply) {
      if (reply != null) return {comments: [{id:"reply",userName:"reply",content:"actual reply"}],maxPage:1};
      if (ep === "two") return {available:false};
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
    for(final ep in ['one','two']) {
      final provider = ReaderImageProvider(imageUrl,key,'work',ep,1,
        enableResize:mode.startsWith('continuous'));
      PaintingBinding.instance.imageCache.putIfAbsent(provider,() =>
        OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image:image.clone()))));
    }
    image.dispose();
    return parsed;
  }

  Future<dynamic> mount(WidgetTester tester, ComicSource s, String mode,
      {bool seamless = false, bool large = false}) async {
    appdata.settings.setEnabledComicSpecificSettings('work', s.key, true);
    for (final entry in <String,dynamic>{
      'readerMode':mode, 'showChapterComments':true, 'showChapterCommentsAtEnd':true,
      'enableContinuousChapterReading':seamless, 'enablePageAnimation':false,
      'readerScreenPicNumberForPortrait':1, 'readerScreenPicNumberForLandscape':1,
      'showSingleImageOnFirstPage':false, 'enableTurnPageByVolumeKey':false,
      'autoPageTurningInterval':1, 'autoScrollSpeed':10000,
    }.entries) {
      appdata.settings.setReaderSetting('work',s.key,entry.key,entry.value);
    }
    final type = ComicType.fromKey(s.key);
    final history = History.fromMap({'id':'work','type':type.value,'title':'work',
      'cover':'','time':DateTime.now().millisecondsSinceEpoch,'ep':1,'page':1});
    await tester.pumpWidget(MaterialApp(home:MediaQuery(
      data:MediaQueryData(size:large ? const Size(844,390) : const Size(390,844),
        textScaler:TextScaler.linear(large ? 2 : 1)),
      child:Reader(type:type,cid:'work',name:'Work',author:'',tags:const [],
        chapters:const ComicChapters({'one':'First chapter','two':'Second chapter'}),history:history))));
    await frames(tester,40);
    final dynamic state = tester.state(find.byType(Reader));
    expect(state.isLoading,false);
    expect(JsEngine().runCode('globalThis.readerCommentCalls'),1);
    if (mode.startsWith('continuous')) {
      final rendered = find.descendant(of: find.byType(Reader),
          matching: find.byType(RawImage));
      debugPrint('COMMENTS_READER_GEOMETRY $mode viewport=${state.size} '
          'page=${state.page} images=${state.images?.length} '
          'rendered=${rendered.evaluate().map((e) {
            final image = (e.widget as RawImage).image;
            final box = e.findRenderObject() as RenderBox;
            return '${image?.width}x${image?.height}@${box.size}'
                ':${box.localToGlobal(Offset.zero)}';
          }).join(";")}');
    }
    return state;
  }

  void resolve(String result) => JsEngine().runCode('globalThis.resolveReaderComments($result);');
  String repeated(String value, int count) => List.filled(count, value).join();
  String nonempty() => jsonEncode({'comments':[
    for(var i=0;i<4;i++) {'id':'topic-$i','userName':repeated('非常长的昵称 ',30),
      'content':repeated('真实正文预览 ',90),'time':repeated('2026年10月14日 非常长日期 ',12),
      'score':12,'replyCount':2,'replyPreview':{'id':'r-$i','content':repeated('真实回复预览 ',50)}}
  ],'maxPage':3});

  void readerTest(String name, Future<void> Function(WidgetTester) body,
      {bool large = false}) {
    testWidgets(name,(tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = large ? const Size(844,390) : const Size(390,844);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.runAsync(() async {
          try { await body(tester); }
          finally {
            // Even an assertion failure must release retained native Promise
            // references before strict QuickJS disposal; don't hide its errors.
            JsEngine().runCode('if (globalThis.resolveReaderComments) globalThis.resolveReaderComments({available:false});');
            await frames(tester,10);
            await tester.pumpWidget(const SizedBox.shrink());
            await frames(tester,20);
            for(final key in keys) {
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
        debugDefaultTargetPlatformOverride = previous;
        tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
      }
    });
  }

  for(final mode in ['galleryLeftToRight','galleryRightToLeft','galleryTopToBottom',
    'continuousTopToBottom']) {
    for(final result in ['nonempty','empty','unavailable','error']) {
      readerTest('$mode mounted Reader pending key/auto -> $result',(tester) async {
        final s = await source(tester,mode);
        final dynamic state = await mount(tester,s,mode);
        // Real keyboard input, then the mounted controller's normal navigation.
        await tester.sendKeyEvent(mode=='galleryRightToLeft' ? LogicalKeyboardKey.arrowLeft
          : mode=='galleryLeftToRight' ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowDown);
        await frames(tester);
        if (mode == 'continuousTopToBottom') {
          // Continuous arrow keys scroll a quarter viewport, not one image.
          // Verify the real key kept us in this chapter, then exercise the
          // explicit image-page API separately with the original exact check.
          expect(state.chapter, 1);
          expect(state.page, inInclusiveRange(1, 3));
          state.toPage(2);
          await frames(tester, 20);
        }
        expect(state.page,2);
        for(var i=0;i<8;i++) { state.toNextPage(); await frames(tester,4); }
        // The forward-drag-on-a-pending-footer case is its own test below:
        // pending comments now allow the chapter turn, so asserting the old
        // "drag stays on chapter 1" here would pin the very behaviour #259
        // removes. Auto-reading still waits for a settled chapter.
        state.autoPageTurning('work',ComicType.fromKey(s.key));
        await frames(tester,160);
        expect(state.chapter,1);
        expect(state.chapterEndReached,false);
        expect(state.history.page,lessThan(state.history.maxPage));
        state.stopAutoReading();
        if(result=='error') {
          JsEngine().runCode('globalThis.rejectReaderComments(new Error("fixture network failure"));');
          await frames(tester);
          expect(state.chapter,1); expect(state.chapterEndReached,false);
          final retry = find.text('重试');
          expect(retry,findsOneWidget);
          await tester.ensureVisible(retry); await tester.tap(retry);
          await frames(tester);
          expect(JsEngine().runCode('globalThis.readerCommentCalls'),2);
          resolve(nonempty());
        } else {
          resolve(result=='nonempty' ? nonempty() : result=='empty'
            ? '{comments:[],maxPage:1}' : '{available:false}');
        }
        await frames(tester,40);
        expect(state.chapter,1);
        if(result=='nonempty' || result=='error') {
          expect(state.chapterEndReached,false);
          // Whole parent footer must be consumed; no internal feed scroll.
          for(var i=0;i<30 && !state.chapterEndReached;i++) {
            state.toNextPage(); await frames(tester,15);
          }
        }
        expect(state.chapterEndReached,true);
        expect(state.history.maxPage,3);
        expect(state.history.page,3);
        state.autoPageTurning('work',ComicType.fromKey(s.key));
        await frames(tester,160);
        expect(state.chapter,2);
        state.stopAutoReading();
        expect(tester.takeException(),isNull);
      });
    }
  }

  // Forward gestures on a still-pending footer must leave the chapter instead
  // of pinning the reader (issue #259). This is the drag counterpart of the
  // mounted-Reader pending key/auto coverage above.
  for(final mode in ['galleryLeftToRight','galleryRightToLeft','galleryTopToBottom']) {
    readerTest('$mode pending footer forward drag opens the next chapter',
      (tester) async {
        final s=await source(tester,mode);
        final dynamic state=await mount(tester,s,mode);
        state.toPage(state.totalPages);
        await frames(tester,40);
        expect(state.chapter,1);
        expect(state.isOnChapterCommentsPage,isTrue);
        expect(state.chapterEndReached,isFalse);
        await tester.drag(find.byType(Reader),mode=='galleryTopToBottom'
          ? const Offset(0,-844) : Offset(mode=='galleryRightToLeft' ? 390 : -390,0));
        await frames(tester,60);
        expect(state.chapter,2);
        expect(state.page,1);
        // A late reply for the chapter that was left must not drag it back.
        resolve(nonempty());
        await frames(tester,40);
        expect(state.chapter,2);
        expect(state.page,1);
        expect(tester.takeException(),isNull);
      });
  }

  for(final mode in ['continuousLeftToRight','continuousRightToLeft']) {
    readerTest('$mode 200 percent short mounted Reader preview actions and footer tail',
      (tester) async {
        final s=await source(tester,mode);
        final dynamic state=await mount(tester,s,mode,large:true);
        resolve(nonempty()); await frames(tester,30);
        // Physical drag along the chapter's reading direction, exercising the
        // mounted PhotoView -> scroll resolver rather than a Rect helper.
        // dragFrom with zero slop emits only ONE move: it wins the arena
        // but DragStartBehavior.start has no subsequent update to scroll.
        // Default slop emits the recognition move followed by the actual move;
        // 870 minus18 leaves852px, just beyond this real844px image.
        final scroll = tester.widget<CustomScrollView>(find.descendant(
          of: find.byType(Reader), matching: find.byType(CustomScrollView)));
        final beforeDrag = scroll.controller!.offset;
        await tester.drag(find.byType(Reader),
          Offset(mode.endsWith('RightToLeft') ? 870 : -870, 0));
        await frames(tester,30);
        debugPrint('COMMENTS_READER_DRAG $mode '
            'before=$beforeDrag after=${scroll.controller!.offset} page=${state.page}');
        expect(scroll.controller!.offset, greaterThan(beforeDrag));
        expect(state.page,2);
        await tester.sendKeyEvent(mode.endsWith('RightToLeft')
          ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight);
        await frames(tester,30);
        // Continuous keys scroll 1/4 viewport; they do not target the next
        // image. Preserve actual key input and verify exact image navigation
        // through the mounted Reader API rather than assuming gallery keys.
        expect(state.chapter, 1);
        expect(state.chapterEndReached, false);
        state.toPage(3);
        await frames(tester, 30);
        expect(state.page,3); expect(state.chapterEndReached,false);
        state.toNextPage(); await frames(tester,30);
        expect(state.chapter,1); expect(state.chapterEndReached,false);
        // Advance through identity/body/reply panels in the same horizontal
        // chapter scroll. Verify a real reply button is hit-testable and routes
        // to its real parent id (JS reply loader is used on the destination).
        Finder reply=find.byIcon(Icons.chat_bubble_outline).hitTestable();
        for(var i=0;i<14 && reply.evaluate().isEmpty;i++) {
          state.toNextPage(); await frames(tester,20);
          reply=find.byIcon(Icons.chat_bubble_outline).hitTestable();
        }
        expect(reply,findsWidgets);
        expect(tester.takeException(),isNull);
        await tester.tap(reply.first); await frames(tester,40);
        expect(find.text('评论详情'),findsOneWidget);
        Navigator.of(tester.element(find.text('评论详情'))).pop();
        await frames(tester,40);
        // Full text now spans as many panels as it needs at 200% scaling;
        // four long comments can legitimately exceed the old 30-turn budget.
        // Derive a finite budget from the actual laid-out footer and require
        // every page turn to make progress, so a navigation stall still fails.
        final position = scroll.controller!.position;
        final footerWidth = tester.getSize(find.byKey(
          const ValueKey('chapter-comments-region'))).width;
        final maxTurns = (footerWidth / position.viewportDimension).ceil() + 2;
        for(var i=0;i<maxTurns && !state.chapterEndReached;i++) {
          final before = position.pixels;
          state.toNextPage(); await frames(tester,20);
          expect(position.pixels, greaterThan(before),
            reason: 'footer turn $i of $maxTurns must advance toward its tail');
          expect(state.chapter,1);
        }
        expect(state.chapterEndReached,true);
        expect(position.pixels, closeTo(position.maxScrollExtent,1));
        expect(state.chapter,1);
        state.toNextChapter(); await frames(tester,40);
        expect(state.chapter,2);
        expect(tester.takeException(),isNull);
      },large:true);
  }

  readerTest('RTL seamless pending boundary waits then consumes expanded footer before cross chapter',
    (tester) async {
      final s=await source(tester,'continuousRightToLeft');
      final dynamic state=await mount(tester,s,'continuousRightToLeft',seamless:true);
      for(var i=0;i<12;i++) { state.toNextPage(); await frames(tester,15); }
      expect(state.chapter,1); expect(state.page,3);
      expect(state.chapterEndReached,false);
      // Try an actual overshooting pointer drag in the already-preloaded window.
      await tester.drag(find.byType(Reader),const Offset(2400,0));
      await frames(tester,30);
      expect(state.chapter,1);
      resolve(nonempty()); await frames(tester,40);
      expect(state.chapterEndReached,false);
      for(var i=0;i<40 && state.chapter==1;i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await frames(tester,20);
      }
      expect(state.chapter,2);
      expect(tester.takeException(),isNull);
    });
}
