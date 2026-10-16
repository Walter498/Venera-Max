import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/js_engine.dart';

import 'comments_fixtures.dart';

// Real QuickJS exports and production parser ownership; no hand-built sources.
void main() {
  setUpCommentsTestHost();
  late Directory temp;
  late String oldPath;
  var serial = 0;
  final keys = <String>[];

  dynamic evaluate(ComicSource source, String expression) => JsEngine().runCode(
        '(() => { const s = ComicSource.sources.${source.key}; '
        'return ($expression); })()',
      );

  void change(ComicSource source, String statements) {
    JsEngine().runCode(
      '(() => { const s = ComicSource.sources.${source.key}; $statements })()',
    );
  }

  int owned(ComicSource source) =>
      ComicSourceParser.debugOwnedFunctionCount(source.key);

  Future<ComicSource> parse({bool provider = true}) async {
    final key = 'metadata_lifetime_${serial++}';
    keys.add(key);
    return ComicSourceParser().parse('''
class MetadataLifetimeFixture extends ComicSource {
  name = "Metadata lifetime fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  init = null;
  search = {};
  categoryComics = {};
  revision = 0;
  settingsReads = 0;
  callbackGets = 0;
  throwCallback = false;
  throwSettings = false;
  missingProvider = false;
  callbacks = [
    value => "first:" + value,
    value => "second:" + value,
    value => "third:" + value
  ];
  get settings() {
    this.settingsReads++;
    if (this.throwSettings) { throw new Error("metadata unavailable"); }
    const s = this;
    const result = {
      action: {
        type: "callback",
        callback: s.callbacks[0],
        nested: {callback: s.callbacks[1]},
        get guarded() {
          s.callbackGets++;
          if (s.throwCallback) { throw new Error("callback getter traversed"); }
          return s.callbacks[2];
        }
      }
    };
    if (!this.missingProvider) {
      result.provider = {
        type: "select",
        default: this.revision === 0 ? "alpha" : "beta",
        options: this.revision === 0
          ? [{value: "alpha", text: "Alpha"}, {value: "beta", text: "Beta"}]
          : [{value: "beta", text: "Beta changed"}]
      };
    }
    return result;
  }
  comic = {
    ${provider ? 'commentProviderSetting: "provider",' : ''}
    commentCapabilities: {sorts: ["hot", "latest"], defaultSort: "hot"},
    async loadCommentsWithOptions() { return {comments: [], maxPage: 1}; }
  };
}
''', '${temp.path}/$key.js');
  }

  void remove(ComicSource source) {
    ComicSourceManager().remove(source.key);
    expect(owned(source), 0);
  }

  setUpAll(() async {
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('provider_metadata_');
    App.dataPath = temp.path;
    await initCommentsTestHost();
    await JsEngine().init();
  });

  tearDown(() {
    for (final key in keys) {
      ComicSourceManager().remove(key);
      expect(ComicSourceParser.debugOwnedFunctionCount(key), 0);
      JsEngine().runCode('void (delete ComicSource.sources.$key);');
    }
    keys.clear();
    JsEngine().runCode('void (delete globalThis.temp);');
  });

  tearDownAll(() {
    try {
      // close() remains strict: never swallow native reference failures.
      JsEngine().dispose();
    } finally {
      App.dataPath = oldPath;
      temp.deleteSync(recursive: true);
    }
  });

  test('negative control: full settings exports add three owned handles each',
      () async {
    final source = await parse();
    final baseline = owned(source);
    expect(baseline, 3);
    const exports = 12;
    final counts = <int>[];
    for (var i = 0; i < exports; i++) {
      final settings = source.getSettingsDynamic()!;
      // The JS function objects are stable, not freshly created per getter.
      expect(settings['action']!['callback'], isA<JSAutoFreeFunction>());
      counts.add(owned(source));
    }
    expect(counts, List.generate(exports, (i) => baseline + 3 * (i + 1)));
    expect(evaluate(source, 's.callbacks.length'), 3);
    ComicSourceParser.releaseSourceFunctions(source.key);
    expect(owned(source), 0);
    // Repeated release and manager removal are safe without relying on GC.
    ComicSourceParser.releaseSourceFunctions(source.key);
    remove(source);
  });

  test('1000 reader metadata rounds keep the exact parser baseline', () async {
    final source = await parse();
    final baseline = owned(source);
    expect(baseline, 3);
    source.data['commentSortPreferences'] = {
      'alpha': {'work': 'latest'},
    };
    var invalidReads = 0;
    var ownershipChanges = 0;
    for (var i = 0; i < 1000; i++) {
      final options = source.commentProviderOptions;
      final value = source.commentProviderValue;
      final sort = source.preferredCommentSort();
      if (options.length != 2 || options['alpha'] != 'Alpha' ||
          options['beta'] != 'Beta' || value != 'alpha' || sort != 'latest') {
        invalidReads++;
      }
      if (owned(source) != baseline) {
        ownershipChanges++;
      }
    }
    expect(invalidReads, 0);
    expect(ownershipChanges, 0);
    expect(owned(source), baseline);
    remove(source);
  });

  test('dynamic getter options and default stay live without callback traversal',
      () async {
    final source = await parse();
    final baseline = owned(source);
    change(source, 's.callbackGets = 0; s.throwCallback = true;');
    expect(source.commentProviderOptions, {'alpha': 'Alpha', 'beta': 'Beta'});
    expect(source.commentProviderValue, 'alpha');
    final reads = evaluate(source, 's.settingsReads') as int;
    change(source, 's.revision = 1;');
    expect(source.commentProviderOptions, {'beta': 'Beta changed'});
    expect(source.commentProviderValue, 'beta');
    expect(evaluate(source, 's.settingsReads'), greaterThan(reads));
    expect(evaluate(source, 's.callbackGets'), 0);
    expect(owned(source), baseline);
  });

  test('persisted value short circuits defaults; absent declaration is legacy',
      () async {
    final source = await parse();
    source.data['settings'] = {'provider': 'persisted-provider'};
    change(source, 's.settingsReads = 0; s.throwSettings = true;');
    expect(source.commentProviderValue, 'persisted-provider');
    expect(evaluate(source, 's.settingsReads'), 0);
    final legacy = await parse(provider: false);
    change(legacy, 's.settingsReads = 0; s.throwSettings = true;');
    expect(legacy.commentProviderOptions, isEmpty);
    expect(legacy.commentProviderValue, isNull);
    expect(legacy.preferredCommentSort(), 'hot');
    expect(evaluate(legacy, 's.settingsReads'), 0);
    expect(owned(source), 3);
    expect(owned(legacy), 3);
  });

  test('missing definition is empty; thrown metadata falls back to parsed settings',
      () async {
    final source = await parse();
    change(source, 's.missingProvider = true;');
    expect(source.commentProviderOptions, isEmpty);
    expect(source.commentProviderValue, isNull);
    change(source, 's.throwSettings = true;');
    expect(source.commentProviderOptions, {'alpha': 'Alpha', 'beta': 'Beta'});
    expect(source.commentProviderValue, 'alpha');
    expect(owned(source), 3);
  });

  test('full settings callbacks survive metadata reads and isolate source removal',
      () async {
    final first = await parse();
    final second = await parse();
    final before = first.getSettingsDynamic()!['action']!;
    final other = second.getSettingsDynamic()!['action']!;
    List<JSAutoFreeFunction> callbacks(Map<String, dynamic> action) => [
          action['callback'] as JSAutoFreeFunction,
          (action['nested'] as Map)['callback'] as JSAutoFreeFunction,
          action['guarded'] as JSAutoFreeFunction,
        ];
    final oldCallbacks = callbacks(before);
    Future<void> callable(List<JSAutoFreeFunction> functions) async {
      final results = <dynamic>[];
      for (final function in functions) {
        results.add(await function(['ok']));
      }
      expect(results, ['first:ok', 'second:ok', 'third:ok']);
    }

    await callable(oldCallbacks);
    expect(first.commentProviderOptions, {'alpha': 'Alpha', 'beta': 'Beta'});
    expect(first.commentProviderValue, 'alpha');
    expect(first.preferredCommentSort(), 'hot');
    expect(owned(first), 6);
    expect(owned(second), 6);
    await callable(oldCallbacks);
    final newCallbacks = callbacks(first.getSettingsDynamic()!['action']!);
    expect(owned(first), 9);
    await callable(newCallbacks);
    remove(first);
    for (final function in [...oldCallbacks, ...newCallbacks]) {
      expect(() => function(['removed']), throwsStateError);
    }
    expect(owned(second), 6);
    await callable(callbacks(other));
    expect(second.commentProviderValue, 'alpha');
    remove(second);
    for (final function in callbacks(other)) {
      expect(() => function(['removed']), throwsStateError);
    }
  });
}
