import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

void main() {
  setUpCommentsTestHost();
  for(final brightness in [Brightness.light,Brightness.dark]) {
    for(final scale in [1.0,2.0]) {
      final mode=brightness==Brightness.light ? 'light' : 'dark';
      final percent=(scale*100).toInt();
      testWidgets('real natural footer $mode $percent', (tester) async {
        final previous=debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
        try {
          tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
          addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
          final source=commentsSource(chapterCapabilities:const CommentCapabilities(
            sorts:['new','hot','wonderful'],defaultSort:'new',canLoadReplies:true),
            chapterOptions:(id,ep,page,reply,options) async => Res([
              for(var i=0;i<6;i++) commentFixture('footer-$i',preview:i==0)],subData:3,total:60));
          final boundary=GlobalKey();
          await tester.pumpWidget(MaterialApp(theme:ThemeData(brightness:brightness,
            platform:TargetPlatform.iOS,useMaterial3:true,
            fontFamily:'CommentsLatin',fontFamilyFallback:const ['CommentsCJK']),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(
              textScaler:TextScaler.linear(scale)),child:child!),
            home:Scaffold(body:SingleChildScrollView(child:RepaintBoundary(key:boundary,
              child:ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
                comicTitle:'Fixture work',chapterTitle:'Chapter with a long title and preserved context'))))));
          await tester.pumpAndSettle();
          expect(find.byType(CommentPresentation),findsNWidgets(4));
          expect(find.descendant(of:find.byKey(boundary),matching:find.byType(Scrollable)),findsNothing);
          expect(tester.takeException(),isNull);
          // Capture the whole real component, not just a clipped initial viewport.
          // No baseline is fabricated here. Root must inspect fresh captures before approval.
          await expectLater(find.byKey(boundary),matchesGoldenFile(
            'goldens/comments/footer_${mode}_$percent.png'));
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride=previous;
        }
      });
    }
  }
}
