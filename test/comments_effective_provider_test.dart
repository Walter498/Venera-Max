import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'comments_fixtures.dart';

// Effective comment-provider regression: the provider confirmed by a response
// must decide sorting/reply/interaction gates, and a controller must never
// invent a provider from a failed, empty, stale or field-less page.
// Pure Res/ComicSource/CommentsController units: no widgets, no network, no
// source setting mutation.

/// Tencent-shaped declaration: all three sorts and replies available.
/// The qingman route must override this without touching source settings.
ComicSource effectiveProviderSource() => commentsSource(
  options: (id, sub, page, reply, opts) async => const Res<List<Comment>>([], subData: 1),
  capabilities: const CommentCapabilities(sorts: ['new', 'hot', 'wonderful'],
    defaultSort: 'wonderful', canLoadReplies: true),
  chapterOptions: (id, ep, page, reply, opts) async => const Res<List<Comment>>([], subData: 1),
  chapterCapabilities: const CommentCapabilities(sorts: ['new', 'hot', 'wonderful'],
    defaultSort: 'wonderful', canLoadReplies: true));

void main() {
  setUpCommentsTestHost();

  group('Res.parseCommentProvider / parseEffectiveProvider', () {
    test('effectiveProvider wins over the legacy provider field', () {
      expect(Res.parseCommentProvider(
        {'effectiveProvider': 'qingman', 'provider': 'tencent'}), 'qingman');
      expect(Res.parseCommentProvider({'effectiveProvider': ' tencent ', 'provider': 'qingman'}),
        'tencent');
    });
    test('legacy response without either field stays null', () {
      expect(Res.parseCommentProvider({'comments': <dynamic>[], 'maxPage': 1, 'total': 0}),
        isNull);
      expect(Res.parseCommentProvider(<String, dynamic>{}), isNull);
      expect(Res.parseCommentProvider(null), isNull);
      expect(Res.parseCommentProvider('qingman'), isNull);
      expect(Res.parseCommentProvider(<dynamic>['qingman']), isNull);
    });
    test('provider field is the only fallback and blank values never count', () {
      expect(Res.parseCommentProvider({'provider': 'tencent'}), 'tencent');
      expect(Res.parseCommentProvider({'effectiveProvider': '   ', 'provider': 'tencent'}),
        'tencent');
      expect(Res.parseCommentProvider({'effectiveProvider': '   '}), isNull);
      expect(Res.parseCommentProvider({'effectiveProvider': 42}), isNull);
      expect(Res.parseCommentProvider({'effectiveProvider': '', 'provider': 7}), isNull);
      expect(Res.parseEffectiveProvider('  qingman  '), 'qingman');
      expect(Res.parseEffectiveProvider(''), isNull);
      expect(Res.parseEffectiveProvider(0), isNull);
    });
    test('a legacy Res keeps a null effectiveProvider while the new field carries it', () {
      expect(const Res<List<Comment>>([], subData: 1).effectiveProvider, isNull);
      expect(const Res<List<Comment>>([], subData: 1, effectiveProvider: 'qingman')
        .effectiveProvider, 'qingman');
    });
  });

  group('CommentsController effective provider lifecycle', () {
    test('first page qingman notifies success and a field-less later page retains it', () async {
      var calls = 0;
      final c = CommentsController(loader: (page, sort) async {
        calls++;
        if (page == 1) {
          return Res<List<Comment>>([commentFixture('topic-1')], subData: 3, total: 3,
            effectiveProvider: 'qingman');
        }
        return Res<List<Comment>>([commentFixture('topic-2')], subData: 3, total: 3);
      });
      var notifications = 0;
      c.addListener(() => notifications++);
      await c.refresh();
      expect(c.error, isNull);
      expect(c.pageError, isNull);
      expect(c.loaded, isTrue);
      expect(c.loading, isFalse);
      expect(c.effectiveProvider, 'qingman');
      // loading=true notification plus the terminal success notification.
      expect(notifications, greaterThanOrEqualTo(2));
      await c.loadMore();
      expect(calls, 2);
      expect(c.page, 2);
      expect(c.effectiveProvider, 'qingman',
        reason: 'an omitted field must not clear the confirmed provider');
      expect(c.comments.map((comment) => comment.id), ['topic-1', 'topic-2']);
      c.dispose();
    });

    test('legacy pages without any provider field keep the controller provider null', () async {
      final c = CommentsController(loader: (_, __) async =>
        Res<List<Comment>>([commentFixture('legacy-1')], subData: 2, total: 2));
      await c.refresh();
      expect(c.loaded, isTrue);
      expect(c.effectiveProvider, isNull);
      await c.loadMore();
      expect(c.effectiveProvider, isNull);
      c.dispose();
    });

    test('explicit refresh clears the previous provider before the new page resolves', () async {
      var calls = 0;
      final second = Completer<Res<List<Comment>>>();
      final c = CommentsController(loader: (page, sort) {
        calls++;
        if (calls == 1) {
          return Future.value(Res<List<Comment>>([commentFixture('topic-1')], subData: 1,
            effectiveProvider: 'qingman'));
        }
        return second.future;
      });
      await c.refresh();
      expect(c.effectiveProvider, 'qingman');
      final pending = c.refresh();
      expect(c.effectiveProvider, isNull,
        reason: 'a refresh must not keep the previous route while it is in flight');
      second.complete(Res<List<Comment>>([commentFixture('topic-1')], subData: 1));
      await pending;
      expect(c.effectiveProvider, isNull);
      expect(c.loaded, isTrue);
      c.dispose();
    });

    test('a failed page never assigns a provider, even when the Res carries one', () async {
      final c = CommentsController(loader: (_, __) async =>
        Res<List<Comment>>(null, errorMessage: 'offline', effectiveProvider: 'qingman'));
      await c.refresh();
      expect(c.error, isNotNull);
      expect(c.loading, isFalse);
      expect(c.loaded, isFalse);
      expect(c.effectiveProvider, isNull,
        reason: 'the error path must not adopt the failed response route');
      c.dispose();
    });

    test('later-page failure keeps the first page provider and stays page-scoped', () async {
      final c = CommentsController(loader: (page, sort) async {
        if (page == 1) {
          return Res<List<Comment>>([commentFixture('topic-1')], subData: 3, total: 3,
            effectiveProvider: 'qingman');
        }
        return const Res.error('page offline');
      });
      await c.refresh();
      expect(c.effectiveProvider, 'qingman');
      await c.loadMore();
      expect(c.error, isNull);
      expect(c.pageError, isNotNull);
      expect(c.effectiveProvider, 'qingman',
        reason: 'a failed next page is not evidence of a different route');
      c.dispose();
    });

    test('a superseded response cannot assign its provider to the new generation', () async {
      final slow = Completer<Res<List<Comment>>>();
      final hot = Completer<Res<List<Comment>>>();
      final c = CommentsController(sort: 'new',
        loader: (page, sort) => sort == 'new' ? slow.future : hot.future);
      final first = c.refresh();
      final second = c.refresh(nextSort: 'hot');
      slow.complete(Res<List<Comment>>([commentFixture('late-1')], subData: 1,
        effectiveProvider: 'tencent'));
      await first;
      expect(c.effectiveProvider, isNull, reason: 'the stale tencent page must not win');
      expect(c.loading, isTrue);
      hot.complete(Res<List<Comment>>([commentFixture('hot-1')], subData: 1,
        effectiveProvider: 'qingman'));
      await second;
      expect(c.effectiveProvider, 'qingman');
      expect(c.comments.single.id, 'hot-1');
      expect(c.loading, isFalse);
      c.dispose();
    });
  });

  group('ComicSource gates for the qingman effective provider', () {
    test('qingman replaces the declared Tencent sorts with new/hot', () {
      final source = effectiveProviderSource();
      expect(source.commentCapabilitiesFor(provider: 'qingman')!.sorts, ['new', 'hot']);
      expect(source.commentCapabilitiesFor(provider: 'qingman')!.defaultSort, 'new');
      expect(source.commentCapabilitiesFor(provider: 'qingman')!.canLoadReplies, isFalse);
      expect(source.availableCommentSorts(provider: 'qingman'), ['new', 'hot']);
      expect(source.availableCommentSorts(chapter: true, provider: 'qingman'), ['new', 'hot']);
      // provider null (or an unknown route) keeps the source-declared behavior.
      expect(source.availableCommentSorts(), ['new', 'hot', 'wonderful']);
      expect(source.availableCommentSorts(chapter: true), ['new', 'hot', 'wonderful']);
      expect(source.availableCommentSorts(provider: 'tencent'), ['new', 'hot', 'wonderful']);
      // Read-only: the override never writes source settings.
      expect(source.data['settings'], isNull);
    });

    test('qingman rejects replies and interaction although Tencent allows both', () {
      final source = effectiveProviderSource();
      final comment = commentFixture('topic');
      expect(source.commentCapabilities!.canLoadReplies, isTrue);
      expect(source.canReadReplies(comment), isTrue);
      expect(source.canReadReplies(comment, chapter: true), isTrue);
      expect(source.canReadReplies(comment, provider: 'qingman'), isFalse);
      expect(source.canReadReplies(comment, chapter: true, provider: 'qingman'), isFalse);
      expect(source.canReadReplies(comment, provider: 'tencent'), isTrue);
      expect(source.canInteractWithComments(provider: 'qingman'), isFalse);
      expect(source.canInteractWithComments(chapter: true, provider: 'qingman'), isFalse);
      expect(source.canInteractWithComments(), isTrue);
      expect(source.canInteractWithComments(chapter: true), isTrue);
      expect(source.canInteractWithComments(provider: 'tencent'), isTrue);
      expect(source.data['settings'], isNull);
    });

    test('qingman rejection is the provider, not a declared reply capability', () {
      final disabled = commentsSource(
        options: (id, sub, page, reply, opts) async => const Res<List<Comment>>([], subData: 1),
        capabilities: const CommentCapabilities(sorts: ['new', 'hot'], canLoadReplies: false));
      expect(disabled.canReadReplies(commentFixture('topic')), isFalse);
      expect(disabled.canReadReplies(commentFixture('topic'), provider: 'qingman'), isFalse);
      final legacy = commentsSource(legacy: (a, b, c, d) async => const Res([], subData: 1));
      // Legacy source: no declaration, no effective provider -> unchanged path.
      expect(legacy.commentCapabilities, isNull);
      expect(legacy.canInteractWithComments(), isTrue);
      expect(legacy.canReadReplies(commentFixture('topic'), provider: 'qingman'), isFalse);
    });
  });
}
