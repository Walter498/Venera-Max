import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();

  for (final reason in ['unavailable', 'no-match', 'nonunique']) {
    test('$reason uses formal available false, not an error string', () async {
      final source = commentsSource(legacy: (id, sub, page, reply) async =>
        const Res<List<Comment>>([], available: false, total: 0, subData: 0));
      final session = DetailsCommentsSession(source: source, cid: 'work', subId: 'sub');
      addTearDown(session.dispose);
      expect(session.showEntry, isFalse);
      await session.preload();
      expect(session.controller.unavailable, isTrue);
      expect(session.controller.error, isNull);
      expect(session.showEntry, isFalse);
      expect(session.controller.hasMore, isFalse);
    });
  }

  test('confirmed empty hides entry without inventing absence on pending', () async {
    final pending = Completer<Res<List<Comment>>>();
    final session = DetailsCommentsSession(source: commentsSource(
      legacy: (a, b, c, d) => pending.future), cid: 'work', subId: 'sub');
    addTearDown(session.dispose);
    final load = session.preload();
    expect(session.showEntry, isFalse);
    expect(session.controller.confirmedEmpty, isFalse);
    pending.complete(const Res([], subData: 1, total: 0));
    await load;
    expect(session.controller.confirmedEmpty, isTrue);
    expect(session.controller.unavailable, isFalse);
    expect(session.showEntry, isFalse);
  });

  test('legacy successful response opens entry; word filtering is not absence', () async {
    final session = DetailsCommentsSession(source: commentsSource(
      legacy: (a, b, c, d) async => Res([commentFixture('blocked')], subData: 1)),
      cid: 'work', subId: 'sub', block: (_) => true);
    addTearDown(session.dispose);
    await session.preload();
    expect(session.controller.available, isNull);
    expect(session.controller.comments, isEmpty);
    expect(session.controller.confirmedEmpty, isFalse);
    expect(session.showEntry, isTrue);
  });

  test('network error remains error, never empty or business unavailable', () async {
    var retry = false;
    final session = DetailsCommentsSession(source: commentsSource(
      legacy: (a, b, c, d) async => retry
        ? Res([commentFixture('restored')], subData: 1)
        : const Res.error('Timeout: no matching network route')),
      cid: 'work', subId: 'sub');
    addTearDown(session.dispose);
    await session.preload();
    expect(session.controller.error, contains('Timeout'));
    expect(session.controller.confirmedEmpty, isFalse);
    expect(session.controller.unavailable, isFalse);
    expect(session.showEntry, isFalse);
    retry = true;
    await session.controller.refresh();
    expect(session.showEntry, isTrue);
  });

  test('thrown network failure is retained even if text mentions no-match', () async {
    final session = DetailsCommentsSession(source: commentsSource(
      legacy: (a, b, c, d) async => throw StateError('no-match connection failed')),
      cid: 'work', subId: 'sub');
    addTearDown(session.dispose);
    await session.preload();
    expect(session.controller.error, contains('connection failed'));
    expect(session.controller.confirmedEmpty, isFalse);
    expect(session.controller.unavailable, isFalse);
    expect(session.showEntry, isFalse);
  });

  test('late source revision does not expose old match', () async {
    final pending = Completer<Res<List<Comment>>>();
    final source = commentsSource(legacy: (a, b, c, d) => pending.future);
    final session = DetailsCommentsSession(source: source, cid: 'work', subId: 'sub');
    addTearDown(session.dispose);
    final load = session.preload();
    source.data['settings'] = {'changed': true};
    pending.complete(Res([commentFixture('old')], subData: 1));
    await load;
    expect(session.isCurrent, isFalse);
    expect(session.showEntry, isFalse);
    expect(session.controller.error, isNotNull);
    expect(session.controller.confirmedEmpty, isFalse);
  });

  test('late cid/source/subId response cannot become new detail entry', () async {
    final pending = Completer<Res<List<Comment>>>();
    final oldSource = commentsSource(legacy: (a, b, c, d) => pending.future);
    final newSource = commentsSource(legacy: (a, b, c, d) async =>
      const Res([], available: false));
    final old = DetailsCommentsSession(source: oldSource, cid: 'old', subId: 'a');
    final current = DetailsCommentsSession(source: newSource, cid: 'new', subId: 'b');
    addTearDown(current.dispose);
    final oldLoad = old.preload();
    expect(old.matches(oldSource, 'new', 'a'), isFalse);
    expect(old.matches(oldSource, 'old', 'b'), isFalse);
    expect(old.matches(newSource, 'old', 'a'), isFalse);
    old.dispose();
    await current.preload();
    pending.complete(Res([commentFixture('stale')], subData: 1));
    await oldLoad;
    expect(old.controller.comments, isEmpty);
    expect(current.showEntry, isFalse);
  });

  test('owner invalidation notifies borrowers and rejects late generations', () async {
    final pending = Completer<Res<List<Comment>>>();
    final session = DetailsCommentsSession(source: commentsSource(
      legacy: (a, b, c, d) => pending.future), cid: 'work', subId: 'sub');
    expect(session.borrow(), isTrue);
    var invalidations = 0;
    void listener() {
      if (!session.isCurrent) invalidations++;
    }
    session.addListener(listener);
    final load = session.preload();
    try {
      session.dispose();
      session.dispose(); // Owner replacement/unmount must be idempotent.
      expect(session.isCurrent, isFalse);
      expect(session.borrow(), isFalse);
      await Future<void>.value();
      expect(invalidations, 1);
      expect(session.controller.comments, isEmpty);
      pending.complete(Res([commentFixture('late')], subData: 1));
      await load;
      expect(session.controller.comments, isEmpty);
      expect(invalidations, 1, reason: 'late response cannot notify old generation');
    } finally {
      session.removeListener(listener);
      session.releaseBorrow();
      session.dispose();
      await Future<void>.value();
    }
  });

  testWidgets('open borrowed page stops displaying after owner disposal', (tester) async {
    var calls = 0;
    final source = commentsSource(legacy: (a, b, c, d) async {
      calls++;
      return Res([Comment.fromJson({
        'id': 'borrowed-old', 'content': 'borrowed-old',
        'userName': 'Borrower',
      })], subData: 1);
    });
    final session = DetailsCommentsSession(source: source, cid: 'work', subId: 'sub');
    try {
      await session.preload();
      await tester.pumpWidget(MaterialApp(home: CommentsPage(
        data: commentsDetails(), source: source, sharedSession: session)));
      await tester.pumpAndSettle();
      expect(find.text('borrowed-old'), findsOneWidget);
      session.dispose();
      await tester.pumpAndSettle();
      expect(find.text('borrowed-old'), findsNothing);
      expect(session.controller.comments, isEmpty);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('detail probe and full page reuse the same first-page load', (tester) async {
    var calls = 0;
    final pending = Completer<Res<List<Comment>>>();
    final source = commentsSource(legacy: (a, b, c, d) {
      calls++;
      return pending.future;
    });
    final session = DetailsCommentsSession(source: source, cid: 'work', subId: 'sub');
    try {
      final probe = session.preload();
      final joined = session.preload();
      expect(calls, 1);
      await tester.pumpWidget(MaterialApp(home: CommentsPage(
        data: commentsDetails(), source: source, sharedSession: session)));
      expect(calls, 1);
      pending.complete(Res([commentFixture('real')], subData: 1));
      await Future.wait([probe, joined]);
      await tester.pumpAndSettle();
      expect(session.showEntry, isTrue);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(home: CommentsPage(
        data: commentsDetails(), source: source, sharedSession: session)));
      await tester.pumpAndSettle();
      expect(calls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    }
  });
}
