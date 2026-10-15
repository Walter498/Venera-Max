import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/js_engine.dart';
import 'comments_fixtures.dart';

// Real parser + QuickJS, without App.init/device/account/JWT/network setup.
void main() {
  setUpCommentsTestHost();
  late Directory temp;
  late String oldPath;
  var serial = 0;
  final keys = <String>[];

  void stage(String tag, String value) {
    // Synchronous output survives a subsequent native evaluate stall.
    stdout.writeln('BRIDGE_MATRIX [$tag] $value');
  }

  Future<ComicSource> parse(String comic, {String? tag}) async {
    final key = 'comments_bridge_${serial++}';
    keys.add(key);
    if (tag != null) stage(tag, 'parse:start key=$key');
    final source = await ComicSourceParser().parse('''
class CommentsBridgeFixture extends ComicSource {
  name = "Comments bridge fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  // Real parser probes nested search hooks even when this source only exposes
  // comments. Supply optional containers, not fake executable loaders.
  search = {};
  categoryComics = {};
  init() {
    super.init();
    this.bridgeInitDone = true;
  }
  comic = {
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    $comic
  };
}
''', '${temp.path}/$key.js');
    if (tag != null) stage(tag, 'parse:done init:wait');
    // Parser schedules inherited init at 50ms. Let that real callback finish
    // before teardown deletes its JS source; do not disable/cancel the event.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(JsEngine().runCode('ComicSource.sources.$key.bridgeInitDone'), isTrue,
        reason: '$tag key=$key real parser init must finish before deletion');
    if (tag != null) stage(tag, 'init:done');
    return source;
  }

  String loaderName(bool chapter, bool options) => chapter
      ? (options ? 'loadChapterCommentsWithOptions' : 'loadChapterComments')
      : (options ? 'loadCommentsWithOptions' : 'loadComments');

  String capabilityName(bool chapter) => chapter
      ? 'chapterCommentCapabilities' : 'commentCapabilities';

  setUpAll(() async {
    oldPath = App.dataPath;
    temp = Directory.systemTemp.createTempSync('comments_bridge_');
    App.dataPath = temp.path;
    await initCommentsTestHost();
    await JsEngine().init();
  });
  tearDown(() {
    for (final key in keys) {
      JsEngine().runCode('delete ComicSource.sources.$key;');
    }
    keys.clear();
  });
  tearDownAll(() {
    try {
      // Keep strict QuickJS reference checking; a leak still fails the suite.
      JsEngine().dispose();
    } finally {
      App.dataPath = oldPath;
      temp.deleteSync(recursive: true);
    }
  });

  for (final chapter in [false, true]) {
    final scope = chapter ? 'chapter' : 'work';
    test('$scope legacy JS receives exactly four ordered arguments', () async {
      final source = await parse('''
        ${capabilityName(chapter)}: {sorts: ["hot"]},
        async ${loaderName(chapter, false)}(id, sub, page, reply) {
          if (arguments.length !== 4) throw new Error("legacy arity");
          if (id !== 'book "quoted"' || sub !== "ep" || page !== 2 ||
              reply !== 'parent "quoted"') throw new Error("legacy order");
          return {comments: [{id: reply, content: "four"}], maxPage: 3};
        }
      ''');
      final res = await source.loadCommentPage('book "quoted"', 'ep', 2,
          'parent "quoted"', chapter: chapter, sort: 'hot');
      expect(res.error, isFalse);
      expect(res.data.single.id, 'parent "quoted"');
      expect(res.data.single.content, 'four');
      expect(res.subData, 3);
      expect(res.available, isNull);
    });

    test('$scope legacy nullable second argument is scope-specific', () async {
      final source = await parse('''
        async ${loaderName(chapter, false)}(id, sub, page, reply) {
          globalThis.commentsBridgeNullCalls++;
          if (arguments.length !== 4 || sub !== null) throw new Error("nullable order");
          return {comments: [], maxPage: 1};
        }
      ''');
      JsEngine().runCode('globalThis.commentsBridgeNullCalls = 0;');
      final result = await source.loadCommentPage('book', null, 1, null, chapter: chapter);
      if (chapter) {
        expect(result.error, isTrue);
        expect(result.errorMessage, 'Chapter comments require a valid episode id');
        expect(JsEngine().runCode('globalThis.commentsBridgeNullCalls'), 0);
      } else {
        expect(result.error, isFalse);
        expect(JsEngine().runCode('globalThis.commentsBridgeNullCalls'), 1);
      }
      JsEngine().runCode('delete globalThis.commentsBridgeNullCalls;');
    });

    test('$scope undeclared legacy parent opens its actual replyTo bridge', () async {
      final source = await parse('''
        async ${loaderName(chapter, false)}(id, sub, page, reply) {
          if (arguments.length !== 4) throw new Error("legacy arity");
          if (reply === null) return {comments: [
            {id: "parent", replyCount: 2},
            {id: "zero", replyCount: 0},
            {id: "unknown", replyPreview: {content: "preview only"}},
            {id: null, replyCount: 2}, {id: "null", replyCount: 2}
          ], maxPage: 1};
          if (reply !== "parent") throw new Error("wrong parent identity");
          return {comments: [{id: "child", content: "actual legacy reply"}], maxPage: 1};
        }
      ''');
      final parents = await source.loadCommentPage('b', 'ep', 1, null, chapter: chapter);
      expect(parents.error, isFalse);
      expect(parents.data.map((c) => source.canReadReplies(c, chapter: chapter)),
          [true, true, false, false, false]);
      final replies = await source.loadCommentPage('b', 'ep', 1,
          parents.data.first.id, chapter: chapter);
      expect(replies.error, isFalse);
      expect(replies.data.single.content, 'actual legacy reply');
      expect(replies.data.single.id, 'child');
    });

    test('$scope options JS receives exactly five ordered arguments', () async {
      final source = await parse('''
        ${capabilityName(chapter)}: {sorts: ["hot"], canLoadReplies: true},
        async ${loaderName(chapter, true)}(id, sub, page, reply, options) {
          if (arguments.length !== 5) throw new Error("options arity");
          if (id !== "book" || sub !== "ep" || page !== 2 || reply !== "parent" ||
              options.sort !== "hot" || Object.keys(options).length !== 1)
            throw new Error("options order");
          return {comments: [{id: reply, content: "five"}], maxPage: 3, total: 9};
        }
      ''');
      final res = await source.loadCommentPage('book', 'ep', 2, 'parent',
          chapter: chapter, sort: 'hot');
      expect(res.error, isFalse);
      expect(res.data.single.content, 'five');
      expect(res.subData, 3);
      expect(res.total, 9);
    });

    for (final options in [false, true]) {
      final route = '$scope ${options ? "options" : "legacy"}';
      Future<ComicSource> responseSource(String body) => parse('''
        ${options ? '${capabilityName(chapter)}: {canLoadReplies: true},' : ''}
        async ${loaderName(chapter, options)}() { $body }
      ''');

      test('$route available false wins before comments parsing', () async {
        for (final body in [
          'return {available: false};',
          'return {available: false, comments: null, maxPage: 99, total: 99};',
          'return {available: false, comments: "invalid"};',
          'return {available: false, comments: [{id: "ignored"}]};',
        ]) {
          final source = await responseSource(body);
          final res = await source.loadCommentPage('b', 'ep', 1, null,
              chapter: chapter);
          expect(res.error, isFalse, reason: body);
          expect(res.available, isFalse);
          expect(res.data, isEmpty);
          expect(res.total, 0);
          expect(res.subData, 0);
          final controller = CommentsController(loader: (_, __) async => res);
          await controller.refresh();
          expect(controller.unavailable, isTrue);
          expect(controller.error, isNull);
          expect(controller.hasMore, isFalse);
          controller.dispose();
        }
      });

      test('$route errors and non-false malformed comments are not empty', () async {
        for (final body in [
          'throw new Error("offline fixture");',
          'return {error: "source failure"};',
          'return {};',
          'return {available: true};',
          'return {available: null, comments: null};',
          'return {available: "false", comments: "invalid"};',
          'return {comments: [null]};',
        ]) {
          final source = await responseSource(body);
          final res = await source.loadCommentPage('b', 'ep', 1, null,
              chapter: chapter);
          expect(res.error, isTrue, reason: body);
          expect(res.dataOrNull, isNull);
          expect(res.available, isNull);
          final controller = CommentsController(loader: (_, __) async => res);
          await controller.refresh();
          expect(controller.error, isNotNull);
          expect(controller.confirmedEmpty, isFalse);
          expect(controller.unavailable, isFalse);
          controller.dispose();
        }
      });
    }
  }

  for (final chapter in [false, true]) {
    test('${chapter ? "chapter" : "work"} nullable capabilities and legacy reply matrix', () async {
      for (final declaration in [null, '{}', '{sorts: ["hot"]}',
        '{canLoadReplies: null}', '{canLoadReplies: "true"}',
        '{canLoadReplies: false}', '{canLoadReplies: true}',
        '{enabled: false, canLoadReplies: true}']) {
        for (final legacy in [false, true]) {
          final tag = '${chapter ? "chapter" : "work"} '
              'declaration=$declaration legacy=$legacy';
          final source = await parse('''
            ${declaration == null ? '' : '${capabilityName(chapter)}: $declaration,'}
            ${legacy ? 'async ${loaderName(chapter, false)}() { return {comments: []}; },' : ''}
            async ${loaderName(chapter, true)}() { return {comments: []}; }
          ''', tag: tag);
          stage(tag, 'capability:read');
          final cap = chapter ? source.chapterCommentCapabilities : source.commentCapabilities;
          // Declarations are immutable in this matrix. Read the real JS getter
          // once, then exercise the unchanged production method for EVERY
          // combination with the actual parsed loaders and capability value.
          // Other bridge tests still exercise live JS-backed source objects.
          final matrixSource = commentsSource(
            legacy: source.commentsLoader,
            chapterLegacy: source.chapterCommentsLoader,
            options: source.commentsOptionsLoader,
            chapterOptions: source.chapterCommentsOptionsLoader,
            capabilities: chapter ? null : cap,
            chapterCapabilities: chapter ? cap : null,
          );
          stage(tag, 'capability:done');
          if (declaration == null) {
            expect(cap, isNull);
          } else if (!declaration.contains('canLoadReplies: true') &&
                     !declaration.contains('canLoadReplies: false')) {
            expect(cap!.canLoadReplies, isNull, reason: declaration);
          }
          final enabled = declaration != null && !declaration.contains('enabled: false');
          final repliesDisabled = declaration?.contains('canLoadReplies: false') == true;
          final repliesEnabled = declaration?.contains('canLoadReplies: true') == true;
          final scopeEnabled = declaration?.contains('enabled: false') != true;
          stage(tag, 'availability:read');
          expect(chapter ? source.hasChapterComments : source.hasComments,
              declaration?.contains('enabled: false') == true ? false : legacy || enabled);
          stage(tag, 'availability:done');
          var checked = 0;
          for (final id in [null, '', '  ', 'null', 'parent']) {
            stage(tag, 'matrix:id=${id == null ? "<null>" : '"$id"'} '
                'counts=[null,-1,0,2] previews=[false,true]');
            for (final count in [null, -1, 0, 2]) {
              for (final preview in [false, true]) {
                final comment = Comment.fromJson({
                  'id': id, 'replyCount': count,
                  if (preview) 'replyPreview': {'id': 'child', 'content': 'real preview'},
                });
                final readable = id == 'parent' && scopeEnabled &&
                    !repliesDisabled &&
                    (repliesEnabled || (legacy && comment.replyCount != null));
                expect(matrixSource.canReadReplies(comment, chapter: chapter), readable,
                    reason: '$tag id=$id count=$count preview=$preview');
                checked++;
              }
            }
          }
          expect(checked, 40, reason: '$tag all id/count/preview combinations');
          stage(tag, 'matrix:done checked=$checked guard:start');
          if (cap?.canLoadReplies == false || cap?.enabled == false) {
            // Even a direct attempted navigation cannot invoke either JS hook.
            final installed = JsEngine().runCode('''
              ComicSource.sources.${source.key}.bridgeHookCalls = 0;
              ComicSource.sources.${source.key}.comic.${loaderName(chapter, true)} =
                function() {
                  ComicSource.sources.${source.key}.bridgeHookCalls++;
                  throw new Error("disabled hook invoked");
                };
              ${legacy ? '''
              ComicSource.sources.${source.key}.comic.${loaderName(chapter, false)} =
                function() {
                  ComicSource.sources.${source.key}.bridgeHookCalls++;
                  throw new Error("disabled legacy hook invoked");
                };
              ''' : ''}
              // Assignment evaluates to the function. Do not export a QuickJS
              // function handle to Dart when the fixture only installs a hook.
              void 0;
            ''');
            expect(installed, isNull);
            final res = await source.loadCommentPage('b', 'ep', 1, 'parent', chapter: chapter);
            expect(res.error, isTrue);
            expect(res.errorMessage, endsWith(scopeEnabled
                ? '（replies-unsupported）' : '（comments-disabled）'), reason: tag);
            expect(res.dataOrNull, isNull, reason: tag);
            expect(JsEngine().runCode(
                'ComicSource.sources.${source.key}.bridgeHookCalls'), 0,
                reason: '$tag neither options nor legacy hook may run');
          }
          if (declaration == null && !legacy) {
            final res = await source.loadCommentPage('b', 'ep', 1, 'parent', chapter: chapter);
            expect(res.error, isTrue, reason: tag);
            expect(res.errorMessage, 'Comments loader unavailable');
          }
          stage(tag, 'guard:done fixture:done');
        }
      }
    });
  }
}
