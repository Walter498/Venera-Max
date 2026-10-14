import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  for (final brightness in [Brightness.light,Brightness.dark]) {
    for (final scale in [1.0,2.0]) {
      final mode = brightness == Brightness.light ? 'light' : 'dark';
      final percent = (scale * 100).toInt();
      for (final thread in [true,false]) {
      final scenario = thread ? 'thread' : 'chapter_sort';
      testWidgets('real chapter $scenario $mode $percent', (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // Flutter checks foundation invariants before addTearDown callbacks.
        try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390,844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        appdata.settings['language'] = 'en-US';
        final source = commentsSource(
          chapterCapabilities: const CommentCapabilities(sorts:['new','hot','wonderful'],
            defaultSort:'new',canLoadReplies:true),
          chapterOptions:(id,ep,page,reply,options) async => Res([
            commentFixture('reply-1',preview:!thread),
            commentFixture('reply-2',preview:false,score:0,replies:0),
          ],subData:2,total:6));
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(theme: ThemeData(
          brightness: brightness, platform:TargetPlatform.iOS, useMaterial3:true,
          fontFamily:'CommentsLatin', fontFamilyFallback:const ['CommentsCJK']),
          builder:(context,child) => MediaQuery(data:MediaQuery.of(context).copyWith(
            textScaler:TextScaler.linear(scale)),child:child!),
          home: RepaintBoundary(key:boundary,child:ChapterCommentsPage(
            comicId:'work',epId:'chapter',source:source,comicTitle:'Fixture work',
            chapterTitle:'Chapter with a long title and preserved context',
            replyComment:thread ? commentFixture('parent-topic',replies:6) : null))));
        await tester.pumpAndSettle();
        expect(tester.takeException(),isNull);
        if (thread) {
          expect(find.text('评论详情'),findsOneWidget);
        } else {
          expect(find.text('最新'),findsOneWidget);
          expect(find.text('最热'),findsOneWidget);
          expect(find.text('精彩'),findsOneWidget);
          expect(find.text('查看回复详情'),findsOneWidget);
        }
        expect(tester.getSize(find.byKey(boundary)),const Size(390,844));
        await expectLater(find.byKey(boundary),matchesGoldenFile(
          'goldens/comments/${scenario}_${mode}_$percent.png'));
        if (scale == 2.0) {
          // Capture remains the initial viewport, then exercise the actual
          // lazy list. At 200% a reply action must be reachable, not clipped
          // permanently below the parent/long-nickname content.
          final replyAction = thread
            ? find.byIcon(Icons.insert_comment_outlined).first
            : find.text('查看回复详情');
          final scrollable = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(replyAction, 180,
            scrollable:scrollable, maxScrolls:40);
          await tester.pumpAndSettle();
          expect(replyAction.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        // No FlutterError suppression: overflow/layout errors fail the test.
        await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });
      }
    }
  }
}
