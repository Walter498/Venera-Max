import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/widget_utils.dart';
import 'package:venera/utils/translations.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/pages/reader/reader.dart';
import 'comments_fixtures.dart';

// Actual fa7afe19 whole footer layout, independently rendered at identical width.
Widget legacyFooter(List<Comment> rows) => Padding(
  padding:const EdgeInsets.fromLTRB(16,18,16,18),
  child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[const Icon(Icons.chat_bubble_outline_rounded,size:20),
      const SizedBox(width:8),Expanded(child:Text('Chapter Comments'.tl,style:ts.s18)),
      TextButton(onPressed:(){},child:Text('View all comments'.tl))]),
    Text('Chapter',style:ts.s12),const SizedBox(height:10),
    for(final c in rows.take(3)) Padding(padding:const EdgeInsets.symmetric(vertical:8),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(c.userName,style:const TextStyle(fontWeight:FontWeight.w600)),
        if(c.time!=null) Text(c.time!,style:ts.s12),
        Text(c.content,maxLines:3,overflow:TextOverflow.ellipsis),
      ])),
    const SizedBox(height:8),
    OutlinedButton.icon(onPressed:(){},icon:const Icon(Icons.edit_outlined,size:18),
      label:Text('View comments and reply'.tl)),
  ]));

void main() {
  for(final size in [const Size(390,844),const Size(844,390)]) {
    for(final brightness in [Brightness.light,Brightness.dark]) {
      for(final fontScale in [1.0,2.0]) {
        testWidgets('fa7afe19 real list baseline $size $brightness $fontScale', (tester) async {
          tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
          addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
          final old=appdata.settings['chapterCommentsHeightScale'];
          addTearDown(() => appdata.settings['chapterCommentsHeightScale']=old);
          appdata.settings['chapterCommentsHeightScale']=1.0;
          appdata.settings['language']='en-US';
          final rows=[for(var i=0;i<3;i++) commentFixture('legacy-$i',preview:false)];
          final source=commentsSource(chapterLegacy:(a,b,c,d) async => Res(rows,subData:1));
          final baseline=GlobalKey();
          await tester.pumpWidget(MaterialApp(theme:ThemeData(platform:TargetPlatform.iOS,
            brightness:brightness,useMaterial3:true),
            builder:(context,child) => MediaQuery(data:MediaQuery.of(context).copyWith(
              textScaler:TextScaler.linear(fontScale)),child:child!),
            home:Scaffold(body:SingleChildScrollView(child:Column(children:[
              SizedBox(key:baseline,child:legacyFooter(rows)),
              ChapterCommentsPreview(comicId:'work',epId:'ep',source:source,
                comicTitle:'Work',chapterTitle:'Chapter'),
            ])))));
          await tester.pumpAndSettle();
          final legacy=tester.getSize(find.byKey(baseline)).height;
          expect(tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height,closeTo(legacy,0.01));
          appdata.settings['chapterCommentsHeightScale']=2.0;
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byKey(const ValueKey('chapter-comments-region'))).height,closeTo(legacy*2,0.01));
          expect(tester.takeException(),isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
