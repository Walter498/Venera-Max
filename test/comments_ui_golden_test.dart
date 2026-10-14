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
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
          brightness: brightness, platform:TargetPlatform.iOS, useMaterial3:true),
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
        // No FlutterError suppression: overflow/layout errors fail the test.
        await tester.pumpWidget(const SizedBox.shrink());
      });
      }
    }
  }
}
