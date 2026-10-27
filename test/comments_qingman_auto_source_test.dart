import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yaml/yaml.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/utils/translations.dart';

// Exact comments.7 distribution, including the production loadInfo parser.
const autoSourceSha256 =
    'c60a2ca4b19bf9bbf936a419e7d5788312f6d9ad8c1cf5a62ab2aa3a017e425a';
const _root = 'ComicSource.sources.lizimh';
const _state = 'globalThis.__qingmanAutoFixture';

// Public synthetic rawApiResponse from task/source/loadinfo7.fixture.json.
// This is NOT a ComicDetails result: only Lizimh.getJson is mocked.
const _rawInfo = <String, dynamic>{
  'name': '我独自升级',
  'author': '',
  'tags': '',
  'picY': '',
  'chapters': [
    {'id': '900', 'order': 1, 'name': '第1话 最弱猎人'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = File('test/fixtures/lizimh_comments7_fixture.js');
  late Directory temp;
  late String oldPath;
  ComicSource? registered;
  var ownsJs = false;

  void checkHash() => expect(
      sha256.convert(fixture.readAsBytesSync()).toString(), autoSourceSha256);

  void select(ComicSource source, String enabled) {
    // Deliberately no manualqingmanbinding key, no fake loadSetting or profile.
    source.data['settings'] = <String, dynamic>{
      'commentProvider': 'qingman',
      'qingmanCommentsEnabled': enabled,
    };
  }

  List<dynamic> calls() => jsonDecode(
      JsEngine().runCode('JSON.stringify($_state.calls)') as String) as List;

  Future<ComicSource> parse(String mode, {String extraScript = ''}) async {
    checkHash();
    expect(ComicSource.find('lizimh'), isNull);
    // Parser wraps this whole script in its own function. The lexical Qingman
    // shadows the frozen production global ONLY for business-response mocks;
    // no native transport, profile, credentials, or TLS is exercised here.
    final script = '${fixture.readAsStringSync()}\n'
        '''
Object.defineProperty(Lizimh.prototype, 'init', {value:null});
globalThis.__qingmanAutoFixture = {mode:${jsonEncode(mode)}, calls:[]};
Lizimh.getJson = async (path) => {
  $_state.calls.push({kind:'lizi', path});
  if (path !== '/app/api/v2/detail/5') throw new Error('Unexpected Lizi request');
  return ${jsonEncode(_rawInfo)};
};
const Qingman = Object.freeze({
  async request(path, params) {
    const s = $_state;
    s.calls.push({kind:'qingman', path, params});
    if (path === '/api/comic/history/fu893u94/search') {
      const rows = s.mode === 'search0' ? [] : s.mode === 'search2exact' ? [
        {id:'101', title:'我独自升级'}, {id:'102', title:'我独自升级'}
      ] : [
        {id:'100', title:'我独自升级 外传'},
        {id:'101', title:'我独自升级'},
        {id:'102', title:'我独自升级 第二季'}
      ];
      return {code:1, data:{datas:rows}};
    }
    if (path === '/api/comic/comics/ie84hfh8/detail') {
      return {code:1, data:{id:'101', title:'我独自升级'}};
    }
    if (path === '/api/comic/chapter/ie84hfh8/homelist/101') {
      return {code:1, data:{datas:[
        {id:'800', chapterName:'第1话 最弱猎人 下'},
        {id:'801', chapterName:s.mode === 'wrongchapter' ? '第1话 最弱猎人 上' : '第1话 最弱猎人'}
      ]}};
    }
    if (path === '/api/comic/comments/fu893u94/chapterList') {
      return {code:1, data:{total:1, datas:[{
        id:'9007199254740993123', nickname:'离线读者',
        avatar:'https://example.invalid/avatar.png', content:'完整整源自动匹配',
        createTime:'2026-10-15 12:00:00', likeNum:7, replyNum:3
      }]}};
    }
    throw new Error('Unexpected Qingman request: ' + path);
  }
});
$extraScript
''';
    ownsJs = true;
    final source = await ComicSourceParser()
        .parse(script, '${temp.path}/lizimh.js')
        .timeout(const Duration(seconds: 15));
    registered = source;
    expect(ComicSourceManager().add(source), isTrue);
    expect(source.version, '2.33.20-comments.7');
    expect(JsEngine().runCode('$_root.minAppVersion'), '1.2.2');
    expect(App.version, '2.4.0');
    expect(JsEngine().runCode('$_root.init === null'), isTrue);
    // Store functions inside JS; never export whole source/closures into Dart.
    JsEngine().runCode('void ($_state.originalLoadInfo = $_root.comic.loadInfo);');
    expect(source.data['settings'], isNull);
    expect(JsEngine().runCode("$_root.loadSetting('commentProvider')"), 'tencent');
    select(source, 'on');
    expect(source.data['settings'], {
      'commentProvider': 'qingman', 'qingmanCommentsEnabled': 'on',
    });
    expect(JsEngine().runCode("$_root.loadSetting('commentProvider')"), 'qingman');
    expect(JsEngine().runCode("$_root.loadSetting('manualqingmanbinding')"), '{}');
    expect(source.chapterCommentCapabilities!.enabled, isTrue);
    expect(source.chapterCommentCapabilities!.canLoadReplies, isFalse);
    expect(source.chapterCommentCapabilities!.sorts, ['new', 'hot']);
    expect(calls(), isEmpty);
    return source;
  }

  void expectChain({required bool catalog, required bool comments, String sort = 'new'}) {
    expect(calls(), [
      {'kind':'lizi', 'path':'/app/api/v2/detail/5'},
      {'kind':'qingman', 'path':'/api/comic/history/fu893u94/search',
        'params':{'keyword':'我独自升级'}},
      if (catalog) ...[
        {'kind':'qingman', 'path':'/api/comic/comics/ie84hfh8/detail',
          'params':{'comicId':'101'}},
        // Production native transport assigns GET to this allowlisted route.
        // request(path, params) has no method; this test does not invent one.
        {'kind':'qingman', 'path':'/api/comic/chapter/ie84hfh8/homelist/101',
          'params':<String, dynamic>{}},
      ],
      if (comments)
        {'kind':'qingman', 'path':'/api/comic/comments/fu893u94/chapterList',
          'params':{'page':1, 'size':20, 'chapterId':'801', 'sort':sort == 'new' ? 1 : 0}},
    ]);
    expect(JsEngine().runCode('$_root.comic.loadInfo === $_state.originalLoadInfo'), isTrue);
    expect(JsEngine().runCode('$_root._epMap["5"]["1"]'), '900',
        reason: 'Unmodified loadInfo parsed raw API chapter order/id mapping');
  }

  setUpAll(() async {
    checkHash();
    // Mock only the platform metadata boundary; use the production loader.
    final manifest = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final packageVersion = (manifest['version'] as String).split('+');
    final wasInitialized = App.isInitialized;
    PackageInfo.setMockInitialValues(
      appName: manifest['name'] as String,
      packageName: 'io.github.kyosee.venera',
      version: packageVersion.first,
      buildNumber: packageVersion.length > 1 ? packageVersion[1] : '',
      buildSignature: '',
    );
    await App.initPackageVersion();
    expect(App.version, packageVersion.first);
    expect(App.version, '2.4.0');
    expect(App.isInitialized, wasInitialized,
        reason: 'Package metadata must not mark the full App ready');
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('qingman_auto_source_');
    App.dataPath = temp.path;
    await AppTranslation.init();
    await JsEngine().init();
  });
  tearDown(() {
    if (ownsJs) {
      JsEngine().runCode('void (delete ComicSource.sources.lizimh);'
          'void (delete globalThis.temp); void (delete $_state);');
    }
    if (registered != null) ComicSourceManager().remove('lizimh');
    registered = null;
    ownsJs = false;
    checkHash();
  });
  tearDownAll(() {
    try {
      // No reset/skip/reference-count suppression. No JSInvokable is exported
      // by this test, so there are no caller-owned JSFunction handles to free.
      JsEngine().dispose();
    } finally {
      App.dataPath = oldPath;
      temp.deleteSync(recursive: true);
      checkHash();
    }
  });

  test('real parser rejects a higher minAppVersion before registration', () async {
    checkHash();
    expect(ComicSource.find('lizimh'), isNull);
    ownsJs = true;
    // Negative control only: preserve fixture bytes and the normal parse path.
    // The subclass changes only the instance minimum, not parser/comparison code.
    final script = '${fixture.readAsStringSync()}\n'
        'Lizimh = class extends Lizimh { minAppVersion = "999.0.0"; };\n';
    await expectLater(
      ComicSourceParser()
          .parse(script, '${temp.path}/version_gate_probe.js')
          .timeout(const Duration(seconds: 15)),
      throwsA(isA<ComicSourceParseException>().having(
        (error) => error.message, 'version gate', contains('999.0.0'))),
    );
    expect(ComicSource.find('lizimh'), isNull);
    expect(JsEngine().runCode('$_root === undefined'), isTrue);
    expect(App.version, '2.4.0');
    checkHash();
  });

  test('full source callbacks survive refresh and release on repeated remove',
      () async {
    for (var cycle = 0; cycle < 3; cycle++) {
      final source = await parse('valid', extraScript: '''
Lizimh.prototype.runDiagnosticTest = async function(images) {
  return images ? 'images-live' : 'api-live';
};
Lizimh = class extends Lizimh {
  constructor() {
    super();
    this.settings.lifecycleNested = {
      type:'callback', nested:[{callback:async () => 'nested-live'}]
    };
  }
};
''');
      final diagnostic = source.settings!['speedTest']!['callback']
          as JSAutoFreeFunction;
      final imageDiagnostic = source.settings!['imageSpeedTest']!['callback']
          as JSAutoFreeFunction;
      expect(await diagnostic([]), 'api-live');
      expect(await imageDiagnostic([]), 'images-live');
      final nested = (source.settings!['lifecycleNested']!['nested'] as List)
          .first['callback'] as JSAutoFreeFunction;
      expect(await nested([]), 'nested-live');
      final refreshed = <JSAutoFreeFunction>[];
      for (var refresh = 0; refresh < 3; refresh++) {
        final settings = source.getSettingsDynamic()!;
        final callback = settings['speedTest']!['callback'] as JSAutoFreeFunction;
        final child = (settings['lifecycleNested']!['nested'] as List)
            .first['callback'] as JSAutoFreeFunction;
        refreshed.addAll([callback, child]);
        expect(await callback([]), 'api-live');
        expect(await child([]), 'nested-live');
        expect(identical(ComicSourceParser.ownSourceValue('lizimh', callback),
            callback), isTrue);
      }
      final api = await source.apiFetch!('/app/api/v2/detail/5');
      expect(api.error, isFalse);
      ComicSourceManager().remove('lizimh');
      ComicSourceManager().remove('lizimh');
      ComicSourceParser.releaseSourceFunctions('lizimh');
      for (final callback in [diagnostic, imageDiagnostic, nested, ...refreshed]) {
        expect(() => callback([]), throwsStateError);
        expect(callback.func.toString(), contains('released'));
      }
      expect((await source.apiFetch!('/app/api/v2/detail/5')).error, isTrue);
      registered = null;
      JsEngine().runCode('void (delete $_root); void (delete globalThis.temp);'
          'void (delete $_state);');
      ownsJs = false;
      // Strict native close on every cycle, not a GC/reset-based cleanup.
      JsEngine().dispose();
      await JsEngine().init();
    }
  });

  for (final sort in ['new', 'hot']) {
    test('entire comments.7 automatic chapter match / $sort / real Dart Comment', () async {
      final source = await parse('valid');
      final result = await source.loadCommentPage('5', '1', 1, null,
          chapter: true, sort: sort).timeout(const Duration(seconds: 10));
      expect(result.error, isFalse, reason: result.errorMessage);
      expect(result.available, isTrue);
      expect(result.total, 1);
      expect(result.subData, 1);
      expect(result.data, hasLength(1));
      final comment = result.data.single;
      expect(comment, isA<Comment>());
      expect(comment.id, 'qingman:9007199254740993123');
      expect(comment.userName, '离线读者');
      expect(comment.avatar, 'https://example.invalid/avatar.png');
      expect(comment.content, '完整整源自动匹配');
      expect(comment.time, '2026-10-15 12:00:00');
      expect(comment.score, 7);
      expect(comment.replyCount, 3);
      expect(comment.replyPreview, isNull);
      expect(source.canReadReplies(comment, chapter: true), isFalse);
      expectChain(catalog: true, comments: true, sort: sort);
      final before = calls();
      final reply = await source.loadCommentPage('5', '1', 1, comment.id, chapter: true);
      expect(reply.error, isTrue);
      expect(reply.errorMessage, contains('replies-unsupported'));
      expect(calls(), before, reason: 'Unsupported reply must never reach mock request');
    });
  }

  for (final entry in {
    'search0':'work-unresolved',
    'search2exact':'work-ambiguous',
    'wrongchapter':'chapter-unresolved',
  }.entries) {
    test('${entry.key} fails closed and remains rejected after on/off/on', () async {
      final source = await parse(entry.key);
      for (final enabled in ['on', 'off', 'on']) {
        select(source, enabled);
        JsEngine().runCode('void ($_state.calls = []);');
        expect(source.chapterCommentCapabilities!.enabled, enabled == 'on');
        expect(source.chapterCommentCapabilities!.canLoadReplies, isFalse);
        final result = await source.loadCommentPage('5', '1', 1, null,
            chapter: true).timeout(const Duration(seconds: 10));
        expect(result.error, isTrue);
        expect(result.errorMessage, contains(enabled == 'off' ? 'comments-disabled' : entry.value));
        if (enabled == 'off') {
          expect(calls(), isEmpty);
        } else {
          expectChain(catalog: entry.key == 'wrongchapter', comments: false);
        }
      }
    });
  }
}
