import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';

// Intentionally the entire comments.5 release, not the simplified fixture or .6.
// No capability/loadSetting/transport patches, profile, widget, or device access.
const shippedHash =
    '9a9f19fe6ce8f61953515832a3ab84b12edc5934e8d6f51ffee44b8d56efe2f9';
const root = 'ComicSource.sources.lizimh';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = File('test/fixtures/lizimh_comments5_fixture.js');
  late Directory temp;
  late String oldPath;
  ComicSource? registered;
  var ownsJs = false;

  void checkHash() => expect(
      sha256.convert(fixture.readAsBytesSync()).toString(), shippedHash);

  void select(ComicSource source, String provider, {String enabled = 'on'}) {
    source.data['settings'] = <String, dynamic>{
      'commentProvider': provider,
      'qingmanCommentsEnabled': enabled,
      'manualqingmanbinding': '{}',
      // Prevent even local metadata loading in the raw Tencent pending test.
      'tencentCommentsEnabled': 'off',
    };
  }

  Future<ComicSource> parse() async {
    checkHash();
    expect(ComicSource.find('lizimh'), isNull,
        reason: 'Do not remove or overwrite a pre-existing same-key source');
    // Parser instantiates after all appended code is evaluated and schedules
    // init only if non-null (parser.dart:244). Shadow the inherited method on
    // this class only, externally; fixture bytes remain exactly the release.
    final script = '${fixture.readAsStringSync()}\n'
        'Object.defineProperty(Lizimh.prototype,"init",{value:null});\n';
    ownsJs = true;
    final source = await ComicSourceParser()
        .parse(script, '${temp.path}/lizimh.js')
        .timeout(const Duration(seconds: 15));
    registered = source;
    expect(ComicSourceManager().add(source), isTrue);
    expect(source.version, '2.33.20-comments.5');
    expect(JsEngine().runCode('$root.init === null'), isTrue);
    return source;
  }

  Map caps(bool chapter, {bool snapshot = false}) {
    final path = chapter ? 'chapterCommentCapabilities' : 'commentCapabilities';
    final expression = '$root.comic.$path';
    if (snapshot) {
      return jsonDecode(JsEngine().runCode('JSON.stringify($expression)') as String)
          as Map;
    }
    return JsEngine().runCode(expression) as Map;
  }

  setUpAll(() async {
    checkHash();
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('qingman_shipped_source_');
    App.dataPath = temp.path;
    await JsEngine().init();
  });
  tearDown(() {
    // JS objects may contain native callable handles. Never export whole source.
    if (ownsJs) {
      JsEngine().runCode('void (delete ComicSource.sources.lizimh);'
          'void (delete globalThis.temp);');
    }
    if (registered != null) ComicSourceManager().remove('lizimh');
    registered = null;
    ownsJs = false;
    checkHash();
  });
  tearDownAll(() {
    try {
      // Keep native reference-count assertions enabled; no test skip/reset trick.
      JsEngine().dispose();
    } finally {
      App.dataPath = oldPath;
      temp.deleteSync(recursive: true);
      checkHash();
    }
  });

  test('full release default Tencent, then live Qingman per-property capabilities',
      () async {
    final source = await parse();
    expect(source.data['settings'], isNull);
    expect(JsEngine().runCode("$root.loadSetting('commentProvider')"), 'tencent');
    final oldRaw = caps(true);
    final oldSnapshot = caps(true, snapshot: true);
    final oldCapability = source.chapterCommentCapabilities!;
    expect(oldRaw['canLoadReplies'], isTrue);
    expect(oldCapability.canLoadReplies, isTrue);
    select(source, 'qingman');
    expect(JsEngine().runCode("$root.loadSetting('commentProvider')"), 'qingman');
    for (final chapter in [false, true]) {
      final direct = caps(chapter);
      expect(direct, caps(chapter, snapshot: true));
      expect(direct['enabled'], isTrue);
      expect(direct['canLoadReplies'], isFalse);
      final capability = chapter
          ? source.chapterCommentCapabilities! : source.commentCapabilities!;
      expect(capability.enabled, isTrue);
      expect(capability.canLoadReplies, isFalse);
      expect(capability.sorts, chapter ? ['new', 'hot'] : isEmpty);
    }
    // Dart conversions/snapshots are values, not live JS objects.
    expect(oldRaw, oldSnapshot);
    expect(oldRaw['canLoadReplies'], isTrue);
    expect(oldCapability.canLoadReplies, isTrue);
    // Each shipped capability property creates a fresh provider manager; it
    // must NOT create/revise the persistent loader's _commentProviders.
    expect(JsEngine().runCode('$root._commentProviders === undefined'), isTrue);
  });

  for (final chapter in [false, true]) {
    test('${chapter ? "chapter" : "work"} on reaches missing binding, not capability gate',
        () async {
      final source = await parse();
      select(source, 'qingman');
      expect(caps(chapter)['enabled'], isTrue);
      expect(caps(chapter), caps(chapter, snapshot: true));
      final raw = await JsEngine().runCode(
          '$root.comic.${chapter ? "loadChapterCommentsWithOptions" : "loadCommentsWithOptions"}'
          '("123","456",1,null,{})') as Map;
      expect(raw['available'], isFalse);
      expect(raw['reason'], 'manual-binding-required');
      final result = await source.loadCommentPage('123', '456', 1, null,
          chapter: chapter);
      expect(result.error, isFalse);
      expect(result.available, isFalse);
      expect(result.data, isEmpty);
      expect(result.errorMessage, isNull);
    });

    test('${chapter ? "chapter" : "work"} off/on uses real settings and recovers',
        () async {
      final source = await parse();
      for (final enabled in ['on', 'off', 'on']) {
        select(source, 'qingman', enabled: enabled);
        expect(caps(chapter)['enabled'], enabled == 'on');
        expect(caps(chapter), caps(chapter, snapshot: true));
        final capability = chapter
            ? source.chapterCommentCapabilities! : source.commentCapabilities!;
        expect(capability.enabled, enabled == 'on');
        final result = await source.loadCommentPage('123', '456', 1, null,
            chapter: chapter);
        expect(result.error, enabled == 'off');
        if (enabled == 'off') {
          expect(result.errorMessage, contains('comments-disabled'));
        } else {
          expect(result.available, isFalse);
        }
      }
    });
  }

  test('shipped raw pending has an ABA settings-snapshot blind spot', () async {
    final source = await parse();
    source.data['settings'] = {'tencentCommentsEnabled': 'off'};
    final invoke = JsEngine().runCode('''(switchAwayAndBack) => {
      const pending = $root.comic.loadChapterCommentsWithOptions(
        '123', '456', 1, null, {});
      switchAwayAndBack();
      return pending;
    }''') as JSInvokable;
    try {
      final result = await invoke([() {
        select(source, 'qingman');
        expect(caps(true)['enabled'], isTrue);
        expect(caps(true, snapshot: true)['enabled'], isTrue);
        expect(source.chapterCommentCapabilities!.enabled, isTrue);
        select(source, 'tencent');
        expect(caps(true)['enabled'], isFalse);
      }]) as Map;
      // Characterize .5, do not pretend it has a monotonic setting revision.
      // Reading fresh capability providers never tokens the loader manager;
      // the manager sees identical Tencent snapshots before and after await.
      expect(result['available'], isFalse);
      expect(result['reason'], isNull,
          reason: 'actual .5 returns old Tencent disabled result, not provider-changed');
    } finally {
      invoke.free();
    }
  });

  test('actual raw Tencent pending result is invalidated on switch to Qingman',
      () async {
    final source = await parse();
    expect(JsEngine().runCode("$root.loadSetting('commentProvider')"), 'tencent');
    // Default provider remains Tencent, but explicitly off avoids ALL requests.
    source.data['settings'] = {'tencentCommentsEnabled': 'off'};
    final before = caps(true);
    expect(before['enabled'], isFalse);
    // Run native setting mutation synchronously in the same JS stack, before
    // the actual async Tencent loader's fulfilled promise resumes. No fake
    // response, metadata, fake provider, timer race, or patched getter involved.
    final invoke = JsEngine().runCode('''(switchNow) => {
      const pending = $root.comic.loadChapterCommentsWithOptions(
        '123', '456', 1, null, {});
      switchNow();
      return pending;
    }''') as JSInvokable;
    try {
      final result = await invoke([() { select(source, 'qingman'); }]) as Map;
      expect(result['available'], isFalse);
      expect(result['reason'], 'provider-changed');
    } finally {
      invoke.free();
    }
    expect(before['enabled'], isFalse, reason: 'old Dart map stays stale');
    expect(caps(true)['enabled'], isTrue);
    expect(caps(true), caps(true, snapshot: true));
    final current = await source.loadCommentPage('123', '456', 1, null,
        chapter: true);
    expect(current.error, isFalse);
    expect(current.available, isFalse);
  });
}
