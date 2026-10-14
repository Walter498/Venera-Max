import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/components/comments_feed.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

void main() {
  setUp(() { appdata.settings['language']='en-US'; });
  testWidgets('missing avatar is an explicit generic person and stats are readonly', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CommentPresentation(
      comment:commentFixture('topic',score:0,replies:0)))));
    expect(find.byIcon(Icons.person_outline),findsOneWidget);
    expect(find.text('0'),findsNWidgets(2));
    expect(find.byType(TextButton),findsNothing);
    expect(find.text('3年前'),findsOneWidget);
    expect(find.textContaining('genuine preview'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('preview reply navigation requests parent id, not preview id', (tester) async {
    debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride=null);
    final replies=<String?>[];
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(canLoadReplies:true),
      chapterOptions:(id,ep,page,reply,options) async {
        replies.add(reply);
        return Res(reply == null ? [commentFixture('topic-A')] : [commentFixture('reply',preview:false)],subData:1,total:1);
      });
    await tester.pumpWidget(MaterialApp(home:ChapterCommentsPage(
      comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看回复详情')); await tester.pumpAndSettle();
    expect(replies,[null,'topic-A']);
    expect(find.text('评论详情'),findsOneWidget);
    expect(find.text('回复列表'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('actual chapter sort selection invokes the page options hook', (tester) async {
    final requested=<String?>[];
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(
      sorts:['new','hot','wonderful'],defaultSort:'new',canLoadReplies:false),
      chapterOptions:(id,ep,page,reply,options) async {
        requested.add(options['sort'] as String?);
        return Res([commentFixture(options['sort'].toString(),preview:false)],subData:1);
      });
    await tester.pumpWidget(MaterialApp(home:ChapterCommentsPage(
      comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter')));
    await tester.pumpAndSettle();await tester.tap(find.text('最热'));await tester.pumpAndSettle();
    await tester.tap(find.text('精彩'));await tester.pumpAndSettle();
    expect(requested,['new','hot','wonderful']);
    expect(find.text('查看回复详情'),findsNothing);expect(tester.takeException(),isNull);
  });
  testWidgets('actual footer doubles whole region and reacts to persisted scale', (tester) async {
    tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final old=appdata.settings['chapterCommentsHeightScale'];
    addTearDown(() => appdata.settings['chapterCommentsHeightScale']=old);
    final source=commentsSource(chapterLegacy:(id,ep,page,reply) async =>
      Res([for(var i=0;i<3;i++) commentFixture('topic-$i',preview:false)],subData:1));
    appdata.settings['chapterCommentsHeightScale']=1.0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
        comicTitle:'Work',chapterTitle:'Chapter')))));
    await tester.pumpAndSettle();
    final legacy=tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height;
    expect(legacy,greaterThan(0));
    appdata.settings['chapterCommentsHeightScale']=2.0;await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height,closeTo(legacy*2,0.01));
    appdata.settings['chapterCommentsHeightScale']=0.5;await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height,closeTo(legacy*0.5,0.01));
    expect(tester.takeException(),isNull);
  });
  testWidgets('successful empty footer hides but error footer keeps retry', (tester) async {
    var fail=true;
    final source=commentsSource(chapterLegacy:(id,ep,page,reply) async =>
      fail ? const Res.error('offline') : const Res([],subData:0,total:0));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
        comicTitle:'Work',chapterTitle:'Chapter')))));
    await tester.pumpAndSettle();expect(find.text('重试'),findsOneWidget);
    fail=false;await tester.tap(find.text('重试'));await tester.pumpAndSettle();
    expect(find.byType(CommentsFeed),findsNothing);expect(tester.takeException(),isNull);
  });
  testWidgets('disabled capability produces no footer UI', (tester) async {
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(enabled:false),
      chapterLegacy:(id,ep,page,reply) async => const Res([],subData:0));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ChapterCommentsPreview(
      comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter'))));
    await tester.pumpAndSettle();expect(find.byType(CommentsFeed),findsNothing);
  });
  testWidgets('error retry in the actual feed restores content', (tester) async {
    var requests=0;
    final feed=CommentsController(loader:(page,sort) async => requests++==0 ?
      const Res.error('offline') : Res([commentFixture('recovered')],subData:1));
    await feed.refresh();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CommentsFeed(
      controller:feed,itemBuilder:(c)=>CommentPresentation(comment:c)))));
    await tester.tap(find.text('重试')); await tester.pumpAndSettle();
    expect(find.text('offline'),findsNothing);expect(find.byType(CommentPresentation),findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());feed.dispose();
  });

  testWidgets('runtime unavailable hides actual footer despite a real declared hook', (tester) async {
    final source=commentsSource(chapterCapabilities:const CommentCapabilities(sorts:['new']),
      chapterOptions:(a,b,c,d,e) async => const Res([],subData:0,total:0,available:false));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ChapterCommentsPreview(
      comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter'))));
    await tester.pumpAndSettle();
    expect(find.byType(CommentsFeed),findsNothing); expect(find.text('暂无评论'),findsNothing);
    expect(find.text('重试'),findsNothing); expect(tester.takeException(),isNull);
  });
  for (final brightness in [Brightness.light,Brightness.dark]) {
    for (final fontScale in [1.0,2.0]) {
      testWidgets('real footer iOS $brightness font $fontScale viewport doubles', (tester) async {
        debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride=null);
        tester.view.physicalSize=const Size(390,844); tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        final previous=appdata.settings['chapterCommentsHeightScale'];
        addTearDown(() => appdata.settings['chapterCommentsHeightScale']=previous);
        final source=commentsSource(chapterCapabilities:const CommentCapabilities(canLoadReplies:true),
          chapterLegacy:(id,ep,page,reply) async => Res([
            for(var i=0;i<6;i++) commentFixture('topic-$i')],subData:1,total:6));
        appdata.settings['chapterCommentsHeightScale']=1.0;
        await tester.pumpWidget(MaterialApp(theme:ThemeData(platform:TargetPlatform.iOS,
          brightness:brightness,useMaterial3:true),
          builder:(context,child) => MediaQuery(data:MediaQuery.of(context).copyWith(
            textScaler:TextScaler.linear(fontScale)),child:child!),
          home:Scaffold(body:SingleChildScrollView(child:ChapterCommentsPreview(
            comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter'))))));
        await tester.pumpAndSettle();
        final legacy=tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height;
        expect(legacy,greaterThan(0));
        expect(find.byType(CommentPresentation),findsWidgets);
        expect(find.textContaining('genuine preview'),findsWidgets);
        appdata.settings['chapterCommentsHeightScale']=2.0;
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height,closeTo(legacy*2,0.01));
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

}
