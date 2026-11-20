import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/read_later.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/pages/reader/reader.dart';
import 'package:venera/pages/reader/reader_chrome.dart';
import 'package:venera/pages/reader/reader_hud.dart';

import 'package:venera/main.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/utils/io.dart' show overrideIO;
import 'helpers/hud_font_fixture.dart' show loadHudTestFonts;

// Mount the production Reader, LocalManager, image decoder and reader scaffold.
// There is no test-only HUD/scaffold or fake Reader state. Only device plugins
// are mocked; all library/database/image files live in our own temporary root.
//
// Run on macOS (same host as the other real Reader tests):
//   flutter test test/reader_hud_integration_test.dart
// Other hosts must supply HUD_CJK_FONT and HUD_LATIN_FONT. The shared FontLoader
// host rejects missing fonts instead of exporting Ahem/tofu evidence. Set
// HUD_EVIDENCE=1 to write build/reader-hud-evidence/real-reader-*.png.
const _comicId = 'reader-hud-local-fixture';
const _chapters = ComicChapters({'one': '第十二话雨后', 'two': '第十三话重逢'});
const _captureKey = ValueKey('real-reader-hud-capture');
const _batteryChannel = MethodChannel('dev.fluttercommunity.plus/battery');
const _memoryChannel = MethodChannel('flutter_memory_info');
final _clockPattern = RegExp(r'^\d{2}:\d{2}$');

Finder _hud() => find.descendant(
  of: find.byType(Reader), matching: find.byType(ReaderHudText));

List<RenderParagraph> _paragraphs(WidgetTester tester, Finder root) =>
    tester.renderObjectList<RenderParagraph>(find.descendant(
      of: root, matching: find.byType(RichText))).toList();

String _hudValue(WidgetTester tester, Finder hud) {
  final values = _paragraphs(tester, hud)
      .map((p) => p.text.toPlainText()).toSet();
  expect(values, hasLength(1), reason: 'Fill and outline must show identical text');
  return values.single;
}

Finder _hudWithValue(WidgetTester tester, String value) => find.byWidgetPredicate(
  (widget) => widget is ReaderHudText && _hud().evaluate().any((element) =>
    identical(element.widget, widget) &&
    _hudValue(tester, find.byWidget(widget)) == value));

void _expectTwoAlignedPasses(WidgetTester tester, Finder hud) {
  final paragraphs = _paragraphs(tester, hud);
  expect(paragraphs, hasLength(2),
      reason: 'Exactly one fill and one stroke, not duplicate filled glyphs');
  final styles = paragraphs.map((p) => p.text.style!).toList();
  expect(styles.where((s) => s.foreground?.style == PaintingStyle.stroke),
      hasLength(1));
  expect(styles.where((s) => (s.foreground?.style ?? PaintingStyle.fill) ==
      PaintingStyle.fill), hasLength(1));
  final stroke = styles.singleWhere(
      (s) => s.foreground?.style == PaintingStyle.stroke).foreground!;
  expect(stroke.strokeWidth, closeTo(1.4, 1e-6));
  final scheme = Theme.of(tester.element(hud)).colorScheme;
  expect(stroke.color.toARGB32(), scheme.onInverseSurface.toARGB32());
  final fill = styles.singleWhere(
      (s) => (s.foreground?.style ?? PaintingStyle.fill) == PaintingStyle.fill);
  expect((fill.foreground?.color ?? fill.color)!.toARGB32(), scheme.onSurface.toARGB32());
  for (final style in styles) {
    expect(style.fontSize, 14);
    expect(style.shadows ?? const <Shadow>[], isEmpty,
        reason: 'Text is outlined; the old eight shadows belong only to Icon');
  }
  final a = styles[0];
  final b = styles[1];
  // The build276 defect was a 14sp outline under an inherited, larger fill.
  // Check the resolved rendering styles, not source text or widget spelling.
  expect([a.fontFamily, a.fontFamilyFallback, a.fontWeight, a.fontStyle,
    a.height, a.letterSpacing, a.wordSpacing, a.textBaseline],
    [b.fontFamily, b.fontFamilyFallback, b.fontWeight, b.fontStyle,
      b.height, b.letterSpacing, b.wordSpacing, b.textBaseline]);
  expect(paragraphs[0].size, paragraphs[1].size);
  expect(paragraphs[0].localToGlobal(Offset.zero),
      paragraphs[1].localToGlobal(Offset.zero));
  expect(paragraphs[0].text.toPlainText(), paragraphs[1].text.toPlainText());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late String oldDataPath;
  late String oldCachePath;
  late LocalComic comic;
  var batteryLevel = 100;
  var batteryState = 'full';
  final batteryCalls = <String>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final oldIO = IOOverrides.current;
  final oldPlatform = debugDefaultTargetPlatformOverride;
  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // main() installs this exact production adapter for file:// paths.
    IOOverrides.global = overrideIO(() => IOOverrides.current);
    await AppTranslation.init();
    await loadHudTestFonts(); // real CJK, Latin and MaterialIcons fonts
    oldDataPath = App.dataPath;
    oldCachePath = App.cachePath;
    temporary = Directory.systemTemp.createTempSync('reader-hud-integration-');
    App.dataPath = temporary.path;
    App.cachePath = '${temporary.path}/cache';
    Directory(App.cachePath).createSync(recursive: true);
    messenger.setMockMethodCallHandler(_memoryChannel, (call) async {
      if (call.method == 'getFreePhysicalMemorySize') return 512 * 1024 * 1024;
      throw MissingPluginException('Unexpected memory call: ${call.method}');
    });
    messenger.setMockMethodCallHandler(_batteryChannel, (call) async {
      batteryCalls.add(call.method);
      switch (call.method) {
        case 'getBatteryLevel': return batteryLevel;
        case 'getBatteryState': return batteryState;
        case 'isInBatterySaveMode': return false;
        default: throw MissingPluginException('Unexpected battery call: ${call.method}');
      }
    });
    await appdata.init();
    await JsEngine().init();
    await ComicSourceManager().init();
    await HistoryManager().init();
    await ReadLaterManager().init();
    await LocalFavoritesManager().init();
    await DatabaseGateway.instance.runExclusive(() async {});
    final library = Directory('${temporary.path}/library')..createSync();
    File('${temporary.path}/local_path').writeAsStringSync(library.path);
    await LocalManager().init();
    comic = LocalComic(
      id: _comicId, title: '雨后书简', subtitle: 'HUD fixture', tags: const [],
      directory: 'hud-fixture', chapters: _chapters, cover: 'one/1.png',
      comicType: ComicType.local, downloadedChapters: const ['one', 'two'],
      createdAt: DateTime(2026, 1, 1));
    // Actual PNG files are enumerated and decoded by the real local Reader.
    for (final chapter in _chapters.ids) {
      final folder = Directory('${comic.baseDir}/${LocalManager.getChapterDirectoryName(chapter)}')
        ..createSync(recursive: true);
      for (var page = 1; page <= 3; page++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xffeeeae1), BlendMode.src);
        canvas.drawRect(const Rect.fromLTWH(0, 466, 430, 466),
            Paint()..color = const Color(0xff252b32));
        canvas.drawRect(Rect.fromLTWH(35.0 * page, 130, 120, 200),
            Paint()..color = const Color(0xff91aaa0));
        final picture = recorder.endRecording();
        final image = await picture.toImage(430, 932);
        try {
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          File('${folder.path}/$page.png').writeAsBytesSync(
              bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
    }
    await LocalManager().add(comic);
    debugDefaultTargetPlatformOverride = oldPlatform;
  });

  tearDownAll(() async {
    try {
      await appdata.saveData(false);
      await DatabaseGateway.instance.runExclusive(() async {});
      LocalManager().close();
      ReadLaterManager().close();
      LocalFavoritesManager().close();
      HistoryManager().close();
      JsEngine().dispose();
    } finally {
      messenger.setMockMethodCallHandler(_batteryChannel, null);
      messenger.setMockMethodCallHandler(_memoryChannel, null);
      App.dataPath = oldDataPath;
      App.cachePath = oldCachePath;
      temporary.deleteSync(recursive: true);
      IOOverrides.global = oldIO;
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });

  Future<void> frames(WidgetTester tester, [int count = 20]) async {
    for (var i = 0; i < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> capture(WidgetTester tester, String label) async {
    if (Platform.environment['HUD_EVIDENCE'] != '1') return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey));
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = Directory('build/reader-hud-evidence')..createSync(recursive: true);
      final file = File('${output.path}/real-reader-$label.png');
      file.writeAsBytesSync(bytes.buffer.asUint8List(
          bytes.offsetInBytes, bytes.lengthInBytes));
      debugPrint('READER_HUD_EVIDENCE ${file.path} ${image.width}x${image.height}');
    } finally {
      image.dispose();
    }
  }

  dynamic scaffold(WidgetTester tester) => tester.state(find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_ReaderScaffold'));

  void expectConnected(WidgetTester tester, String page, int level) {
    expect(_hud(), findsNWidgets(3),
        reason: 'Chapter/page, clock and battery must all use ReaderHudText');
    expect(find.byKey(const ValueKey('reader-page-info')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-status-info')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-info-bar')), findsOneWidget);
    expect(_hudWithValue(tester, page), findsOneWidget);
    final values = _hud().evaluate().map((element) =>
        _hudValue(tester, find.byWidget(element.widget))).toList();
    expect(values.where(_clockPattern.hasMatch), hasLength(1));
    expect(values.where((value) => value == '$level%'), hasLength(1));
    final battery = find.descendant(of: find.byType(Reader),
        matching: find.byType(ReaderHudBattery));
    expect(battery, findsOneWidget);
    expect(find.descendant(of: battery, matching: _hudWithValue(tester, '$level%')),
        findsOneWidget, reason: 'Battery percent must use the same outlined text');
    final icon = tester.widget<Icon>(find.descendant(of: battery,
        matching: find.byType(Icon)));
    expect(icon.icon, level == 100 ? Icons.battery_full_sharp : Icons.battery_charging_full);
    expect(icon.size, 16);
    expect(icon.shadows, hasLength(8));
    expect(icon.shadows!.map((s) => s.offset).toSet(), {
      const Offset(-0.8, -0.8), const Offset(0, -0.8), const Offset(0.8, -0.8),
      const Offset(-0.8, 0), const Offset(0.8, 0),
      const Offset(-0.8, 0.8), const Offset(0, 0.8), const Offset(0.8, 0.8),
    });
    for (final element in _hud().evaluate()) {
      _expectTwoAlignedPasses(tester, find.byWidget(element.widget));
    }
    final positioned = find.ancestor(of: _hudWithValue(tester, page),
        matching: find.byWidgetPredicate((widget) => widget is Positioned &&
            widget.left == 25 && widget.right == 25 && widget.bottom == 13));
    expect(positioned, findsOneWidget,
        reason: 'One constrained footer must contain page AND status');
    expect(find.descendant(of: positioned, matching: battery), findsOneWidget);
    final position = tester.widget<Positioned>(positioned);
    expect(position.child, isA<IgnorePointer>());
    final ignore = position.child as IgnorePointer;
    expect(ignore.ignoring, isTrue);
    expect(ignore.child, isA<Row>());
    final row = ignore.child! as Row;
    expect(row.children.first, isA<Expanded>());
    expect(row.children[1], isA<SizedBox>());
    expect((row.children[1] as SizedBox).width, 10);
    final pageRect = tester.getRect(_hudWithValue(tester, page));
    final batteryRect = tester.getRect(battery);
    expect(pageRect.right, lessThanOrEqualTo(batteryRect.left));
    expect(pageRect.left, closeTo(25, 0.01));
    expect(batteryRect.right, closeTo(tester.view.physicalSize.width - 25, 0.01));
    for (final rect in [pageRect, batteryRect]) {
      expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height - 12));
      expect(rect.top, greaterThan(0));
    }
    expect(batteryCalls, containsAll(['getBatteryLevel', 'getBatteryState']));
    expect(tester.takeException(), isNull);
  }

  for (final size in [const Size(430, 932), const Size(390, 844)]) {
    for (final dark in [false, true]) {
      for (final level in [100, 35]) {
        final label = '${size.width.toInt()}x${size.height.toInt()}-'
            '${dark ? 'dark' : 'light'}-$level-${level == 35 ? 'charging' : 'full'}';
        testWidgets('real Reader HUD $label: layers, paging, chrome and settings',
            (tester) async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          batteryLevel = level;
          batteryState = level == 35 ? 'charging' : 'full';
          batteryCalls.clear();
          // No comic-specific overrides are installed. Mutating these actual
          // settings below exercises the same reads as the Reader settings UI.
          for (final entry in <String, dynamic>{
            'language': 'en-US', 'readerMode': 'galleryLeftToRight',
            'adaptiveReading': false, 'enablePageAnimation': false,
            'showSingleImageOnFirstPage': false,
            'readerScreenPicNumberForPortrait': 1,
            'readerScreenPicNumberForLandscape': 1,
            'showChapterComments': false, 'enableContinuousChapterReading': false,
            'enableTurnPageByVolumeKey': false, 'autoRemoveFromReadLater': false,
            'readerKeepScreenOn': false, 'readerNightMode': false,
            'showPageNumberInReader': true,
            'enableClockAndBatteryInfoInReader': true,
          }.entries) {
            appdata.settings[entry.key] = entry.value;
          }
          try {
            await tester.runAsync(() async {
              try {
                final history = History.fromMap({
                  'id': _comicId, 'type': ComicType.local.value,
                  'title': comic.title, 'cover': comic.cover,
                  'time': DateTime.now().millisecondsSinceEpoch, 'ep': 1, 'page': 1,
                });
                // Read the real app theme without booting unrelated plugins;
                // override fonts only, preserving production 3.x text metrics.
                final dynamic themeFactory = const MyApp().createState();
                final ThemeData productionTheme = themeFactory.getTheme(
                    Colors.purple, null, null,
                    dark ? Brightness.dark : Brightness.light);
                final fontTheme = productionTheme.copyWith(
                  textTheme: productionTheme.textTheme.apply(
                    fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
                  primaryTextTheme: productionTheme.primaryTextTheme.apply(
                    fontFamily: 'HudLatin', fontFamilyFallback: const ['HudCJK']),
                );
                await tester.pumpWidget(MaterialApp(
                  navigatorKey: App.rootNavigatorKey,
                  theme: fontTheme,
                  builder: (context, child) => Material(child: child!),
                  debugShowCheckedModeBanner: false,
                  home: RepaintBoundary(key: _captureKey, child: Reader(
                    type: ComicType.local, cid: _comicId, name: comic.title,
                    author: comic.subtitle, tags: const [], chapters: _chapters,
                    history: history, initialChapter: 1, initialPage: 1)),
                ));
                await frames(tester, 60);
                final dynamic reader = tester.state(find.byType(Reader));
                expect(reader.isLoading, isFalse);
                expect(reader.maxPage, 3);
                expect(reader.page, 1);
                final decoded = tester.widgetList<RawImage>(find.descendant(
                    of: find.byType(Reader), matching: find.byType(RawImage)))
                    .where((widget) => widget.image != null).toList();
                expect(decoded, isNotEmpty,
                    reason: 'Evidence must include a decoded real local page');
                expect(decoded.any((widget) => widget.image!.width == 430 &&
                    widget.image!.height == 932), isTrue);
                expectConnected(tester, '第十二话雨后 : 1/3', level);
                await capture(tester, '$label-page1');

                await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
                await frames(tester, 40);
                expect(reader.page, 2);
                expectConnected(tester, '第十二话雨后 : 2/3', level);
                expect(_hudWithValue(tester, '第十二话雨后 : 1/3'), findsNothing);
                // Check both render layers: an old filled label must not remain
                // underneath a newly-updated outlined label.
                for (final element in _hud().evaluate()) {
                  expect(_paragraphs(tester, find.byWidget(element.widget))
                      .map((p) => p.text.toPlainText()),
                      isNot(contains('第十二话雨后 : 1/3')));
                }
                await capture(tester, '$label-page2');

                // Real center taps go through Reader gesture routing. Verify
                // the chrome actually changes, not merely that HUD stays built.
                expect(scaffold(tester).isOpen, isFalse);
                await tester.tapAt(Offset(size.width / 2, size.height / 2));
                await frames(tester, 30);
                expect(scaffold(tester).isOpen, isTrue);
                expect(tester.widgetList<ReaderChromeVisibility>(
                    find.byType(ReaderChromeVisibility)).any((w) => w.visible), isTrue);
                expectConnected(tester, '第十二话雨后 : 2/3', level);
                await capture(tester, '$label-chrome-open');
                await tester.tapAt(Offset(size.width / 2, size.height / 2));
                await frames(tester, 30);
                expect(scaffold(tester).isOpen, isFalse);
                expect(tester.widgetList<ReaderChromeVisibility>(
                    find.byType(ReaderChromeVisibility)).every((w) => !w.visible), isTrue);
                expectConnected(tester, '第十二话雨后 : 2/3', level);
                await capture(tester, '$label-chrome-closed');

                // Also change chapter through the mounted production API.
                reader.toNextChapter();
                await frames(tester, 40);
                expect(reader.chapter, 2);
                expectConnected(tester, '第十三话重逢 : 1/3', level);
                expect(_hudWithValue(tester, '第十二话雨后 : 2/3'), findsNothing);

                for (final flags in [(false, true), (true, false),
                    (false, false), (true, true)]) {
                  appdata.settings['showPageNumberInReader'] = flags.$1;
                  appdata.settings['enableClockAndBatteryInfoInReader'] = flags.$2;
                  // The actual settings panel invokes this same mounted update.
                  scaffold(tester).update();
                  await frames(tester, 15);
                  final values = _hud().evaluate().map((e) =>
                      _hudValue(tester, find.byWidget(e.widget))).toList();
                  expect(values.where((v) => v == '第十三话重逢 : 1/3'),
                      hasLength(flags.$1 ? 1 : 0));
                  expect(values.where(_clockPattern.hasMatch),
                      hasLength(flags.$2 ? 1 : 0));
                  expect(values.where((v) => v == '$level%'),
                      hasLength(flags.$2 ? 1 : 0));
                  expect(values, hasLength((flags.$1 ? 1 : 0) + (flags.$2 ? 2 : 0)));
                  expect(find.byType(ReaderHudBattery),
                      flags.$2 ? findsOneWidget : findsNothing);
                  expect(tester.takeException(), isNull);
                }
                expectConnected(tester, '第十三话重逢 : 1/3', level);
              } finally {
                await tester.pumpWidget(const SizedBox.shrink());
                await frames(tester, 20);
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                await DatabaseGateway.instance.runExclusive(() async {});
                await appdata.saveData(false);
              }
            });
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        });
      }
    }
  }
}
