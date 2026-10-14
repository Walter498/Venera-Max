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

  Future<ComicSource> parse(String comic) async {
    final key = 'comments_bridge_${serial++}';
    keys.add(key);
    return ComicSourceParser().parse('''
class CommentsBridgeFixture extends ComicSource {
  name = "Comments bridge fixture";
  key = "$key";
  version = "1.0.0";
  minAppVersion = null;
  // Real parser probes nested search hooks even when this source only exposes
  // comments. Supply optional containers, not fake executable loaders.
  search = {};
  categoryComics = {};
  comic = {
    async loadInfo(id) { return {title: id, cover: "", tags: {}}; },
    $comic
  };
}
''', '${temp.path}/$key.js');
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
    JsEngine().dispose();
    App.dataPath = oldPath;
    temp.deleteSync(recursive: true);
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
          final source = await parse('''
            ${declaration == null ? '' : '${capabilityName(chapter)}: $declaration,'}
            ${legacy ? 'async ${loaderName(chapter, false)}() { return {comments: []}; },' : ''}
            async ${loaderName(chapter, true)}() { return {comments: []}; }
          ''');
          final cap = chapter ? source.chapterCommentCapabilities : source.commentCapabilities;
          if (declaration == null) {
            expect(cap, isNull);
          } else if (!declaration.contains('canLoadReplies: true') &&
                     !declaration.contains('canLoadReplies: false')) {
            expect(cap!.canLoadReplies, isNull, reason: declaration);
          }
          final enabled = declaration != null && !declaration.contains('enabled: false');
          expect(chapter ? source.hasChapterComments : source.hasComments,
              declaration?.contains('enabled: false') == true ? false : legacy || enabled);
          for (final id in [null, '', '  ', 'null', 'parent']) {
            for (final count in [null, -1, 0, 2]) {
              for (final preview in [false, true]) {
                final comment = Comment.fromJson({
                  'id': id, 'replyCount': count,
                  if (preview) 'replyPreview': {'id': 'child', 'content': 'real preview'},
                });
                final readable = id == 'parent' && cap?.enabled != false &&
                    cap?.canLoadReplies != false &&
                    (cap?.canLoadReplies == true ||
                      (legacy && comment.replyCount != null));
                expect(source.canReadReplies(comment, chapter: chapter), readable,
                    reason: '$declaration legacy=$legacy id=$id count=$count preview=$preview');
              }
            }
          }
          if (cap?.canLoadReplies == false || cap?.enabled == false) {
            // Even a direct attempted navigation cannot invoke either JS hook.
            JsEngine().runCode('''
              ComicSource.sources.${source.key}.comic.${loaderName(chapter, true)} =
                function() { throw new Error("disabled hook invoked"); };
            ''');
            final res = await source.loadCommentPage('b', 'ep', 1, 'parent', chapter: chapter);
            expect(res.error, isTrue);
            expect(res.errorMessage, 'Comments capability unavailable');
          }
          if (declaration == null && !legacy) {
            final res = await source.loadCommentPage('b', 'ep', 1, 'parent', chapter: chapter);
            expect(res.errorMessage, 'Comments loader unavailable');
          }
        }
      }
    });
  }
}
