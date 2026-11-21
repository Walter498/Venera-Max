import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_details_cache.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/home_layout.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/read_later.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/pages/favorites/shelf_page.dart';
import 'package:venera/main.dart';
import 'package:venera/pages/home_page.dart';
import 'package:venera/pages/home_source_feed.dart';
import 'package:shimmer_animation/shimmer_animation.dart';
import 'package:venera/utils/translations.dart';

import 'helpers/hud_font_fixture.dart';

const _sourceKey = 'vibe_pages_fixture';
const _cover = 'https://example.invalid/vibe-cover.png';

// Same source contract as comic_cover_refresh_test: no HTTP, no auth or parser
// substitute. The real ComicPage owns loading, actions, metadata and layout.
ComicSource _source(LoadComicFunc loader, {
  String name = 'Offline library',
  String key = _sourceKey,
  List<ExplorePageData> explorePages = const [],
}) => ComicSource(
  name, key, null, null, null, null, explorePages,
  null, null, loader, null, null, null, null, '', '', '1.0.0',
  null, null, null, null, null, null, null, null, null, null, null,
  null, false, false, null, null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String oldDataPath;
  late String oldCachePath;
  final captureKey = GlobalKey();

  setUpAll(() async {
    oldDataPath = App.dataPath;
    oldCachePath = App.cachePath;
    directory = Directory.systemTemp.createTempSync('vibe-pages-');
    App.dataPath = directory.path;
    App.cachePath = '${directory.path}/cache';
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await appdata.init();
    await AppTranslation.init();
    await JsEngine().init();
    await ComicSourceManager().init();
    await LocalManager().init();
    await HistoryManager().init();
    await LocalFavoritesManager().init();
    await ReadLaterManager().init();
    CacheManager.instance = null;
    await CacheManager().ready;
    debugDefaultTargetPlatformOverride = null;
    await loadHudTestFonts();
    if (Platform.environment['VIBE_EVIDENCE'] == '1') {
      for (final name in ['HUD_LATIN_FONT', 'HUD_CJK_FONT']) {
        final path = Platform.environment[name];
        if (path == null || !File(path).existsSync()) {
          throw StateError('Vibe screenshots require real fonts: $name');
        }
      }
    }
  });

  tearDownAll(() async {
    ComicSourceManager().remove(_sourceKey);
    ComicDetailsCache().close();
    DatabaseGateway.instance.closeManaged('${App.dataPath}/cache.db');
    CacheManager.instance = null;
    await appdata.saveData(false);
    ReadLaterManager().close();
    LocalFavoritesManager().close();
    HistoryManager().close();
    LocalManager().close();
    JsEngine().dispose();
    App.mainNavigatorKey = null;
    App.dataPath = oldDataPath;
    App.cachePath = oldCachePath;
    debugDefaultTargetPlatformOverride = null;
    directory.deleteSync(recursive: true);
  });

  setUp(() async {
    appdata.settings['language'] = 'en-US';
    appdata.settings['comicDisplayMode'] = 'detailed';
    appdata.settings['comicTileScale'] = 1.0;
    appdata.settings['shelf_folder'] = '';
    appdata.implicitData.remove('favoriteFolder');
    appdata.implicitData.remove('favoriteExpandedFolders');
    appdata.implicitData.remove('favoriteSidebarHidden');
    ComicSourceManager().remove(_sourceKey);
    await ReadLaterManager().clearAll();
    for (final item in HistoryManager().getAll()) {
      HistoryManager().remove(item.id, item.type);
    }
    final manager = LocalFavoritesManager();
    for (final folder in manager.folderNames.toList()) {
      if (manager.existsFolder(folder)) manager.deleteFolder(folder);
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  Future<void> cacheCover(WidgetTester tester, ImageProvider provider, int seed) async {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const palettes = [Color(0xff203e49), Color(0xff775044), Color(0xff44645c)];
      canvas.drawColor(palettes[seed % palettes.length], BlendMode.src);
      canvas.drawCircle(const Offset(96, 65), 42, Paint()..color = const Color(0xffe4c6a0));
      final paint = Paint()..color = const Color(0xff142d36);
      canvas.drawPath(Path()..moveTo(0, 220)..lineTo(56, 92)..lineTo(168, 220)..close(), paint);
      canvas.drawRect(const Rect.fromLTWH(18, 174, 76, 4), Paint()..color = const Color(0xffe9ddc7));
      canvas.drawRect(const Rect.fromLTWH(18, 185, 48, 3), Paint()..color = const Color(0xffe9ddc7));
      final picture = recorder.endRecording();
      final image = await picture.toImage(144, 200);
      picture.dispose();
      return image;
    });
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image!))),
    );
  }

  Future<void> pumpPage(WidgetTester tester, Widget page, {
    double width = 390, Brightness brightness = Brightness.light,
    double scale = 1, bool reduceMotion = false,
    bool settleInitialFrame = true,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    App.mainNavigatorKey = App.rootNavigatorKey;
    final dynamic themeFactory = const MyApp().createState();
    final ThemeData productionTheme = themeFactory.getTheme(
      Colors.purple, null, null, brightness,
    );
    final fontTheme = productionTheme.copyWith(
      textTheme: productionTheme.textTheme.apply(
        fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK'],
      ),
      primaryTextTheme: productionTheme.primaryTextTheme.apply(
        fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK'],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: App.rootNavigatorKey,
      theme: fontTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale), disableAnimations: reduceMotion,
          accessibleNavigation: reduceMotion,
        ),
        child: child!,
      ),
      home: RepaintBoundary(key: captureKey, child: Scaffold(body: page)),
    ));
    // A cold-load fixture inspects the actual first paint before another
    // frame replaces it with the existing local-first fallback details.
    if (!settleInitialFrame) return;
    // Deliberately bounded: real source loading and progress animations may be
    // active. pumpAndSettle would mask those states or time out indefinitely.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['VIBE_EVIDENCE'] != '1' &&
        Platform.environment['HUD_EVIDENCE'] != '1') return;
    final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/vibe-evidence/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      debugPrint('VIBE_PAGE_EVIDENCE ${file.path} ${image.width}x${image.height}');
      image.dispose();
    });
  }

  Future<void> settleWrites(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => appdata.saveData(false));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> seedHome(WidgetTester tester) async {
    appdata.settings['homeSections'] = [
      for (final section in kHomeSections)
        {'id': section.id, 'visible': ['history', 'readLater'].contains(section.id)},
    ];
    for (var i = 0; i < 3; i++) {
      final history = History.fromMap({
        'id': 'vibe-home-$i', 'type': 123,
        'title': ['The quiet atlas', 'Far from the city', 'After the rain'][i],
        'cover': 'https://example.invalid/vibe-home-$i.png',
        'time': DateTime(2026, 11, 20, 10, i).millisecondsSinceEpoch,
        'ep': 1, 'page': 12,
      });
      HistoryManager().addHistory(history);
      await cacheCover(tester, findImageProvider(history)!, i);
      if (i == 0) {
        await ReadLaterManager().addMultiple([
          ReadLaterItem(id: history.id, title: history.title, cover: history.cover,
            type: history.type, time: history.time),
        ]);
      }
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('real home compact geometry and edit round-trip ${brightness.name}', (tester) async {
      await seedHome(tester);
      await pumpPage(tester, const HomePage(), brightness: brightness);
      expect(find.byType(SimpleComicTile), findsNWidgets(4));
      final section = tester.widget<Material>(find.ancestor(
        of: find.byType(SimpleComicTile).first, matching: find.byType(Material),
      ).first);
      expect((section.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8));
      final sectionPadding = tester.widget<Padding>(find.ancestor(
        of: find.byWidget(section), matching: find.byType(Padding),
      ).first);
      expect(sectionPadding.padding, const EdgeInsets.symmetric(horizontal: 8, vertical: 6));
      expect(tester.getTopLeft(find.text('History')).dy,
        lessThan(tester.getTopLeft(find.text('Read Later')).dy));
      await capture(tester, 'home-${brightness.name}');
      await tester.tap(find.byTooltip('Edit Home'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byTooltip('Done'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(SimpleComicTile), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      await settleWrites(tester);
    });
  }

  testWidgets('real home fits 320px at 2x type and reduced motion', (tester) async {
    await seedHome(tester);
    await pumpPage(tester, const HomePage(), width: 320, scale: 2,
      brightness: Brightness.dark, reduceMotion: true);
    expect(find.byType(SimpleComicTile), findsNWidgets(4));
    expect(find.byKey(const Key('home-reading-statistics-entry')), findsOneWidget);
    await capture(tester, 'home-narrow-2x-reduced');
    await settleWrites(tester);
  });

  Widget shelfShell() {
    final observer = NaviObserver();
    final navigatorKey = GlobalKey<NavigatorState>();
    return NaviPane(
      paneItems: [
        PaneItemEntry(label: '首頁', icon: Icons.home_outlined, activeIcon: Icons.home),
        PaneItemEntry(label: '收藏', icon: Icons.favorite_border, activeIcon: Icons.favorite),
      ],
      paneActions: const [], observer: observer, navigatorKey: navigatorKey,
      initialPage: 1, pageBuilder: (_) => const ShelfPage(),
    );
  }

  testWidgets('real shelf actions remain reachable at 320px and 2x type', (tester) async {
    await pumpPage(tester, shelfShell(), width: 320, scale: 2, reduceMotion: true);
    expect(find.text('還沒有收藏，去首頁逛逛吧'), findsOneWidget);
    expect(find.byTooltip('排序'), findsOneWidget);
    expect(find.text('緩存中心'), findsOneWidget);
    await capture(tester, 'shelf-narrow-2x-reduced');
    await tester.tap(find.text('編輯'));
    await tester.pump();
    expect(find.text('完成'), findsOneWidget);
    final delete = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '取消收藏（0）'));
    expect(delete.onPressed, isNull);
    await tester.tap(find.text('完成'));
    await tester.ensureVisible(find.text('足跡'));
    await tester.tap(find.text('足跡'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('還沒有閱讀足跡'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleWrites(tester);
  });

  for (final large in [false, true]) {
    testWidgets('real favorites overview ${large ? 'narrow 2x' : 'dark'}', (tester) async {
      final manager = LocalFavoritesManager();
      manager.createFolder('Evening reads');
      manager.createFolder('A deliberately long folder title for wrapping');
      await pumpPage(tester, const FavoritesPage(),
        width: large ? 320 : 390, scale: large ? 2 : 1,
        brightness: Brightness.dark, reduceMotion: large);
      expect(find.text('Evening reads'), findsWidgets);
      await capture(tester, large ? 'favorites-narrow-2x-reduced' : 'favorites-dark');
      // Exercise the actual folder card rather than a hand-built mock tile.
      final cardLabel = find.descendant(
        of: find.byType(SmoothCustomScrollView).last,
        matching: find.text('Evening reads'),
      );
      await tester.tap(cardLabel);
      await tester.pump(const Duration(milliseconds: 300));
      expect(appdata.implicitData['favoriteFolder']['name'], 'Evening reads');
      expect(tester.takeException(), isNull);
      await settleWrites(tester);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('real source and weekday chips have 44px hits at ${scale}x', (tester) async {
      final keys = ['vibe-week-${scale}-a', 'vibe-week-${scale}-b'];
      final names = ['A long offline source label at two-times text', 'Second source'];
      final calls = [0, 0];
      final previousScope = HomeSourceScope.currentKey;
      addTearDown(() {
        for (final key in keys) { ComicSourceManager().remove(key); }
        appdata.settings['homeDisplaySources'] = <String>[];
        HomeSourceScope.currentKey = previousScope;
      });
      for (var index = 0; index < keys.length; index++) {
        final sourceIndex = index;
        final comics = [
          for (var day = 0; day < 2; day++)
            Comic('Day $day from source $sourceIndex',
              'https://example.invalid/week-$sourceIndex-$day.png',
              'week-$sourceIndex-$day', null, const [], '',
              keys[sourceIndex], null, null),
        ];
        final parts = [
          ExplorePagePart('周一', [comics[0]], null),
          ExplorePagePart('周二', [comics[1]], null),
        ];
        ComicSourceManager().add(_source(
          (_) async => const Res.error('Unused detail fixture'),
          key: keys[index], name: names[index],
          explorePages: [ExplorePageData(
            'Home', ExplorePageType.singlePageWithMultiPart, null, null,
            () async { calls[sourceIndex]++; return Res(parts); }, null,
          )],
        ));
        for (var day = 0; day < comics.length; day++) {
          await cacheCover(tester, findImageProvider(comics[day])!, day);
        }
      }
      appdata.settings['homeDisplaySources'] = keys;
      appdata.settings['homeSections'] = [
        for (final section in kHomeSections)
          {'id': section.id, 'visible': section.id == 'sourceHome'},
      ];
      await pumpPage(tester, const HomePage(), width: 320, scale: scale,
        reduceMotion: true, brightness: Brightness.dark);
      expect(find.byType(HomeSourceFeed), findsOneWidget);
      Finder chip(String label) => find.byWidgetPredicate(
        (widget) => widget is VeneraChip && widget.label == label,
      );
      void checkHit(String label) {
        final target = find.descendant(of: chip(label), matching: find.byType(VeneraPressable));
        final size = tester.getSize(target);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        final textHeight = tester.getSize(find.text(label)).height;
        expect(textHeight + 12, lessThanOrEqualTo(size.height + 1), reason: 'Scaled label must fit inside $label');
      }
      checkHit(names[0]);
      checkHit('周一');
      checkHit('周二');
      expect(calls, [1, 0]);
      expect(tester.widget<VeneraChip>(chip('周一')).selected, isTrue);
      final tuesday = find.descendant(of: chip('周二'), matching: find.byType(VeneraPressable));
      final tuesdayRect = tester.getRect(tuesday);
      // Touch the bottom of the actual hit region, not just the text center.
      await tester.tapAt(Offset(tuesdayRect.left + 16, tuesdayRect.bottom - 2));
      await tester.pump();
      expect(tester.widget<VeneraChip>(chip('周二')).selected, isTrue);
      expect(calls, [1, 0]); // weekday selection never fetches the source again
      await capture(tester, 'home-source-week-${scale}x');
      await tester.ensureVisible(chip(names[1]));
      await tester.tap(chip(names[1]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, [1, 1]);
      expect(HomeSourceScope.currentKey, keys[1]);
      checkHit(names[1]);
      expect(tester.widget<VeneraChip>(chip(names[1])).selected, isTrue);
      expect(tester.takeException(), isNull);
      await settleWrites(tester);
    });
  }

  testWidgets('real cold detail uses static loading semantics then one response', (tester) async {
    const id = 'vibe-cold-no-cache';
    expect(ComicDetailsCache().find(_sourceKey, id), isNull);
    final response = Completer<Res<ComicDetails>>();
    var requests = 0;
    ComicSourceManager().add(_source((requestedId) {
      expect(requestedId, id);
      requests++;
      return response.future;
    }));
    await cacheCover(tester, comicDetailCoverProvider(
      sourceKey: _sourceKey, id: id, cover: _cover, localComic: null,
    ), 0);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await pumpPage(tester, const ComicPage(
      id: id, sourceKey: _sourceKey, cover: _cover,
      title: 'Opening the atlas', heroID: 'cold-atlas',
    ), width: 320, scale: 2, reduceMotion: true, settleInitialFrame: false);
    expect(requests, 1);
    expect(response.isCompleted, isFalse);
    final status = find.byKey(const ValueKey('comic-details-loading-status'));
    expect(status, findsOneWidget);
    expect(find.byType(Shimmer), findsNothing);
    final indicator = tester.widget<CircularProgressIndicator>(find.descendant(
      of: status, matching: find.byType(CircularProgressIndicator),
    ));
    expect(indicator.value, .72); // fixed arc, no repeating controller
    final statusData = tester.getSemantics(status).getSemanticsData();
    expect(statusData.label, 'Loading'.tl);
    expect(statusData.value, isEmpty); // never claim a measured 72%
    expect(tester.takeException(), isNull);
    await capture(tester, 'detail-cold-loading-narrow-2x-reduced');

    // The production loader is local-first: an uncached page advances from
    // its first-paint skeleton to fallback details while this request is still
    // pending. Do not change that flow merely to prolong a screenshot state.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(requests, 1);
    expect(response.isCompleted, isFalse);
    response.complete(Res(ComicDetails.fromJson({
      'comicId': id, 'sourceKey': _sourceKey,
      'title': 'The atlas has arrived', 'subtitle': 'Loaded without a cache',
      'cover': _cover, 'tags': <String, List<String>>{},
      'chapters': <String, String>{'1': 'Arrival'},
    })));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Loaded without a cache'), findsOneWidget);
    expect(find.byKey(const ValueKey('comic-details-loading-status')), findsNothing);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
    await capture(tester, 'detail-cold-loaded-narrow-2x-reduced');
    await settleWrites(tester);
  });

  for (final variant in ['light', 'narrow-2x-reduced', 'wide-dark']) {
    testWidgets('real detail header, metadata and Hero $variant', (tester) async {
      final response = Completer<Res<ComicDetails>>();
      var requests = 0;
      ComicSourceManager().add(_source((id) {
        requests++;
        expect(id, 'vibe-detail');
        return response.future;
      }));
      await cacheCover(tester, comicDetailCoverProvider(
        sourceKey: _sourceKey, id: 'vibe-detail', cover: _cover, localComic: null,
      ), 0);
      final details = ComicDetails.fromJson({
        'comicId': 'vibe-detail', 'sourceKey': _sourceKey,
        'title': 'The quiet atlas', 'subtitle': 'A journey in three parts',
        'cover': _cover,
        'description': 'An illustrated journey through quiet places and familiar streets.',
        'tags': <String, List<String>>{'author': ['M. Chen'], 'genre': ['Adventure', 'Slice of life']},
        'chapters': <String, String>{'1': 'First light', '2': 'The long way home', '3': 'After the rain'},
      });
      // A real cached detail page, not a reproduction of its header. The pending
      // source refresh must keep its cached content and issue exactly one call.
      ComicDetailsCache().update(_sourceKey, 'vibe-detail', details);
      await pumpPage(tester, const ComicPage(
        id: 'vibe-detail', sourceKey: _sourceKey, cover: _cover,
        title: 'The quiet atlas', heroID: 'vibe-detail-hero',
      ), width: variant.startsWith('wide') ? 900 : variant.startsWith('narrow') ? 320 : 390,
        scale: variant.startsWith('narrow') ? 2 : 1,
        brightness: variant == 'light' ? Brightness.light : Brightness.dark,
        reduceMotion: variant.contains('reduced'));
      expect(requests, 1);
      final hero = find.byWidgetPredicate((widget) => widget is Hero && widget.tag == 'covervibe-detail-hero');
      expect(hero, findsOneWidget);
      expect(tester.getSize(hero).width, variant.startsWith('wide') ? 162 : 96);
      expect(find.text('A journey in three parts'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Read'), findsOneWidget);
      await capture(tester, 'detail-$variant');
      if (variant.contains('reduced')) {
        final dynamic pageState = tester.state(find.byType(ComicPage));
        final ScrollController controller = pageState.scrollController;
        expect(controller.position.maxScrollExtent, greaterThan(0));
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        // This invokes the real onPressed handler: animateTo(Duration.zero)
        // would assert here; reduced motion must take the jumpTo branch.
        expect(controller.offset, 0);
        expect(tester.takeException(), isNull);
      }
      response.complete(Res(details));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      // Browsing preferences must survive page entry and refresh untouched.
      expect(appdata.settings['comicDisplayMode'], 'detailed');
      expect(appdata.settings['comicTileScale'], 1.0);
      await settleWrites(tester);
    });
  }
}
