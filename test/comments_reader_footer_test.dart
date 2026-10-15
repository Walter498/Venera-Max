import 'dart:async';
import 'dart:io';
import 'package:venera/foundation/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/components/rich_comment_content.dart';
import 'package:venera/components/comments_feed.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  Widget host(Widget footer, {ScrollController? controller}) => MaterialApp(
    home:Scaffold(body:SingleChildScrollView(controller:controller,child:Column(children:[
      const SizedBox(height:1200,child:Text('Comic pages')),
      footer,
    ]))));

  for(final count in [1,3,4,9]) {
    testWidgets('natural footer keeps ${count > 4 ? 4 : count} of $count without a nested scroll or pagination', (tester) async {
      final pages=<int>[];
      final source=commentsSource(chapterLegacy:(id,ep,page,reply) async {
        pages.add(page);
        return Res([for(var i=0;i<count;i++) commentFixture('topic-$i',preview:false)],subData:3,total:30);
      });
      final scroll=ScrollController();
      await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
        comicTitle:'Work',chapterTitle:'Chapter'),controller:scroll));
      await tester.pumpAndSettle();
      final footer=find.byType(ChapterCommentsPreview);
      expect(find.descendant(of:footer,matching:find.byType(Scrollable)),findsNothing);
      expect(find.descendant(of:footer,matching:find.byType(CommentsFeed)),findsNothing);
      expect(find.descendant(of:footer,matching:find.byType(Offstage)),findsNothing);
      expect(find.byType(CommentPresentation),findsNWidgets(count > 4 ? 4 : count));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(pages,[1]);
      expect(find.text('加载更多评论'),findsNothing);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());scroll.dispose();
    });
  }

  for (final rich in [false, true]) {
    testWidgets('preview body and reply drag parent chapter scroll rich=$rich', (tester) async {
      final body = rich ? '<b>Body 😀 [unknown-emoji]</b><br>Second line'
          : 'Body 😀 [unknown-emoji]\nSecond line';
      final reply = rich ? '<i>Reply 😀 [unknown-emoji]</i><br>Second line'
          : 'Reply 😀 [unknown-emoji]\nSecond line';
      final source = commentsSource(chapterLegacy: (id, ep, page, parent) async => Res([
        Comment.fromJson({'id':'drag', 'userName':'Author', 'content':body,
          'replyPreview':{'id':'drag-reply', 'userName':'Reply author', 'content':reply}}),
      ], subData:1));
      final scroll = ScrollController();
      try {
        await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
          comicTitle:'Work',chapterTitle:'Chapter'),controller:scroll));
        await tester.pumpAndSettle();
        final footer = find.byType(ChapterCommentsPreview);
        expect(find.descendant(of:footer,matching:find.byType(Scrollable)),findsNothing);
        expect(find.descendant(of:footer,matching:find.byType(SelectableText)),findsNothing);
        expect(find.byType(CommentContent),findsNWidgets(2));
        for (final text in [body, reply]) {
          final content = find.byWidgetPredicate((w) => w is CommentContent && w.text == text);
          expect(tester.widget<CommentContent>(content).selectable,isFalse);
          final naturalText = find.descendant(of:content,matching:find.byType(Text));
          expect(naturalText,findsOneWidget);
          final rendered = tester.widget<Text>(naturalText);
          expect(rendered.data ?? rendered.textSpan!.toPlainText(),
            text == body ? 'Body 😀 [unknown-emoji]\nSecond line'
                : 'Reply 😀 [unknown-emoji]\nSecond line');
          if (rich) {
            final spans = (rendered.textSpan! as TextSpan).children!.cast<TextSpan>();
            if (text == body) {
              expect(spans.first.style?.fontWeight,FontWeight.bold);
            } else {
              expect(spans.first.style?.fontStyle,FontStyle.italic);
            }
          }
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(content.hitTestable(),findsOneWidget);
          final before = scroll.offset;
          await tester.drag(content,const Offset(0,120));
          await tester.pumpAndSettle();
          expect(scroll.offset,lessThan(before));
          expect(tester.takeException(),isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
      }
    });
  }

  testWidgets('full-page presentation still defaults to selectable plain and rich body/reply', (tester) async {
    for (final rich in [false, true]) {
      final body = rich ? '<b>Selectable body</b>' : 'Selectable body';
      final reply = rich ? '<i>Selectable reply</i>' : 'Selectable reply';
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:CommentPresentation(
        comment:Comment.fromJson({'id':'full','userName':'Author','content':body,
          'replyPreview':{'id':'reply','userName':'Reply author','content':reply}})))));
      await tester.pumpAndSettle();
      expect(tester.widget<CommentPresentation>(find.byType(CommentPresentation)).selectable,isTrue);
      expect(tester.widgetList<CommentContent>(find.byType(CommentContent))
        .every((content) => content.selectable),isTrue);
      expect(find.byType(SelectableText),findsNWidgets(2));
      expect(tester.takeException(),isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('chapter load hook starts before a lazy preview exists and joins the shared feed', (tester) async {
    final response=Completer<Res<List<Comment>>>();
    final calls=<String>[];
    final source=commentsSource(chapterLegacy:(id,ep,page,reply) {
      calls.add('$ep:$page');return response.future;
    });
    final scope=ReaderChapterCommentsFeeds();
    final feed=scope.chapterLoading(source,'work','first');
    expect(calls,['first:1']);
    expect(identical(scope.chapterLoading(source,'work','first'),feed),isTrue);
    expect(find.byType(ChapterCommentsPreview),findsNothing);
    await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'first',source:source,
      sharedFeed:feed,comicTitle:'Work',chapterTitle:'First')));
    await tester.pump();
    expect(calls,['first:1']);
    response.complete(Res([commentFixture('first-topic')],subData:2));
    await tester.pumpAndSettle();
    expect(find.byType(CommentPresentation),findsOneWidget);
    expect(calls,['first:1']);
    await tester.pumpWidget(const SizedBox.shrink());scope.dispose();
  });

  testWidgets('switch chapter and source revision ignore stale generation responses', (tester) async {
    final pending=<String,Completer<Res<List<Comment>>>>{};
    final source=commentsSource(chapterLegacy:(id,ep,page,reply) {
      final key='$ep:${sourceRevision++}';
      return (pending[key]=Completer<Res<List<Comment>>>()).future;
    });
    final scope=ReaderChapterCommentsFeeds();
    final a=scope.chapterLoading(source,'work','a');
    await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'a',source:source,
      sharedFeed:a,comicTitle:'Work',chapterTitle:'A')));
    final b=scope.chapterLoading(source,'work','b');
    await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'b',source:source,
      sharedFeed:b,comicTitle:'Work',chapterTitle:'B')));
    final keys=pending.keys.toList();
    pending[keys[1]]!.complete(Res([commentFixture('fresh-b')],subData:1));
    pending[keys[0]]!.complete(Res([commentFixture('stale-a')],subData:1));
    await tester.pumpAndSettle();
    expect(tester.widget<CommentPresentation>(find.byType(CommentPresentation)).comment.id,'fresh-b');
    source.data['settings']={'revision':'changed'};
    final revised=scope.chapterLoading(source,'work','b');
    expect(identical(revised,b),isFalse);
    await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'b',source:source,
      sharedFeed:revised,comicTitle:'Work',chapterTitle:'B')));
    pending[pending.keys.last]!.complete(Res([commentFixture('revised-b')],subData:1));
    await tester.pumpAndSettle();
    expect(tester.widget<CommentPresentation>(find.byType(CommentPresentation)).comment.id,'revised-b');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());scope.dispose();
  });

  testWidgets('footer reply preview navigates with the parent id', (tester) async {
    final previousPlatform=debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
    final replies=<String?>[];
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(canLoadReplies:true),
      chapterOptions:(id,ep,page,reply,options) async {
        replies.add(reply);return Res([commentFixture(reply==null ? 'parent-topic' : 'reply',
          preview:reply==null)],subData:1);
      });
    await tester.pumpWidget(MaterialApp(theme:ThemeData(platform:TargetPlatform.iOS),
      home:Scaffold(body:SingleChildScrollView(child:ChapterCommentsPreview(
        comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter')))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看回复详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看回复详情'));await tester.pumpAndSettle();
    expect(replies,[null,'parent-topic']);expect(find.text('评论详情'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride=previousPlatform;
    }
  });

  testWidgets('real sort replacement still has four tiles and no more-page requests', (tester) async {
    final oldPath = App.dataPath;
    final temp = await tester.runAsync(() => Directory.systemTemp.createTemp('sort-footer-'));
    App.dataPath = temp!.path;
    addTearDown(() async { App.dataPath = oldPath; await temp.delete(recursive: true); });
    final calls=<String>[];
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(
      sorts:['new','hot'],defaultSort:'new'),chapterOptions:(id,ep,page,reply,options) async {
        calls.add('${options['sort']}:$page');
        return Res([for(var i=0;i<8;i++) commentFixture('${options['sort']}-$i',preview:false)],subData:3);
      });
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter')))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CommentSortSelector));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('最热').last);
      await source.saveData();
    });
    await tester.pumpAndSettle();
    expect(calls,['new:1','hot:1']);expect(find.byType(CommentPresentation),findsNWidgets(4));
    expect(tester.widget<CommentPresentation>(find.byType(CommentPresentation).first).comment.id,'hot-0');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('production chapter-load entry issues one comment hook before image completion', (tester) async {
    final calls=<String>[];
    final images=Completer<List<String>>();
    final comments=Completer<Res<List<Comment>>>();
    final source=commentsSource(chapterLegacy:(id,ep,page,reply) {
      calls.add('comments:$ep:$page');return comments.future;
    });
    final scope=ReaderChapterCommentsFeeds();
    final loading=loadReaderChapter<List<String>>(
      prefetchComments:()=>scope.chapterLoading(source,'work','ep'),
      loadImages:() {calls.add('images:ep');return images.future;});
    expect(calls,['comments:ep:1','images:ep']);
    expect(find.byType(ChapterCommentsPreview),findsNothing);
    final feed=scope.chapterLoading(source,'work','ep');
    await tester.pumpWidget(host(ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
      sharedFeed:feed,comicTitle:'Work',chapterTitle:'Chapter')));
    await tester.pump();
    expect(calls,['comments:ep:1','images:ep']);
    images.complete(['image']);expect(await loading,['image']);
    comments.complete(Res([commentFixture('loaded')],subData:1));
    await tester.pumpAndSettle();expect(find.byType(CommentPresentation),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());scope.dispose();
  });

  for(final axis in [Axis.vertical,Axis.horizontal]) {
    for(final reverse in axis==Axis.vertical ? [false] : [false,true]) {
      testWidgets('complete footer tail is the endpoint for $axis reverse=$reverse', (tester) async {
        tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final scroll=ScrollController();final viewportKey=GlobalKey();final footerKey=GlobalKey();
        final source=commentsSource(chapterLegacy:(a,b,c,d) async => Res([
          for(var i=0;i<4;i++) commentFixture('end-$i')],subData:2));
        final footer=ChapterCommentsPreview(key:footerKey,comicId:'work',epId:'ep',source:source,
          comicTitle:'Work',chapterTitle:'Chapter',horizontal:axis==Axis.horizontal,reverse:reverse);
        final children=<Widget>[
          SizedBox(width:axis==Axis.horizontal ? 1200 : 390,height:axis==Axis.vertical ? 1200 : 844),footer];
        await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(key:viewportKey,
          child:SingleChildScrollView(controller:scroll,scrollDirection:axis,reverse:reverse,
            child:axis==Axis.vertical ? Column(children:children) : Row(
              textDirection:reverse ? TextDirection.rtl : TextDirection.ltr,children:children))))));
        await tester.pumpAndSettle();
        bool reached() => readerFooterReachedEnd(footer:tester.getRect(find.byKey(footerKey)),
          viewport:tester.getRect(find.byKey(viewportKey)),axis:axis,reverse:reverse);
        expect(reached(),isFalse);
        scroll.jumpTo(1200);await tester.pumpAndSettle();
        // The comic's end alone must not count as the full footer's end.
        expect(reached(),isFalse);
        scroll.jumpTo(scroll.position.maxScrollExtent);await tester.pumpAndSettle();
        expect(reached(),isTrue);
        expect(find.descendant(of:find.byKey(footerKey),matching:find.byType(Scrollable)),findsNothing);
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox.shrink());scroll.dispose();
      });
    }
  }

  for(final reverse in [false,true]) {
    testWidgets('horizontal 844x390 200% panels keep reply reachable reverse=$reverse', (tester) async {
      tester.view.physicalSize=const Size(844,390);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final scroll=ScrollController();
      final source=commentsSource(chapterCapabilities:const CommentCapabilities(canLoadReplies:true),
        chapterLegacy:(a,b,c,d) async => Res([for(var i=0;i<4;i++) Comment.fromJson({
          'id':'panel-$i','userName':List.filled(40,'长昵称').join(),
          'time':List.filled(30,'2026年10月14日').join(),
          'content':List.filled(90,'正文预览').join(),'replyCount':2,'score':12,
          'replyPreview':{'id':'r-$i','content':List.filled(90,'回复预览').join()},
        })],subData:3));
      try {
        await tester.pumpWidget(MaterialApp(home:Scaffold(body:MediaQuery(
          data:const MediaQueryData(size:Size(844,390),textScaler:TextScaler.linear(2)),
          child:SingleChildScrollView(controller:scroll,scrollDirection:Axis.horizontal,reverse:reverse,
            child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,comicTitle:'Work',
              chapterTitle:List.filled(80,'长章节标题').join(),horizontal:true,reverse:reverse))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        final footer=find.byType(ChapterCommentsPreview);
        expect(find.descendant(of:footer,matching:find.byType(Scrollable)),findsNothing);
        expect(find.byType(CommentReadOnlyStats),findsNWidgets(4));
        scroll.jumpTo(844*3); await tester.pumpAndSettle();
        expect(find.byIcon(Icons.chat_bubble_outline).hitTestable(),findsOneWidget);
        scroll.jumpTo(scroll.position.maxScrollExtent); await tester.pumpAndSettle();
        expect(find.text('View all comments').hitTestable(),findsOneWidget);
        expect(tester.takeException(),isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());scroll.dispose();
      }
    });
  }
}
int sourceRevision=0;
