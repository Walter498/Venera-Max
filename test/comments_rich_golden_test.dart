import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/comment_context_stats.dart';
import 'package:venera/components/comment_presentation.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'comments_fixtures.dart';

// Fresh baselines only: these four files require explicit visual review.
// Do not update the existing thread/chapter/footer golden files for this suite.
void main() {
  setUpCommentsTestHost();
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final scale in [1.0, 2.0]) {
      final mode = brightness == Brightness.light ? 'light' : 'dark';
      final percent = (scale * 100).toInt();
      testWidgets('rich natural footer $mode $percent', (tester) async {
        final oldPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 5000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          final mother = Comment.fromJson({
            'id': 'rich-parent', 'userName': '真实昵称与自然换行 Reader',
            'content': '章末真实评论内容，自然高度显示。仅展示来源提供的数据，不补等级、浏览量或回复。',
            'time': '2026-10-15 21:00', 'userLevel': 45,
            'viewCount': 1197000, 'badges': ['热评', '关联作品：真实作品名'],
            'score': 32, 'replyCount': 24,
            'replyPreviews': [
              {'id': 'reply-a', 'userName': '回复读者甲', 'time': '2026-10-15 20:59',
                'content': '第一条真实回复，保留昵称、日期和内容。'},
              {'id': 'reply-b', 'userName': '回复读者乙', 'time': '2026-10-15 20:58',
                'content': '第二条真实回复，不合成额外数据。'},
            ],
          });
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness, platform: TargetPlatform.iOS,
              useMaterial3: true, fontFamily: 'CommentsLatin',
              fontFamilyFallback: const ['CommentsCJK']),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
            home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(
              key: boundary, child: ColoredBox(
                color: brightness == Brightness.light ? Colors.white : const Color(0xff141218),
                child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const CommentContextStats(context: {'provider': 'tencent',
                      'comicFavoriteCount': 833267, 'chapterLikeCount': 19537}),
                    CommentPresentation(comment: mother, selectable: false, onReply: () {}),
                    for (var i = 1; i < 4; i++) CommentPresentation(selectable: false,
                      comment: Comment.fromJson({'id': 'plain-$i', 'userName': '读者 $i',
                        'content': '普通母评论 $i：未知等级和浏览量应隐藏。',
                        'time': '2026-10-15'})),
                  ]),
              ),
            ))),
          ));
          await tester.pumpAndSettle();
          expect(find.byType(CommentPresentation), findsNWidgets(4));
          expect(find.text('Lv45'), findsOneWidget);
          expect(find.byTooltip('浏览量 1197000'), findsOneWidget);
          expect(find.text('收藏83.3万'), findsOneWidget);
          expect(find.text('本章获赞2万'), findsOneWidget);
          expect(find.byTooltip('本章获赞 19537'), findsOneWidget);
          expect(find.text('查看回复详情'), findsNWidgets(2));
          expect(find.byType(SelectableText), findsNothing);
          expect(find.byType(Scrollable), findsOneWidget); // Outer only.
          expect(tester.getSize(find.byKey(boundary)).width, 390);
          expect(tester.takeException(), isNull);
          await expectLater(find.byKey(boundary), matchesGoldenFile(
            'goldens/comments/rich_${mode}_$percent.png'));
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          debugDefaultTargetPlatformOverride = oldPlatform;
        }
      });
    }
  }
}
