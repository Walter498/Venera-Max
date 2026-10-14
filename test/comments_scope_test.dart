import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comments_feed.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  test('options-only without declaration is not an executable loader', () {
    final source=commentsSource(
      options:(a,b,c,d,e) async => const Res([],subData:0),
      chapterOptions:(a,b,c,d,e) async => const Res([],subData:0));
    expect(source.hasComments,isFalse); expect(source.hasChapterComments,isFalse);
  });
  testWidgets('same source settings mutation invalidates old chapter response', (tester) async {
    final slow=Completer<Res<List<Comment>>>();
    var count=0;
    final source=commentsSource(chapterLegacy:(a,b,c,d) async {
      if (count++==0) return slow.future;
      return Res([commentFixture('new-scope',preview:false)],subData:1);
    });
    Widget page() => MaterialApp(home:ChapterCommentsPage(key:const ValueKey('scope'),
      comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter'));
    await tester.pumpWidget(page()); await tester.pump();
    source.data['settings']={'scope':'changed'};
    await tester.pumpWidget(page()); await tester.pumpAndSettle();
    slow.complete(Res([commentFixture('old-scope',preview:false)],subData:1));
    await tester.pumpAndSettle();
    final feed=tester.widget<CommentsFeed>(find.byType(CommentsFeed)).controller;
    expect(feed.comments.single.id,'new-scope'); expect(count,2);
    expect(tester.takeException(),isNull);
  });
  testWidgets('footer uses caller controller and refresh cannot get overwritten by old empty', (tester) async {
    final stale=Completer<Res<List<Comment>>>();
    var calls=0;
    final feed=CommentsController(loader:(a,b) async => calls++==0 ? stale.future :
      Res([commentFixture('current',preview:false)],subData:1));
    final old=feed.refresh();
    final source=commentsSource(chapterLegacy:(a,b,c,d) async => throw StateError('duplicate request'));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
        comicTitle:'Work',chapterTitle:'Chapter',sharedFeed:feed)))));
    await feed.refresh(); await tester.pumpAndSettle();
    stale.complete(const Res([],subData:0,total:0)); await old; await tester.pumpAndSettle();
    expect(feed.comments.single.id,'current'); expect(feed.confirmedEmpty,isFalse);
    expect(find.byType(CommentsFeed),findsOneWidget); expect(calls,2);
    expect(identical(tester.widget<CommentsFeed>(find.byType(CommentsFeed)).controller,feed),isTrue);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink()); feed.dispose();
  });
}
