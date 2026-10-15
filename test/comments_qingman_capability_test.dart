import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';

// Real QuickJS + production parser + sendMessage(load_setting). No device,
// profile, network, account, node emulation or patched native reference asserts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String oldPath;
  var serial = 0;
  final sources = <ComicSource>[];

  Future<ComicSource> parse({bool getters = true, bool declared = true}) async {
    final key = 'qingman_capability_${serial++}';
    final source = await ComicSourceParser().parse('''
class QingmanCapabilityFixture extends ComicSource {
  name = "Qingman capability fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  // Avoid the inherited delayed init callback touching a deleted test source.
  init = null;
  search = {};
  categoryComics = {};
  settings = {
    commentProvider: {type:"select", default:"qingman", options:[
      {value:"tencent",text:"腾讯"}, {value:"qingman",text:"青漫"}]},
    qingmanCommentsEnabled: {type:"select",default:"on",options:[
      {value:"on",text:"开启"},{value:"off",text:"关闭"}]},
    manualqingmanbinding: {type:"input",default:""}
  };
  calls = 0;
  capabilities(workOnly) {
    const q = this.loadSetting('commentProvider') === 'qingman';
    return {sorts:workOnly?[]:q?['new','hot']:['new','hot','wonderful'],
      defaultSort:'new',canLoadReplies:!q&&!workOnly,
      enabled:!q || this.loadSetting('qingmanCommentsEnabled') !== 'off'};
  }
  makeCaps(workOnly) {
    const source = this, caps = {};
    for (const k of ['sorts','defaultSort','canLoadReplies','enabled']) {
      Object.defineProperty(caps,k,{enumerable:true,get() {
        // Same closure as the shipped source: this is caps, not the source.
        if (this !== caps) throw new Error('getter receiver changed');
        return source.capabilities(workOnly)[k];
      }});
    }
    return caps;
  }
  async load(workOnly,id,sub,page,reply,options) {
    this.calls++;
    if (reply !== null) throw new Error('non-null reply reached loader');
    if (this.loadSetting('commentProvider') === 'qingman' &&
        this.loadSetting('manualqingmanbinding') === '') {
      throw new Error('manual-binding-required');
    }
    return {comments:[],maxPage:1,total:0};
  }
  comic = {
    commentProviderSetting: 'commentProvider',
    async loadInfo(id) {return {title:id,cover:'',tags:{}};},
    ${declared ? '''
    commentCapabilities: ${getters ? 'this.makeCaps(true)' : '{enabled:true,canLoadReplies:false}'},
    chapterCommentCapabilities: ${getters ? 'this.makeCaps(false)' : '{enabled:true,canLoadReplies:false}'},
    ''' : ''}
    loadComments: async (id,sub,page,reply) => this.load(true,id,sub,page,reply,null),
    loadChapterComments: async (id,sub,page,reply) => this.load(false,id,sub,page,reply,null),
    loadCommentsWithOptions: async (id,sub,page,reply,options) => this.load(true,id,sub,page,reply,options),
    loadChapterCommentsWithOptions: async (id,sub,page,reply,options) => this.load(false,id,sub,page,reply,options)
  };
}
''', '${temp.path}/$key.js').timeout(const Duration(seconds: 10));
    // loadSetting uses ComicSource.find, i.e. the real Dart source registry.
    expect(ComicSourceManager().add(source), isTrue);
    sources.add(source);
    return source;
  }

  int calls(ComicSource source) => JsEngine().runCode(
      'ComicSource.sources.${source.key}.calls') as int;

  setUpAll(() async {
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('qingman_capability_');
    App.dataPath = temp.path;
    await JsEngine().init();
  });
  tearDown(() {
    for (final source in sources) {
      JsEngine().runCode('delete ComicSource.sources.${source.key};');
      ComicSourceManager().remove(source.key);
    }
    sources.clear();
  });
  tearDownAll(() {
    try {
      JsEngine().dispose();
    } finally {
      App.dataPath = oldPath;
      temp.deleteSync(recursive: true);
    }
  });

  test('real QJS explicit booleans and enumerable getters match JSON snapshot', () async {
    final source = await parse();
    for (final enabled in ['on', 'off', 'on']) {
      source.data['settings'] = {'qingmanCommentsEnabled': enabled};
      for (final chapter in [false, true]) {
        final path = chapter ? 'chapterCommentCapabilities' : 'commentCapabilities';
        final expression = 'ComicSource.sources.${source.key}.comic.$path';
        final direct = JsEngine().runCode(expression) as Map;
        // Diagnostic oracle only: production still uses the unmodified bridge.
        final snapshot = jsonDecode(JsEngine().runCode(
            'JSON.stringify($expression)') as String) as Map;
        expect(direct, snapshot, reason: '$enabled chapter=$chapter');
        expect(direct['enabled'], enabled == 'on');
        expect(direct['canLoadReplies'], false);
        final cap = chapter ? source.chapterCommentCapabilities : source.commentCapabilities;
        expect(cap!.enabled, enabled == 'on');
        expect(cap.canLoadReplies, isFalse);
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  for (final chapter in [false, true]) {
    test('${chapter ? "chapter" : "work"} default-on reaches missing binding, off blocks, on recovers', () async {
      final source = await parse();
      expect(source.data['settings'], isNull);
      final cap = chapter ? source.chapterCommentCapabilities : source.commentCapabilities;
      expect(cap!.enabled, isTrue);
      final missing = await source.loadCommentPage('123', '456', 1, null, chapter: chapter);
      expect(missing.error, isTrue);
      expect(missing.errorMessage, contains('manual-binding-required'));
      expect(calls(source), 1);
      source.data['settings'] = {'qingmanCommentsEnabled': 'off'};
      final disabled = await source.loadCommentPage('123', '456', 1, null, chapter: chapter);
      expect(disabled.error, isTrue);
      expect(calls(source), 1, reason: 'disabled must never call loader');
      source.data['settings'] = {'qingmanCommentsEnabled': 'on'};
      final recovered = await source.loadCommentPage('123', '456', 1, null, chapter: chapter);
      expect(recovered.errorMessage, contains('manual-binding-required'));
      expect(calls(source), 2);
      source.data['settings'] = {'commentProvider': 'tencent', 'qingmanCommentsEnabled': 'off'};
      expect((chapter ? source.chapterCommentCapabilities : source.commentCapabilities)!.enabled, isTrue);
      final tencent = await source.loadCommentPage('123', '456', 1, null, chapter: chapter);
      expect(tencent.error, isFalse);
      expect(calls(source), 3);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('${chapter ? "chapter" : "work"} null lists but empty/nonempty reply ids are gated', () async {
      final source = await parse(getters: false);
      for (final reply in ['', 'parent']) {
        final blocked = await source.loadCommentPage('123', '456', 1, reply, chapter: chapter);
        expect(blocked.error, isTrue);
        expect(calls(source), 0, reason: 'replyTo=$reply is non-null');
      }
      final list = await source.loadCommentPage('123', '456', 1, null, chapter: chapter);
      expect(list.errorMessage, contains('manual-binding-required'));
      expect(calls(source), 1);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  test('undeclared legacy capabilities remain null; explicit false stays false', () async {
    final source = await parse(declared: false);
    expect(source.commentCapabilities, isNull);
    expect(source.chapterCommentCapabilities, isNull);
    expect(CommentCapabilities.fromJson({'enabled': false}).enabled, isFalse);
    expect(CommentCapabilities.fromJson({}).enabled, isTrue);
    expect(CommentCapabilities.fromJson({'canLoadReplies': 'true'}).canLoadReplies, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
