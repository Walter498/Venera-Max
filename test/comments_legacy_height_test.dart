import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

// The old fa7afe19 1x/2x + Offstage contract was explicitly superseded.
// Retain the real theme/width/text-scale matrix and overflow assertions;
// persisted multipliers must now be inert, with four natural preview tiles.
void main() {
  setUpCommentsTestHost();
  for(final size in [const Size(390,844),const Size(844,390)]) {
    for(final brightness in [Brightness.light,Brightness.dark]) {
      for(final fontScale in [1.0,2.0]) {
        testWidgets('fixed footer compatibility $size $brightness $fontScale', (tester) async {
          tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
          addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
          final old=appdata.settings['chapterCommentsHeightScale'];
          addTearDown(() => appdata.settings['chapterCommentsHeightScale']=old);
          appdata.settings['chapterCommentsHeightScale']=1.0;
          final rows=[for(var i=0;i<8;i++) commentFixture('compat-$i',preview:false)];
          final source=commentsSource(chapterLegacy:(a,b,c,d) async => Res(rows,subData:3));
          await tester.pumpWidget(MaterialApp(theme:ThemeData(platform:TargetPlatform.iOS,
            brightness:brightness,useMaterial3:true),
            builder:(context,child) => MediaQuery(data:MediaQuery.of(context).copyWith(
              textScaler:TextScaler.linear(fontScale)),child:child!),
            home:Scaffold(body:SingleChildScrollView(child:ChapterCommentsPreview(
              comicId:'work',epId:'ep',source:source,comicTitle:'Work',chapterTitle:'Chapter')))));
          await tester.pumpAndSettle();
          final region=find.byKey(const ValueKey('chapter-comments-region'));
          final natural=tester.getSize(region).height;
          expect(natural,greaterThan(0));
          expect(find.byType(CommentPresentation),findsNWidgets(4));
          expect(find.descendant(of:region,matching:find.byType(Scrollable)),findsNothing);
          expect(find.descendant(of:region,matching:find.byType(Offstage)),findsNothing);
          for(final scale in [0.5,2.0,4.0]) {
            appdata.settings['chapterCommentsHeightScale']=scale;
            await tester.pumpAndSettle();
            expect(tester.getSize(region).height,closeTo(natural,0.01));
          }
          expect(tester.takeException(),isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
